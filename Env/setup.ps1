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

        # Attempt to write to the main log file if the path is set
        if ($LogFilePath -ne $null) {
            try {
                # Use UTF8 encoding for better character support
                $logEntry | Out-File -FilePath $LogFilePath -Append -Encoding UTF8 -ErrorAction Stop
            } catch {
                # Fallback if main log fails: Write to console and temp error log
                Write-Host "LOGGING ERROR: Could not write to '$LogFilePath'. Fallback needed. Error: $_"
                $fallbackErrorLog = Join-Path $env:TEMP "app_install_fallback_error.log"
                $logEntry | Out-File -FilePath $fallbackErrorLog -Append -Encoding UTF8
            }
        } else {
            # If LogFilePath isn't set yet (very early stages), write to console
            Write-Host $logEntry
        }
    }
}

# --- Fallback Error Log Path (for very early errors) ---
$EarlyErrorLogPath = Join-Path $env:TEMP "app_install_early_error_$(Get-Date -Format 'yyyyMMddHHmmss').log"

try {
    # --- Determine target installation directory ---
    # This needs to happen early to establish the main log file path
    if ($InstallPath -eq $null -or $InstallPath -eq "" -or (-not (Test-Path $InstallPath -PathType Container))) {
        # Cannot use Write-Log yet as $targetDir is not confirmed
        $errorMsg = "FATAL: Invalid or missing installation path provided via -InstallPath parameter. Value received: '$InstallPath'"
        Write-Host $errorMsg
        $errorMsg | Out-File -FilePath $EarlyErrorLogPath -Append -Encoding UTF8
        exit 1 # Exit immediately
    } else {
        # Use the provided path, ensure it's absolute
        $targetDir = Resolve-Path -Path $InstallPath
        # --- Define the main log file path NOW ---
        $LogFilePath = Join-Path $targetDir "setup_log.txt"

        # Clear previous log file if it exists
        if (Test-Path $LogFilePath) {
            Remove-Item $LogFilePath -Force
        }
        Write-Log "Target installation directory confirmed: $targetDir"
        Write-Log "Log file initialized at: $LogFilePath"

        # Create the directory if it doesn't exist (should have been created by Inno Setup, but check anyway)
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

    # --- Helper functions (no logging needed inside definitions) ---
    function Compare-Versions($v1, $v2) {
        try {
            $ver1 = [version]$v1
            $ver2 = [version]$v2
            return $ver1.CompareTo($ver2)
        }
        catch {
            # Log comparison failures
            Write-Log "Version comparison failed: $_" -Level WARN
            return 0 # Treat as equal if comparison fails
        }
    }

    function Ask-YesNo($message) {
        # This function might not be needed if running non-interactively from installer
        try {
            $response = Read-Host "$message (Y/N)" # Keep interaction on console
            return ($response -match '^(Y|y)')
        } catch {
            Write-Log "Could not prompt user (non-interactive?). Assuming 'No'." -Level WARN
            return $false
        }
    }

    function Generate-SetupBat($targetDir) {
        $batContent = @"
@echo off
echo Re-running setup/update...
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0\SetupFiles\setup.ps1" -InstallPath "%~dp0"
pause
"@
        $batPath = Join-Path $targetDir "setup.bat"
        try {
            $batContent | Out-File -Encoding ASCII -FilePath $batPath -Force
            Write-Log "Generated setup helper batch file at '$batPath'."
        } catch {
            Write-Log "Could not generate setup.bat in '$targetDir'. Error: $_" -Level WARN
        }
    }

    # Determine the folder where this script is located (within SetupFiles).
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    Write-Log "Script directory (SetupFiles) is: $scriptDir"

    # Read package metadata from metadata.txt
    $packageMetadataFile = Join-Path $scriptDir "metadata.txt"
    if (-Not (Test-Path $packageMetadataFile)) {
        throw "FATAL: No metadata.txt found in '$scriptDir'. Aborting." # Throw will be caught and logged
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
    $appFolderName = $packageMetadata["AppFolder"] # The name of the subfolder containing the app's Python code

    if (-not $newAppName -or -not $appFolderName -or -not $newVersion) {
        throw "FATAL: Metadata file '$packageMetadataFile' is missing required fields (AppName, AppFolder, Version)."
    }

    Write-Log "Package metadata:"
    Write-Log "  AppName: $newAppName"
    Write-Log "  AppFolder: $appFolderName"
    Write-Log "  EntryFile: $newEntryFile"
    Write-Log "  New Package Version: $newVersion"

    Write-Log "Testing write permissions to target directory '$targetDir'..."
    try {
        $testFilePath = Join-Path $targetDir "test_write_permissions.tmp"
        "test" | Out-File -FilePath $testFilePath -Encoding ASCII -ErrorAction Stop
        Remove-Item -Path $testFilePath -Force -ErrorAction Stop
        Write-Log "Write permissions confirmed."
    } catch {
        # Log the error before throwing
        Write-Log "Cannot write to target directory '$targetDir'. The installation requires administrator privileges." -Level ERROR
        Write-Log "Error details: $_" -Level ERROR
        throw "Installation failed due to insufficient permissions. Ensure the installer is run as administrator."
    }

    # --- Copy Package Contents ---
    Write-Log "Skipping file copy step as Inno Setup handles initial file placement."

    # --- Generate setup.bat helper ---
    Generate-SetupBat $targetDir

    # --- Determine required Python version from the requirements.txt ---
    $appPath = Join-Path -Path $targetDir -ChildPath $appFolderName
    $reqFile = Join-Path -Path $appPath -ChildPath "requirements.txt"

    if (-Not (Test-Path $reqFile)) {
        throw "FATAL: Could not find '$appFolderName\requirements.txt' in '$targetDir'. Searched path: '$reqFile'. Aborting setup."
    }
    Write-Log "Found requirements file at: $reqFile"

    $requiredPythonVersion = "3.10.0" # Default if not specified
    try {
        foreach ($line in Get-Content $reqFile) {
            if ($line -match "^\s*python\s*==\s*([\d\.]+)") {
                $requiredPythonVersion = $matches[1]
                Write-Log "Found required Python version in requirements.txt: $requiredPythonVersion"
                break
            }
        }
    } catch {
        Write-Log "Could not read or parse requirements.txt for Python version. Using default $requiredPythonVersion. Error: $_" -Level WARN
    }
    Write-Log "Using required Python version: $requiredPythonVersion"

    # --- Check/Install/Update bundled Python in the env folder ---
    $envDir = Join-Path $targetDir "env"
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
            Write-Log "Removing existing env directory: '$envDir'"
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

        # Apply custom ._pth file if it exists in SetupFiles
        $customPthSource = Join-Path $scriptDir "custom_pth.txt"
        if (Test-Path $customPthSource) {
            $pthFileDest = Get-ChildItem -Path $envDir -Filter "*._pth" | Select-Object -First 1
            if ($pthFileDest) {
                Write-Log "Replacing _pth file '$($pthFileDest.FullName)' with custom version from '$customPthSource'..."
                try {
                    $customContent = Get-Content $customPthSource -Raw
                    Set-Content -Path $pthFileDest.FullName -Value $customContent -Encoding ASCII -Force
                    Write-Log "New _pth file content:"
                    # Log multi-line content appropriately
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

    # --- Ensure pip is installed in the env ---
    Write-Log "Checking if pip is installed in '$pythonExe'..."
    $pipVersion = ""
    try {
        $pipCmdOutput = & $pythonExe -m pip --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $pipCmdOutput -match "pip") {
             $pipVersion = $pipCmdOutput.Trim() # Trim potential whitespace
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
            # Capture output/errors from get-pip.py
            $getPipOutput = & $pythonExe $getPipFile --no-warn-script-location 2>&1
            if ($LASTEXITCODE -ne 0) {
                 Write-Log "get-pip.py execution failed (ExitCode $LASTEXITCODE). Output:" -Level ERROR
                 $getPipOutput | ForEach-Object { Write-Log "  $_" -Level ERROR }
                 throw "get-pip.py execution failed."
            } else {
                 Write-Log "get-pip.py executed. Output:"
                 $getPipOutput | ForEach-Object { Write-Log "  $_" }
            }

            # Verify installation
            $pipVersion = (& $pythonExe -m pip --version 2>&1).Trim()
            if ($LASTEXITCODE -ne 0 -or $pipVersion -notmatch "pip") {
                throw "pip installation command finished, but verification failed. Output: $pipVersion"
            }
            Write-Log "pip installed successfully: $pipVersion"
        } catch {
            # Catch block handles logging the specific error
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
    $deps = Get-Content $reqFile | Where-Object { $_.Trim() -ne '' -and $_ -notmatch "^\s*#.*" -and $_ -notmatch "^\s*python\s*==" }

    if ($deps) {
        $tempReqFile = Join-Path $targetDir "temp_requirements.txt"
        try {
            $deps | Out-File -Encoding UTF8 -FilePath $tempReqFile
            $pipCommand = "& `"$pythonExe`" -m pip install --no-cache-dir --no-warn-script-location -r `"$tempReqFile`""
            Write-Log "Running: $pipCommand"

            # Capture output/errors from pip install
            $pipInstallOutput = & $pythonExe -m pip install --no-cache-dir --no-warn-script-location -r $tempReqFile 2>&1
            if ($LASTEXITCODE -ne 0) {
                 Write-Log "pip install command failed (ExitCode $LASTEXITCODE). Output:" -Level ERROR
                 $pipInstallOutput | ForEach-Object { Write-Log "  $_" -Level ERROR }
                 throw "pip install command failed."
            } else {
                 Write-Log "pip install executed. Output:"
                 $pipInstallOutput | ForEach-Object { Write-Log "  $_" }
                 Write-Log "Dependencies updated successfully."
            }
        } catch {
            throw "FATAL: Failed to install dependencies from '$tempReqFile'. Error: $_"
        } finally {
            if (Test-Path $tempReqFile) { Remove-Item $tempReqFile }
        }
    }
    else {
        Write-Log "No dependencies found in '$reqFile' (excluding python line and comments)."
    }

    # --- Final Steps ---
    Write-Log "-----------------------------------------------------"
    Write-Log "Setup/Update complete for $newAppName version $newVersion."
    Write-Log "Installation location: $targetDir"
    Write-Log "-----------------------------------------------------"

} catch {
    # --- Log the final error ---
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
    # Attempt to write to the main log file first
    Write-Log $errorMessage -Level FATAL

    # Also write to the fallback temp error log just in case
    try {
        $errorMessage | Out-File -FilePath $EarlyErrorLogPath -Append -Encoding UTF8
        Write-Host "FATAL ERROR occurred. Details logged to '$LogFilePath' (and potentially '$EarlyErrorLogPath')."
    } catch {
        Write-Host "FATAL ERROR occurred, and could not write to fallback log '$EarlyErrorLogPath'."
        Write-Host $errorMessage
    }

    # Signal failure to Inno Setup (non-zero exit code)
    exit 1
}

# Success
Write-Log "Setup script completed successfully."
exit 0