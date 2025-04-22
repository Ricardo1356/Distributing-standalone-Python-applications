param(
    # Root installation directory provided by the installer.
    [string]$InstallPath = $null
)

# Configure PowerShell for non-interactive execution.
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop' # Exit script on terminating errors.

# --- Global Variables ---
$LogFilePath = $null # Initialized after path/parameter validation.
$CentralLogDir = $null # Central log directory path.

# --- Logging Function ---
# Writes timestamped messages to the log file.
function Write-Log {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "FATAL")]
        [string]$Level = "INFO"
    )
    process {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss" # Format for log entry content
        $logEntry = "[$timestamp] [$Level] $Message"

        if ($LogFilePath -ne $null) {
            try {
                # Ensure the directory exists before writing
                if (-not (Test-Path (Split-Path $LogFilePath -Parent))) {
                    New-Item -ItemType Directory -Path (Split-Path $LogFilePath -Parent) -Force | Out-Null
                }
                $logEntry | Out-File -FilePath $LogFilePath -Append -Encoding UTF8 -ErrorAction Stop
            } catch {
                # Fallback logging if primary log fails (e.g., permissions after setup).
                Write-Host "LOGGING ERROR: Could not write to '$LogFilePath'. Fallback needed. Error: $_"
                $fallbackErrorLog = Join-Path $env:TEMP "app_install_fallback_error.log"
                $logEntry | Out-File -FilePath $fallbackErrorLog -Append -Encoding UTF8
            }
        } else {
            # Log to console before $LogFilePath is set.
            Write-Host $logEntry
        }
    }
}


# Used for errors before the main log file is ready. Still use TEMP for absolute earliest errors.
$EarlyErrorLogPath = Join-Path $env:TEMP "app_install_early_error_$(Get-Date -Format 'yyyyMMddHHmmss').log"

try {
    # --- Validate Parameters and Initialize Logging ---
    if ($InstallPath -eq $null -or $InstallPath -eq "" -or (-not (Test-Path $InstallPath -PathType Container))) {
        $errorMsg = "FATAL: Invalid or missing -InstallPath parameter. Value: '$InstallPath'"
        Write-Host $errorMsg; $errorMsg | Out-File -FilePath $EarlyErrorLogPath -Append -Encoding UTF8; exit 1
    }

    # Define and create the central log directory under the common PythonApps folder. Requires Admin privileges.
    try {
        $commonPFPath = [Environment]::GetFolderPath('ProgramFiles') # e.g., C:\Program Files
        if (-not $commonPFPath) { throw "Could not determine Program Files path." }
        # Construct path like C:\Program Files\PythonApps\Logs
        $CentralLogDir = Join-Path $commonPFPath 'PythonApps\Logs'
        if (-not (Test-Path $CentralLogDir)) {
            New-Item -ItemType Directory -Path $CentralLogDir -Force -ErrorAction Stop | Out-Null
        }
    } catch {
        $errorMsg = "FATAL: Could not create central log directory '$CentralLogDir'. Error: $_"
        Write-Host $errorMsg; $errorMsg | Out-File -FilePath $EarlyErrorLogPath -Append -Encoding UTF8; exit 1
    }

    # Define the final log file path using a generic name and timestamp.
    $logTimestamp = Get-Date -Format 'yyyy-MM-dd_HH_mm_ss' # Use underscores instead of colons
    # Generic log file name
    $LogFilePath = Join-Path $CentralLogDir "installation_log_$logTimestamp.txt"

    # Now safe to start logging to the file.
    Write-Log "=== Starting setup/update ==="
    Write-Log "User: $env:USERNAME"
    Write-Log "InstallPath Parameter: '$InstallPath'"

    # Resolve target directory AFTER initializing logging.
    $targetDir = Resolve-Path -Path $InstallPath # Ensure absolute path.
    Write-Log "TargetDir Resolved: $targetDir"

    $internalDir = Join-Path $targetDir "_internal"
    Write-Log "InternalDir: $internalDir"
    Write-Log "CentralLogDir: $CentralLogDir"
    Write-Log "LogFile: $LogFilePath"

    # --- Helper Functions ---

    # Compares two version strings.
    function Compare-Versions($v1, $v2) {
        try {
            return ([version]$v1).CompareTo([version]$v2)
        }
        catch {
            Write-Log "Version comparison failed between '$v1' and '$v2'. Error: $_" -Level WARN
            return 0 # Treat as equal on failure.
        }
    }

    # Generates a helper batch file to re-run this script manually.
    function Generate-SetupBat($targetDir, $internalDir) {
        $batContent = '@echo off%0DPowershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0\_internal\setup.ps1" -InstallPath "%~dp0"%0DPause'
        $batPath = Join-Path $internalDir "rerun_setup.bat"
        try {
            $batContent | Out-File -Encoding ASCII -FilePath $batPath -Force
            Write-Log "Generated helper batch: '$batPath'."
        } catch {
            Write-Log "Could not generate rerun_setup.bat in '$internalDir'. Error: $_" -Level WARN
        }
    }

    # --- Load Configuration ---
    # Load configuration from metadata.txt located alongside this script.
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $packageMetadataFile = Join-Path $scriptDir "metadata.txt"
    if (-Not (Test-Path $packageMetadataFile)) { throw "FATAL: metadata.txt not found in '$scriptDir'." }

    $packageMetadata = @{}
    Get-Content $packageMetadataFile | ForEach-Object { if ($_ -match "^\s*([^=]+)\s*=\s*(.+)$") { $packageMetadata[$matches[1].Trim()] = $matches[2].Trim() } }

    $newAppName    = $packageMetadata["AppName"] # Still needed for messages, etc.
    $newEntryFile  = $packageMetadata["EntryFile"]
    $newVersion    = $packageMetadata["Version"]
    $appFolderName = $packageMetadata["AppFolder"]

    if (-not $newAppName -or -not $appFolderName -or -not $newVersion) { throw "FATAL: metadata.txt is missing required fields." }
    Write-Log "Metadata: AppName='$newAppName', AppFolder='$appFolderName', EntryFile='$newEntryFile', Version='$newVersion'"

    # --- Permissions Check ---
    # Verify write permissions in the target directory.
    Write-Log "Testing write permissions to '$targetDir'..."
    try {
        $testFilePath = Join-Path $targetDir "test_write.tmp"; "test" | Out-File -FilePath $testFilePath -Encoding ASCII -ErrorAction Stop; Remove-Item -Path $testFilePath -Force -ErrorAction Stop
        Write-Log "Write permissions confirmed."
    } catch {
        Write-Log "Write permission test failed in '$targetDir'. Requires admin privileges? Error: $_" -Level ERROR
        throw "Installation failed due to insufficient permissions."
    }

    # --- Generate Helper Script ---
    Generate-SetupBat $targetDir $internalDir

    # --- Python Version Check ---
    # Determine required Python version from requirements.txt.
    $appPath = Join-Path -Path $targetDir -ChildPath $appFolderName
    $reqFile = Join-Path -Path $appPath -ChildPath "requirements.txt"
    if (-Not (Test-Path $reqFile)) { throw "FATAL: requirements.txt not found at '$reqFile'." }
    Write-Log "Found requirements file: $reqFile"

    $requiredPythonVersion = "3.10.0" # Default Python version if not specified in requirements.
    try {
        foreach ($line in Get-Content $reqFile) { if ($line -match "^\s*python\s*==\s*([\d\.]+)") { $requiredPythonVersion = $matches[1]; Write-Log "Required Python version from requirements.txt: $requiredPythonVersion"; break } }
    } catch {
        Write-Log "Could not parse requirements.txt for Python version. Using default $requiredPythonVersion. Error: $_" -Level WARN
    }
    Write-Log "Using required Python version: $requiredPythonVersion"

    # --- Python Environment Setup ---
    # Check/Install/Update bundled Python environment.
    $envDir = Join-Path $targetDir "env"
    $pythonExe = Join-Path $envDir "python.exe"
    $needPythonUpdate = $false

    if (Test-Path $pythonExe) {
        try {
            $installedPythonVerStr = (& $pythonExe -c "import platform; print(platform.python_version())").Trim()
            Write-Log "Installed Python version: $installedPythonVerStr"
            if (Compare-Versions $installedPythonVerStr $requiredPythonVersion -ne 0) { Write-Log "Python version mismatch. Update needed."; $needPythonUpdate = $true }
            else { Write-Log "Python version matches." }
        } catch { Write-Log "Error checking Python version. Assuming update needed. Error: $_" -Level WARN; $needPythonUpdate = $true }
    } else { Write-Log "Bundled Python not found. Installation needed."; $needPythonUpdate = $true }

    if ($needPythonUpdate) {
        Write-Log "Updating Python environment in '$envDir'..."
        if (Test-Path $envDir) { Write-Log "Removing existing env: '$envDir'"; Remove-Item $envDir -Recurse -Force }
        New-Item -ItemType Directory -Path $envDir | Out-Null
        Write-Log "Downloading Python $requiredPythonVersion (amd64)..."
        $zipUrl = "https://www.python.org/ftp/python/$requiredPythonVersion/python-$requiredPythonVersion-embed-amd64.zip"
        $zipFile = Join-Path $envDir "python-embed.zip"
        try { Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing } catch { throw "FATAL: Failed to download Python from '$zipUrl'. Error: $_" }
        Write-Log "Extracting Python to '$envDir'..."
        try { Expand-Archive -Path $zipFile -DestinationPath $envDir -Force } catch { throw "FATAL: Failed to extract '$zipFile'. Error: $_" } finally { if (Test-Path $zipFile) { Remove-Item $zipFile } }
        Write-Log "Python extracted."

        # Apply custom ._pth file to include site-packages.
        $customPthSource = Join-Path $scriptDir "custom_pth.txt"
        if (Test-Path $customPthSource) {
            $pthFileDest = Get-ChildItem -Path $envDir -Filter "*._pth" | Select-Object -First 1
            if ($pthFileDest) {
                Write-Log "Applying custom ._pth file to '$($pthFileDest.FullName)'..."
                try { $customContent = Get-Content $customPthSource -Raw; Set-Content -Path $pthFileDest.FullName -Value $customContent -Encoding ASCII -Force; Write-Log "Custom ._pth applied." }
                catch { Write-Log "Failed to apply custom ._pth file. Error: $_" -Level WARN }
            } else { Write-Log "No default ._pth file found in '$envDir' to replace." -Level WARN }
        } else { Write-Log "No custom_pth.txt found in '$scriptDir'." }
    }

    # --- Pip Installation ---
    # Ensure pip is installed.
    Write-Log "Checking pip installation..."
    $pipVersion = ""
    try {
        $pipCmdOutput = & $pythonExe -m pip --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $pipCmdOutput -match "pip") { $pipVersion = $pipCmdOutput.Trim(); Write-Log "pip found: $pipVersion" }
        else { Write-Log "pip check failed or pip not found (ExitCode $LASTEXITCODE). Output: $pipCmdOutput" -Level WARN }
    } catch { Write-Log "pip check failed with exception: $_" -Level WARN }

    if (-not $pipVersion) {
        Write-Log "Attempting to install pip..."
        $getPipUrl = "https://bootstrap.pypa.io/get-pip.py"
        $getPipFile = Join-Path $envDir "get-pip.py"
        try { Invoke-WebRequest -Uri $getPipUrl -OutFile $getPipFile -UseBasicParsing } catch { throw "FATAL: Failed to download get-pip.py. Error: $_" }
        Write-Log "Running get-pip.py..."
        try {
            $getPipOutput = & $pythonExe $getPipFile --no-warn-script-location 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Log "get-pip.py failed (ExitCode $LASTEXITCODE). Output:" -Level ERROR; $getPipOutput | ForEach-Object { Write-Log "  $_" -Level ERROR }; throw "get-pip.py failed." }
            else { Write-Log "get-pip.py executed successfully." }
            $pipVersionCheck = (& $pythonExe -m pip --version 2>&1).Trim() # Verify
            if ($LASTEXITCODE -ne 0 -or $pipVersionCheck -notmatch "pip") { throw "pip verification failed after get-pip.py. Output: $pipVersionCheck" }
            $pipVersion = $pipVersionCheck
            Write-Log "pip installed: $pipVersion"
        } catch { throw "FATAL: Failed to install pip. Error: $_" } finally { if (Test-Path $getPipFile) { Remove-Item $getPipFile } }
    }

    # --- Dependency Installation ---
    # Install/update dependencies using pip.
    Write-Log "Checking dependencies in '$reqFile'..."
    $deps = Get-Content $reqFile | Where-Object { $_.Trim() -ne '' -and $_ -notmatch "^\s*#.*" -and $_ -notmatch "^\s*python\s*==" }
    if ($deps) {
        Write-Log "Installing/updating dependencies..."
        $tempReqFile = Join-Path $targetDir "temp_requirements.txt"
        try {
            $deps | Out-File -Encoding UTF8 -FilePath $tempReqFile
            $pipCommand = "& `"$pythonExe`" -m pip install --no-cache-dir --no-warn-script-location -r `"$tempReqFile`""
            Write-Log "Running: $pipCommand"
            $pipInstallOutput = & $pythonExe -m pip install --no-cache-dir --no-warn-script-location -r $tempReqFile 2>&1
            if ($LASTEXITCODE -ne 0) { Write-Log "pip install failed (ExitCode $LASTEXITCODE). Output:" -Level ERROR; $pipInstallOutput | ForEach-Object { Write-Log "  $_" -Level ERROR }; throw "pip install failed." }
            else { Write-Log "pip install executed successfully." }
        } catch { throw "FATAL: Failed to install dependencies. Error: $_" } finally { if (Test-Path $tempReqFile) { Remove-Item $tempReqFile } }
    } else { Write-Log "No dependencies found in '$reqFile'." }

    # --- Completion ---
    Write-Log "-----------------------------------------------------"
    # Use $newAppName read from metadata for the completion message
    Write-Log "Setup/Update complete for $newAppName version $newVersion."
    Write-Log "Installation location: $targetDir"
    Write-Log "-----------------------------------------------------"

} catch {
    # --- Log fatal errors ---
    $errorMessage = @"
-----------------------------------------------------
FATAL ERROR during installation/update:
$($_.Exception.Message)
Script Stack Trace: $($_.ScriptStackTrace)
Failed Command: $($_.InvocationInfo.Line)
Target Object: $($_.TargetObject)
-----------------------------------------------------
"@
    Write-Log $errorMessage -Level FATAL # Log to central file if possible
    try { $errorMessage | Out-File -FilePath $EarlyErrorLogPath -Append -Encoding UTF8; Write-Host "FATAL ERROR occurred. Details logged to '$LogFilePath' (and potentially '$EarlyErrorLogPath')." }
    catch { Write-Host "FATAL ERROR occurred, and could not write to fallback log '$EarlyErrorLogPath'."; Write-Host $errorMessage }

    # --- Rollback Removed ---
    # Running the uninstaller here seems to interfere with Inno Setup correctly detecting the script's failure exit code.
    # By removing it, Inno Setup should correctly report the failure, but the user will need to manually uninstall the partial installation.
    Write-Log "Setup script failed. Manual uninstallation via Add/Remove Programs might be required." -Level WARN

    # --- Exit with Failure Code ---
    exit 1 # Always signal the original failure to Inno Setup.
}

# Success
Write-Log "Setup script completed successfully."
exit 0