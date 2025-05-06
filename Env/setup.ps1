param(
    [string]$InstallPath = $null
)

# Set silent progress and error preferences.
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# --- Global variable for the main log file path ---
$LogFilePath = $null

# --- Logging Function ---
function Write-Log {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR", "FATAL")]
        [string]$Level = "INFO"
    )
    process {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"

        if ($LogFilePath -ne $null) {
            try {
                $logEntry | Out-File -FilePath $LogFilePath -Append -Encoding UTF8 -ErrorAction Stop
            } catch {
                Write-Host "LOGGING ERROR: Could not write to '$LogFilePath'. Fallback needed. Error: $_"
                $fallbackErrorLog = Join-Path $env:TEMP "app_install_fallback_error.log"
                $logEntry | Out-File -FilePath $fallbackErrorLog -Append -Encoding UTF8
            }
        } else {
            Write-Host $logEntry
        }
    }
}

# --- Fallback Error Log Path (for very early errors) ---
$EarlyErrorLogPath = Join-Path $env:TEMP "app_install_early_error_$(Get-Date -Format 'yyyyMMddHHmmss').log"

try {
    # --- Determine target installation directory ---
    if ($InstallPath -eq $null -or $InstallPath -eq "" -or (-not (Test-Path $InstallPath -PathType Container))) {
        $errorMsg = "FATAL: Invalid or missing installation path provided via -InstallPath parameter. Value received: '$InstallPath'"
        Write-Host $errorMsg
        $errorMsg | Out-File -FilePath $EarlyErrorLogPath -Append -Encoding UTF8
        exit 1
    } else {
        $targetDir = Resolve-Path -Path $InstallPath
        $timestampForLog = Get-Date -Format "yyyyMMdd-HHmmss"
        $LogFilePath = Join-Path $targetDir "InstallationLog_$timestampForLog.txt"
        if (Test-Path $LogFilePath) {
            Remove-Item $LogFilePath -Force
        }
        Write-Log "Target installation directory confirmed: $targetDir"
        Write-Log "Log file initialized at: $LogFilePath"
        if (-Not (Test-Path $targetDir)) {
            Write-Log "Creating installation directory: $targetDir"
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
    }

    # --- Start Logging ---
    Write-Log "=== Starting setup/update ==="
    Write-Log "Timestamp: $(Get-Date)"
    Write-Log "Running with user: $env:USERNAME"
    Write-Log "Current directory: $(Get-Location)"
    Write-Log "InstallPath parameter received: '$InstallPath'"

    # --- Helper functions ---
    function Compare-Versions($v1, $v2) {
        try {
            $ver1 = [version]$v1
            $ver2 = [version]$v2
            return $ver1.CompareTo($ver2)
        }
        catch {
            Write-Log "Version comparison failed: $_" -Level WARN
            return 0 
        }
    }

    # Determine the folder where this script is located (within SetupFiles).
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    Write-Log "Script directory (SetupFiles) is: $scriptDir"

    # Read package metadata from metadata.txt
    $packageMetadataFile = Join-Path $scriptDir "metadata.txt"
    if (-Not (Test-Path $packageMetadataFile)) {
        throw "FATAL: No metadata.txt found in '$scriptDir'. Aborting."
    }

    $packageMetadata = @{}
    Get-Content $packageMetadataFile | ForEach-Object {
        if ($_ -match "^\s*([^=]+)\s*=\s*(.+)$") {
            $packageMetadata[$matches[1].Trim()] = $matches[2].Trim()
        }
    }

    $newAppName    = $packageMetadata["AppName"]
    $newEntryFile  = $packageMetadata["EntryFile"]
    $newVersion    = $packageMetadata["Version"]
    $appFolderName = $packageMetadata["AppFolder"]
    $requiredPythonVersion = $packageMetadata["PythonVersion"] # Get PythonVersion from metadata

    # Validate essential metadata
    if (-not $newAppName -or -not $appFolderName -or -not $newVersion) {
        throw "FATAL: Metadata file '$packageMetadataFile' is missing required fields (AppName, AppFolder, Version)."
    }

    # Handle PythonVersion: use from metadata or default, and log
    if (-not $requiredPythonVersion -or $requiredPythonVersion -eq "") {
        $requiredPythonVersion = "3.10.0" # Default if not found or empty in metadata
        Write-Log "PythonVersion not found or empty in metadata.txt. Using default: $requiredPythonVersion" -Level WARN
    } else {
        Write-Log "Using Python version from metadata.txt: $requiredPythonVersion"
    }
    
    Write-Log "Package metadata:"
    Write-Log "  AppName: $newAppName"
    Write-Log "  AppFolder: $appFolderName"
    Write-Log "  EntryFile: $newEntryFile"
    Write-Log "  New Package Version: $newVersion"
    Write-Log "  Required Python Version (from metadata): $requiredPythonVersion"

    # Testing write permissions
    Write-Log "Testing write permissions to target directory '$targetDir'..."
    try {
        $testFilePath = Join-Path $targetDir "test_write_permissions.tmp"
        "test" | Out-File -FilePath $testFilePath -Encoding ASCII -ErrorAction Stop
        Remove-Item -Path $testFilePath -Force -ErrorAction Stop
        Write-Log "Write permissions confirmed."
    } catch {
        Write-Log "Cannot write to target directory '$targetDir'. The installation requires administrator privileges." -Level ERROR
        Write-Log "Error details: $_" -Level ERROR
        throw "Installation failed due to insufficient permissions. Ensure the installer is run as administrator."
    }

    # Skipping file copy as Inno Setup handles it
    Write-Log "Skipping file copy step as Inno Setup handles initial file placement."

    # Define path to requirements.txt (needed for pip install later)
    $appPath = Join-Path -Path $targetDir -ChildPath $appFolderName
    $reqFile = Join-Path -Path $appPath -ChildPath "requirements.txt"

    if (-Not (Test-Path $reqFile)) {
        throw "FATAL: Could not find '$appFolderName\requirements.txt' in '$targetDir'. Searched path: '$reqFile'. Aborting setup."
    }
    Write-Log "Found requirements file at: $reqFile (will be used for pip install)"

    # --- Check/Install/Update bundled Python in the Env folder ---
    # This section now uses $requiredPythonVersion which is reliably from metadata.txt
    $envDir = Join-Path $targetDir "Env"
    $pythonExe = Join-Path $envDir "python.exe"
    $needPythonUpdate = $false

    if (Test-Path $pythonExe) {
        try {
            $installedPythonVerStr = & $pythonExe -c "import platform; print(platform.python_version())"
            Write-Log "Installed bundled Python version: $installedPythonVerStr"
            if (Compare-Versions $installedPythonVerStr $requiredPythonVersion -ne 0) {
                Write-Log "Installed Python version ($installedPythonVerStr) does not match required version ($requiredPythonVersion). Updating bundled Python..."
                $needPythonUpdate = $true
            } else {
                 Write-Log "Installed Python version matches required version."
            }
        }
        catch {
            Write-Log "Error determining installed Python version. Will attempt to update bundled Python. Error: $_" -Level WARN
            $needPythonUpdate = $true
        }
    }
    else {
        Write-Log "No bundled Python found at '$pythonExe'. Need to download."
        $needPythonUpdate = $true
    }

    if ($needPythonUpdate) {
        Write-Log "Preparing to install/update Python environment in '$envDir'..."
        if (Test-Path $envDir) {
            Write-Log "Removing existing Env directory: '$envDir'"
            Remove-Item $envDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $envDir | Out-Null
        Write-Log "Downloading embeddable Python $requiredPythonVersion (amd64)..."
        $zipUrl = "https://www.python.org/ftp/python/$requiredPythonVersion/python-$requiredPythonVersion-embed-amd64.zip"
        Write-Log "Downloading from URL: $zipUrl"
        $zipFile = Join-Path $envDir "python-embed.zip"

        try {
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing
        } catch {
            throw "FATAL: Failed to download Python embeddable package from '$zipUrl'. Error: $_"
        }

        Write-Log "Extracting Python embeddable package..."
        try {
            Expand-Archive -Path $zipFile -DestinationPath $envDir -Force
        } catch {
             throw "FATAL: Failed to extract Python zip file '$zipFile'. Error: $_"
        } finally {
             if (Test-Path $zipFile) { Remove-Item $zipFile }
        }
        Write-Log "Bundled Python downloaded and extracted."

        $customPthSource = Join-Path $scriptDir "custom_pth.txt"
        if (Test-Path $customPthSource) {
            $pthFileDest = Get-ChildItem -Path $envDir -Filter "*._pth" | Select-Object -First 1
            if ($pthFileDest) {
                Write-Log "Replacing _pth file '$($pthFileDest.FullName)' with custom version from '$customPthSource'..."
                try {
                    $customContent = Get-Content $customPthSource -Raw
                    Set-Content -Path $pthFileDest.FullName -Value $customContent -Encoding ASCII -Force # Embeddable Python's pth file is often ASCII
                    Write-Log "New _pth file content:"
                    Get-Content $pthFileDest.FullName | ForEach-Object { Write-Log "  $_" }
                } catch {
                     Write-Log "Failed to replace ._pth file. Error: $_" -Level WARN
                }
            }
            else {
                Write-Log "No default ._pth file found in '$envDir' to replace." -Level WARN
            }
        } else {
             Write-Log "No custom_pth.txt found in '$scriptDir', using default Python ._pth file."
        }
    }

    # --- Ensure pip is installed in the Env ---
    Write-Log "Checking if pip is installed in '$pythonExe'..."
    $pipVersion = ""
    try {
        $pipCmdOutput = & $pythonExe -m pip --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $pipCmdOutput -match "pip") {
             $pipVersion = $pipCmdOutput.Trim()
        } else {
            Write-Log "pip check command output (ExitCode $LASTEXITCODE): $pipCmdOutput" -Level WARN
        }
    } catch {
        Write-Log "pip check failed with exception: $_" -Level WARN
    }

    if (-not $pipVersion) {
        Write-Log "pip is not installed or check failed. Attempting to install pip..."
        $getPipUrl = "https://bootstrap.pypa.io/get-pip.py"
        $getPipFile = Join-Path $envDir "get-pip.py"
        Write-Log "Downloading get-pip.py from $getPipUrl..."
        try {
            Invoke-WebRequest -Uri $getPipUrl -OutFile $getPipFile -UseBasicParsing
        } catch {
            throw "FATAL: Failed to download get-pip.py from '$getPipUrl'. Error: $_"
        }

        Write-Log "Running get-pip.py using '$pythonExe'..."
        try {
            $getPipOutput = & $pythonExe $getPipFile --no-warn-script-location 2>&1
            if ($LASTEXITCODE -ne 0) {
                 Write-Log "get-pip.py execution failed (ExitCode $LASTEXITCODE). Output:" -Level ERROR
                 $getPipOutput | ForEach-Object { Write-Log "  $_" -Level ERROR }
                 throw "get-pip.py execution failed."
            } else {
                 Write-Log "get-pip.py executed. Output:"
                 $getPipOutput | ForEach-Object { Write-Log "  $_" }
            }

            $pipVersion = (& $pythonExe -m pip --version 2>&1).Trim()
            if ($LASTEXITCODE -ne 0 -or $pipVersion -notmatch "pip") {
                throw "pip installation command finished, but verification failed. Output: $pipVersion"
            }
            Write-Log "pip installed successfully: $pipVersion"
        } catch {
            throw "FATAL: Failed to install pip using get-pip.py. Error: $_"
        } finally {
            if (Test-Path $getPipFile) { Remove-Item $getPipFile }
        }
    }
    else {
        Write-Log "pip is already installed: $pipVersion"
    }

   # --- Update Dependencies using pip ---
   Write-Log "Installing/updating dependencies from '$reqFile'..."
   $deps = Get-Content $reqFile | Where-Object {
       $_.Trim() -ne '' -and
       $_ -notmatch "^\s*#.*" -and
       $_ -notmatch "^\s*python\s*==" -and # Exclude python==
       $_ -notmatch '^\s*python\s*=\s*"' -and # Exclude python = "..."
       $_ -notmatch '^\s*python_version\s*=\s*"' # Exclude python_version = "..."
   }

   if ($deps) {
       $tempReqFile = Join-Path $targetDir "temp_requirements.txt"
       try {
           Write-Log "Dependencies being passed to pip:"
           $deps | ForEach-Object { Write-Log "  $_" }
           $deps | Out-File -Encoding UTF8 -FilePath $tempReqFile
           
           # Use an array for the command and arguments for Start-Process for better handling
           $pipArgs = @("-m", "pip", "install", "--no-cache-dir", "--no-warn-script-location", "--upgrade", "-r", """$tempReqFile""")
           Write-Log "Running: $pythonExe $($pipArgs -join ' ')"

           $process = Start-Process -FilePath $pythonExe -ArgumentList $pipArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput "$targetDir\pip_stdout.log" -RedirectStandardError "$targetDir\pip_stderr.log"
           
           $stdoutContent = Get-Content "$targetDir\pip_stdout.log" -Raw -ErrorAction SilentlyContinue
           $stderrContent = Get-Content "$targetDir\pip_stderr.log" -Raw -ErrorAction SilentlyContinue

           if ($stdoutContent) { Write-Log "pip install stdout: $stdoutContent" }

           if ($process.ExitCode -ne 0) {
                Write-Log "pip install command failed (ExitCode $($process.ExitCode))." -Level ERROR
                if ($stderrContent) { Write-Log "pip install stderr: $stderrContent" -Level ERROR }
                throw "pip install command failed."
           } else {
                Write-Log "pip install executed successfully."
                if ($stderrContent) { Write-Log "pip install stderr (might contain warnings): $stderrContent" -Level WARN } # Log stderr even on success for warnings
                Write-Log "Dependencies updated successfully."
           }
       } catch {
           Write-Log "Error during dependency installation: $($_.Exception.Message)" -Level ERROR
           throw "FATAL: Failed to install dependencies from '$tempReqFile'. Error: $_"
       } finally {
           if (Test-Path $tempReqFile) { Remove-Item $tempReqFile }
           if (Test-Path "$targetDir\pip_stdout.log") { Remove-Item "$targetDir\pip_stdout.log" }
           if (Test-Path "$targetDir\pip_stderr.log") { Remove-Item "$targetDir\pip_stderr.log" }
       }
   }
   else {
       Write-Log "No dependencies found in '$reqFile' (excluding python lines and comments)."
   }

    # --- Final Steps ---
    Write-Log "-----------------------------------------------------"
    Write-Log "Setup/Update complete for $newAppName version $newVersion."
    Write-Log "Installation location: $targetDir"
    Write-Log "-----------------------------------------------------"

} catch {
    $errorMessage = @"
-----------------------------------------------------
FATAL ERROR during installation/update:
$($_.Exception.Message)

Script Stack Trace:
$($_.ScriptStackTrace)

Failed Command:
$($_.InvocationInfo.Line)

Target Object:
$($_.TargetObject)
-----------------------------------------------------
"@
    Write-Log $errorMessage -Level FATAL
    try {
        $errorMessage | Out-File -FilePath $EarlyErrorLogPath -Append -Encoding UTF8
        Write-Host "FATAL ERROR occurred. Details logged to '$LogFilePath' (and potentially '$EarlyErrorLogPath')."
    } catch {
        Write-Host "FATAL ERROR occurred, and could not write to fallback log '$EarlyErrorLogPath'."
        Write-Host $errorMessage
    }
    exit 1
}

# Success
Write-Log "Setup script completed successfully."
exit 0