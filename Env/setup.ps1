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
            # This case should ideally not happen after LogFilePath is initialized
            Write-Host $logEntry
        }
    }
}

# --- Fallback Error Log Path (for very early errors) ---
$EarlyErrorLogPath = Join-Path $env:TEMP "app_install_early_error_$(Get-Date -Format 'yyyyMMddHHmmss').log"

try {
    # --- Determine target installation directory & Initialize LogFilePath ---
    if ($InstallPath -eq $null -or $InstallPath -eq "" -or (-not (Test-Path $InstallPath -PathType Container))) {
        $errorMsg = "FATAL: Invalid or missing installation path provided via -InstallPath parameter. Value received: '$InstallPath'"
        Write-Host $errorMsg
        $errorMsg | Out-File -FilePath $EarlyErrorLogPath -Append -Encoding UTF8 # Log to early error log
        exit 1
    } else {
        $targetDir = Resolve-Path -Path $InstallPath
        $timestampForLog = Get-Date -Format "yyyyMMdd-HHmmss"
        $LogFilePath = Join-Path $targetDir "Installation_Log_$timestampForLog.txt"
        if (Test-Path $LogFilePath) {
            Remove-Item $LogFilePath -Force # Start with a fresh log for this run
        }
        Write-Log "Target installation directory confirmed: $targetDir"
        Write-Log "Log file initialized at: $LogFilePath"
        if (-Not (Test-Path $targetDir)) {
            Write-Log "Creating installation directory: $targetDir"
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
    }

    # --- Start Logging ---
    Write-Log "=== Starting setup/update process ==="
    Write-Log "Timestamp: $(Get-Date)"
    Write-Log "Running with user: $env:USERNAME"
    Write-Log "Current directory: $(Get-Location)"
    Write-Log "InstallPath parameter received: '$InstallPath'"

    # --- Helper functions ---
    function Compare-Versions($v1, $v2) {
        try {
            $ver1 = [version]$v1
            $ver2 = [version]$v2
            return $ver1.CompareTo($ver2) # 0 if equal, -1 if v1 < v2, 1 if v1 > v2
        }
        catch {
            Write-Log "Version comparison failed for '$v1' and '$v2': $_" -Level WARN
            return -2 # Indicate an error in comparison, ensuring it's not treated as equal
        }
    }

    # --- Script & Metadata Reading (from the NEW version's _internal folder) ---
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    Write-Log "Script directory (_internal, containing new version's setup files) is: $scriptDir"

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
    $newAppName            = $packageMetadata["AppName"]
    $newEntryFile          = $packageMetadata["EntryFile"] # Not used in this script but good to parse
    $newVersion            = $packageMetadata["Version"]
    $appFolderName         = $packageMetadata["AppFolder"] # Folder name for the app's code
    $requiredPythonVersion = $packageMetadata["PythonVersion"]

    if (-not $newAppName -or -not $appFolderName -or -not $newVersion -or -not $requiredPythonVersion) {
        throw "FATAL: Metadata file '$packageMetadataFile' is missing required fields (AppName, AppFolder, Version, PythonVersion)."
    }
    Write-Log "Processing new application version based on metadata:"
    Write-Log "  New AppName: $newAppName"
    Write-Log "  New AppFolder: $appFolderName"
    Write-Log "  New Package Version: $newVersion"
    Write-Log "  Required Python Version for new package: $requiredPythonVersion"

    # --- Define core paths ---
    $envDir = Join-Path $targetDir "Env" # Standard Python environment subfolder
    $pythonExe = Join-Path $envDir "python.exe"
    # Path to the application code folder (e.g., <targetDir>/<AppNameFromMetadata>)
    $appCodePath = Join-Path -Path $targetDir -ChildPath $appFolderName
    # Path to the requirements.txt of the NEW application version (already copied by Inno Setup)
    $reqFile = Join-Path -Path $appCodePath -ChildPath "requirements.txt"

    if (-Not (Test-Path $reqFile)) {
        throw "FATAL: Could not find new '$appFolderName\requirements.txt' in '$targetDir'. Expected at: '$reqFile'. Aborting setup."
    }
    Write-Log "Found new requirements file at: $reqFile (will be used for pip install)"
    
    # --- Test write permissions (early check) ---
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

    # --- Check for existing installation and determine if Python environment needs full setup/refresh ---
    $performFullPythonSetup = $false
    $isUpdateScenario = $false

    if (Test-Path $envDir) { # Check if Env directory exists
        $isUpdateScenario = $true
        Write-Log "Existing 'Env' directory found at '$envDir'. Treating as an update or re-setup."
        if (Test-Path $pythonExe) {
            Write-Log "Existing Python executable found at '$pythonExe'."
            try {
                $installedPythonVerStr = (& $pythonExe -c "import platform; print(platform.python_version())").Trim()
                Write-Log "Currently installed bundled Python version: $installedPythonVerStr"
                if ((Compare-Versions $installedPythonVerStr $requiredPythonVersion) -ne 0) {
                    Write-Log "Installed Python version ($installedPythonVerStr) differs from new required version ($requiredPythonVersion). Full Python environment refresh needed." -Level WARN
                    $performFullPythonSetup = $true
                } else {
                    Write-Log "Installed Python version matches new required version. Python executable itself is OK."
                }
            } catch {
                Write-Log "Could not determine version of existing Python at '$pythonExe'. Assuming full Python setup is needed. Error: $_" -Level WARN
                $performFullPythonSetup = $true
            }
        } else {
            Write-Log "'Env' directory exists, but no Python executable found at '$pythonExe'. Full Python setup needed."
            $performFullPythonSetup = $true
        }
    } else {
        Write-Log "No existing 'Env' directory found. This is a fresh installation. Full Python setup needed."
        $performFullPythonSetup = $true
    }

    if ($performFullPythonSetup) {
        Write-Log "Performing full Python environment setup in '$envDir' for version $requiredPythonVersion..."
        if (Test-Path $envDir) {
            Write-Log "Removing existing Env directory: '$envDir' to ensure clean setup."
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
        Write-Log "Bundled Python $requiredPythonVersion downloaded and extracted."

        $customPthSource = Join-Path $scriptDir "custom_pth.txt" # From new _internal
        if (Test-Path $customPthSource) {
            $pthFileDest = Get-ChildItem -Path $envDir -Filter "*._pth" | Select-Object -First 1
            if ($pthFileDest) {
                Write-Log "Replacing _pth file '$($pthFileDest.FullName)' with custom version from '$customPthSource'..."
                try {
                    $customContent = Get-Content $customPthSource -Raw
                    Set-Content -Path $pthFileDest.FullName -Value $customContent -Encoding ASCII -Force
                    Write-Log "New _pth file content:"
                    Get-Content $pthFileDest.FullName | ForEach-Object { Write-Log "  $_" }
                } catch {
                     Write-Log "Failed to replace ._pth file. Error: $_" -Level WARN
                }
            } else { Write-Log "No default ._pth file found in '$envDir' to replace." -Level WARN }
        } else { Write-Log "No custom_pth.txt found in '$scriptDir', using default Python ._pth file." }
    } elseif ($isUpdateScenario) {
        Write-Log "Python environment at '$envDir' does not require a version update. Proceeding to check pip and dependencies."
    }

    # --- Ensure pip is installed in the Env ---
    # This runs if Python was just set up, or if it pre-existed and Python version matched.
    Write-Log "Ensuring pip is available in '$pythonExe'..."
    $pipVersion = ""
    if (-not (Test-Path $pythonExe)) {
         throw "FATAL: Python executable '$pythonExe' not found. Cannot proceed to pip installation."
    }
    try {
        $pipCmdOutput = & $pythonExe -m pip --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $pipCmdOutput -match "pip") {
             $pipVersion = $pipCmdOutput.Trim()
        } else { Write-Log "pip check command output (ExitCode $LASTEXITCODE): $pipCmdOutput" -Level WARN }
    } catch { Write-Log "pip check failed with exception: $_" -Level WARN }

    if (-not $pipVersion) {
        Write-Log "pip is not installed or check failed. Attempting to install pip..."
        $getPipUrl = "https://bootstrap.pypa.io/get-pip.py"
        $getPipFile = Join-Path $envDir "get-pip.py"
        Write-Log "Downloading get-pip.py from $getPipUrl..."
        try { Invoke-WebRequest -Uri $getPipUrl -OutFile $getPipFile -UseBasicParsing } 
        catch { throw "FATAL: Failed to download get-pip.py from '$getPipUrl'. Error: $_" }

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
            if ($LASTEXITCODE -ne 0 -or $pipVersion -notmatch "pip") { throw "pip installation command finished, but verification failed. Output: $pipVersion" }
            Write-Log "pip installed successfully: $pipVersion"
        } 
        catch { throw "FATAL: Failed to install pip using get-pip.py. Error: $_" } 
        finally { if (Test-Path $getPipFile) { Remove-Item $getPipFile } }
    } else { Write-Log "pip is already installed: $pipVersion" }

   # --- Install/Update Dependencies using pip ---
   # This section always runs to synchronize with the new requirements.txt
   if ($isUpdateScenario) {
       Write-Log "Updating dependencies for the new version from '$reqFile'..."
   } else {
       Write-Log "Installing dependencies for fresh installation from '$reqFile'..."
   }
   $deps = Get-Content $reqFile | Where-Object {
       $_.Trim() -ne '' -and
       $_ -notmatch "^\s*#.*" -and
       $_ -notmatch "^\s*python\s*==" -and 
       $_ -notmatch '^\s*python\s*=\s*"' -and 
       $_ -notmatch '^\s*python_version\s*=\s*"'
   }
   if ($deps) {
       $tempReqFile = Join-Path $targetDir "temp_requirements.txt"
       try {
           Write-Log "Dependencies being passed to pip:"
           $deps | ForEach-Object { Write-Log "  $_" }
           $deps | Out-File -Encoding UTF8 -FilePath $tempReqFile
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
                if ($stderrContent) { Write-Log "pip install stderr (might contain warnings): $stderrContent" -Level WARN }
                Write-Log "Dependencies updated successfully."
           }
       } 
       catch { Write-Log "Error during dependency installation: $($_.Exception.Message)" -Level ERROR; throw "FATAL: Failed to install dependencies. Error: $_" } 
       finally {
           if (Test-Path $tempReqFile) { Remove-Item $tempReqFile }
           if (Test-Path "$targetDir\pip_stdout.log") { Remove-Item "$targetDir\pip_stdout.log" }
           if (Test-Path "$targetDir\pip_stderr.log") { Remove-Item "$targetDir\pip_stderr.log" }
       }
   } else { Write-Log "No dependencies found in '$reqFile' (excluding python lines and comments) to install/update." }

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