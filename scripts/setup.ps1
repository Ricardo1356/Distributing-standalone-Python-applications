param(
    [string]$InstallPath = $null,
    [string]$CurrentInstalledVersion = $null,
    [string]$NewAppVersion = $null,         # Added: Version of the app being installed
    [string]$AppIdForRegistry = $null      # Added: AppId string for registry key
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
            Write-Host $logEntry # For very early messages before LogFilePath is set
            $earlyLog = Join-Path $env:TEMP "app_install_very_early_uninitialized.log"
            $logEntry | Out-File -FilePath $earlyLog -Append -Encoding UTF8
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
        $errorMsg | Out-File -FilePath $EarlyErrorLogPath -Append -Encoding UTF8
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
    Write-Log "=== Starting setup/update process (Simplified - No User Prompts) ==="
    Write-Log "Timestamp: $(Get-Date)"
    Write-Log "Running with user: $env:USERNAME"
    Write-Log "Current directory: $(Get-Location)"
    Write-Log "InstallPath parameter received: '$InstallPath'"
    Write-Log "CurrentInstalledVersion parameter received: '$CurrentInstalledVersion'"

    # --- Helper functions ---
    function Compare-Versions($v1, $v2) {
        try {
            $ver1 = [version]$v1
            $ver2 = [version]$v2
            return $ver1.CompareTo($ver2) # 0 if equal, -1 if v1 < v2, 1 if v1 > v2
        }
        catch {
            Write-Log "Version comparison failed for '$v1' and '$v2': $_" -Level WARN
            return -2 # Indicate an error in comparison
        }
    }

    # --- Script & Metadata Reading (from the NEW version's _internal folder) ---
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition # This will be {app}\_internal
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
    $newEntryFile          = $packageMetadata["EntryFile"]
    $newVersion            = $packageMetadata["Version"]
    $appFolderName         = $packageMetadata["AppFolder"]
    $requiredPythonVersion = $packageMetadata["PythonVersion"]

    if (-not $newAppName -or -not $appFolderName -or -not $newVersion -or -not $requiredPythonVersion) {
        throw "FATAL: Metadata file '$packageMetadataFile' is missing required fields (AppName, AppFolder, Version, PythonVersion)."
    }
    Write-Log "Processing new application version based on metadata:"
    Write-Log "  New AppName: $newAppName"
    Write-Log "  New AppFolder: $appFolderName"
    Write-Log "  New Package Version: $newVersion"
    Write-Log "  Required Python Version for new package: $requiredPythonVersion"

    # --- VERSION CHECK AND AUTOMATIC ACTION LOGIC ---
    $performCleanInstallWipe = $false # Flag to indicate a full directory wipe is needed

    Write-Log "Starting version check. CurrentInstalledVersion: '$CurrentInstalledVersion', NewVersion from metadata: '$newVersion'"

    if (-not [string]::IsNullOrEmpty($CurrentInstalledVersion)) {
        Write-Log "Comparing new installer version ($newVersion) with current installed version ($CurrentInstalledVersion)."
        $versionComparisonResult = Compare-Versions $newVersion $CurrentInstalledVersion
        Write-Log "Version comparison result: $versionComparisonResult (-1 means new<current, 0 means new=current, 1 means new>current, -2 means error)"

        if ($versionComparisonResult -eq 1) { # New version is GREATER than current (Update)
            Write-Log "Installer version ($newVersion) is newer than installed version ($CurrentInstalledVersion). This is an update. Proceeding." -Level INFO
        } elseif ($versionComparisonResult -eq 0 -or $versionComparisonResult -eq -1) { # New version is SAME or OLDER (Downgrade/Reinstall)
            Write-Log "Installer version ($newVersion) is the same as or older than the installed version ($CurrentInstalledVersion). Performing automatic clean install wipe." -Level WARN
            $performCleanInstallWipe = $true # This flag will trigger directory cleaning
        } else { # Error in version comparison (-2)
             Write-Log "Could not reliably compare versions ($newVersion vs $CurrentInstalledVersion due to format issues). Proceeding cautiously as if it's a standard update/install (no wipe)." -Level WARN
        }
    } else {
        Write-Log "No CurrentInstalledVersion provided. Assuming fresh install. Proceeding."
        # $performCleanInstallWipe remains false, as it's a fresh install into potentially an empty or new directory.
        # The Python setup logic will handle creating/cleaning the Env dir.
    }

    # --- CONDITIONAL DIRECTORY WIPE for Clean Install Scenario ---
    if ($performCleanInstallWipe) {
        Write-Log "Performing clean install wipe due to version logic." -Level WARN
        Write-Log "Target directory for wipe: $targetDir. Script directory (to exclude): $scriptDir"
        $internalFolderName = Split-Path -Leaf $scriptDir # Should be "_internal"
        if (-not [string]::IsNullOrEmpty($internalFolderName)) {
            Write-Log "Attempting to remove all items in '$targetDir' EXCEPT '$internalFolderName'..."
            Get-ChildItem -Path $targetDir -Exclude $internalFolderName -Force | ForEach-Object {
                Write-Log "Removing: $($_.FullName)"
                try {
                    Remove-Item -Recurse -Force $_.FullName -ErrorAction Stop
                    Write-Log "Successfully removed: $($_.FullName)"
                } catch {
                    Write-Log "Error removing '$($_.FullName)': $($_.Exception.Message)" -Level ERROR
                }
            }
            Write-Log "Target directory cleaned (excluding '$internalFolderName')."
        } else {
            Write-Log "Could not determine _internal folder name from '$scriptDir'. Skipping directory wipe for safety." -Level ERROR
        }
    }

    # --- Define core paths ---
    $envDir = Join-Path $targetDir "Env"
    $pythonExe = Join-Path $envDir "python.exe"
    $appCodePath = Join-Path -Path $targetDir -ChildPath $appFolderName
    $reqFile = Join-Path -Path $appCodePath -ChildPath "requirements.txt" 

    if (-Not (Test-Path $reqFile)) {
        Write-Log "FATAL: Could not find new '$appFolderName\requirements.txt' in '$targetDir'. Expected at: '$reqFile'." -Level FATAL
        throw "FATAL: Could not find new '$appFolderName\requirements.txt'. Aborting setup."
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
        Write-Log "Cannot write to target directory '$targetDir'. Please check permissions." -Level ERROR
        Write-Log "Error details: $_" -Level ERROR
        throw "Installation failed due to insufficient permissions. You may need to choose a writable folder."
    }

    # --- Check for existing installation and determine if Python environment needs full setup/refresh ---
    $performFullPythonSetup = $false
    $isUpdateScenarioLogging = $false # For logging context only

    if ($performCleanInstallWipe) {
        Write-Log "Clean install wipe was performed. Forcing full Python setup."
        $performFullPythonSetup = $true
    } elseif (Test-Path $envDir) {
        $isUpdateScenarioLogging = $true 
        Write-Log "Existing 'Env' directory found at '$envDir'. Checking Python version."
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
        Write-Log "No existing 'Env' directory found (or it was removed by clean wipe). This requires a full Python setup."
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

        $customPthSource = Join-Path $scriptDir "custom_pth.txt"
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
    } elseif ($isUpdateScenarioLogging) { # Only true if Env existed, no wipe, and Python version matched
        Write-Log "Python environment at '$envDir' does not require a version update. Proceeding to check pip and dependencies."
    }

    # --- Ensure pip is installed in the Env ---
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
        $envVariablesToClear = @("PYTHONPATH", "PYTHONHOME") 
        $originalEnvValues = @{}
        try {
            foreach ($varName in $envVariablesToClear) {
                $originalEnvValues[$varName] = Get-Content "env:$varName" -ErrorAction SilentlyContinue
                if ($null -ne $originalEnvValues[$varName]) { Remove-Item "env:$varName" -ErrorAction SilentlyContinue }
            }

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
            if ($LASTEXITCODE -ne 0 -or -not ($pipVersion -match "pip")) { throw "pip installation command finished, but verification failed. Output: $pipVersion" }
            Write-Log "pip installed successfully: $pipVersion"
        } 
        catch { throw "FATAL: Failed to install pip using get-pip.py. Error: $_" } 
        finally { 
            if (Test-Path $getPipFile) { Remove-Item $getPipFile } 
            foreach ($varName in $envVariablesToClear) { 
                if ($originalEnvValues.ContainsKey($varName) -and $null -ne $originalEnvValues[$varName]) {
                    Set-Content "env:$varName" -Value $originalEnvValues[$varName]
                } else { 
                    Remove-Item "env:$varName" -ErrorAction SilentlyContinue
                }
            }
        }
    } else { Write-Log "pip is already installed: $pipVersion" }

    # --- Upgrade pip, wheel, and setuptools ---
    Write-Log "Upgrading pip, wheel, setuptools, and pep517..."
    try {
        & $pythonExe -m pip install --upgrade pip wheel setuptools pep517
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to upgrade pip/wheel/setuptools/pep517."
        }
        Write-Log "Base build tools upgraded successfully."
    } catch {
        Write-Log "Error upgrading base build tools: $($_.Exception.Message)" -Level ERROR
        throw "FATAL: Could not upgrade base build tools. Error: $_"
    }
    
    # Python 3.12+ setuptools<60 logic
    $pyVerMajor = 0
    $pyVerMinor = 0
    try {
        $versionParts = $requiredPythonVersion.Split('.')
        $pyVerMajor = [int]$versionParts[0]
        $pyVerMinor = [int]$versionParts[1]
    } catch {
        Write-Log "Could not parse requiredPythonVersion '$requiredPythonVersion' for major/minor parts. Skipping Python 3.12+ setuptools check." -Level WARN
    }

    if (($pyVerMajor -eq 3 -and $pyVerMinor -ge 12) -or $pyVerMajor -gt 3) {
        Write-Log "Python $requiredPythonVersion detected (matches 3.12+ pattern). Ensuring setuptools<60 for distutils compatibility."
        try {
            & $pythonExe -m pip install --upgrade "setuptools<60"
            if ($LASTEXITCODE -ne 0) {
                Write-Log "Failed to install/upgrade setuptools<60 for Python 3.12+." -Level WARN
            } else {
                $currentSetuptoolsVer = (& $pythonExe -m pip show setuptools |
                    Select-String -Pattern "Version:" |
                    ForEach-Object { $_.ToString().Split(':')[1].Trim() })
                Write-Log "Setuptools version after check/update for 3.12+ compatibility: '$currentSetuptoolsVer'."
            }
        } catch {
            Write-Log "Error during setuptools<60 installation for Python 3.12+: $($_.Exception.Message)" -Level WARN
        }
    }

   # --- Install/Update Dependencies using pip ---
   if ($isUpdateScenarioLogging -and -not $performFullPythonSetup) { 
       Write-Log "Updating dependencies for the existing environment from '$reqFile'..."
   } else { 
       Write-Log "Installing dependencies into the Python environment from '$reqFile'..."
   }
   $deps = Get-Content $reqFile | Where-Object {
       $_.Trim() -ne '' -and
       $_ -notmatch "^\s*#.*" -and
       $_ -notmatch "^\s*python\s*==" -and 
       $_ -notmatch '^\s*python\s*=\s*"' -and 
       $_ -notmatch '^\s*python_version\s*=\s*"'
   }
   if ($deps) {
       $tempReqFile = Join-Path $env:TEMP "temp_req_$(Get-Random).txt" 
       $pipLogDir = Join-Path $targetDir "logs" 
       if (-not (Test-Path $pipLogDir)) { New-Item -ItemType Directory -Path $pipLogDir -Force | Out-Null }
       $pipStdoutLog = Join-Path $pipLogDir "pip_install_stdout.log"
       $pipStderrLog = Join-Path $pipLogDir "pip_install_stderr.log"
       try {
           Write-Log "Dependencies being passed to pip (from temp file $tempReqFile):"
           $deps | ForEach-Object { Write-Log "  $_" }
           $deps | Out-File -Encoding UTF8 -FilePath $tempReqFile
           
           $pipArgs = @("-m", "pip", "install", "--no-cache-dir", "--no-warn-script-location", "--upgrade", "-r", """$tempReqFile""")
           Write-Log "Running: $pythonExe $($pipArgs -join ' ')"
           
           $processInfo = New-Object System.Diagnostics.ProcessStartInfo
           $processInfo.FileName = $pythonExe
           $processInfo.Arguments = ($pipArgs -join ' ')
           $processInfo.RedirectStandardOutput = $true
           $processInfo.RedirectStandardError = $true
           $processInfo.UseShellExecute = $false
           $processInfo.CreateNoWindow = $true
           
           $process = New-Object System.Diagnostics.Process
           $process.StartInfo = $processInfo
           $process.Start() | Out-Null
           
           $stdoutContent = $process.StandardOutput.ReadToEnd()
           $stderrContent = $process.StandardError.ReadToEnd()
           $process.WaitForExit()

           Set-Content -Path $pipStdoutLog -Value $stdoutContent -Encoding UTF8
           Set-Content -Path $pipStderrLog -Value $stderrContent -Encoding UTF8
           
           if ($stdoutContent) { Write-Log "pip install stdout --- START ---"; $stdoutContent.Split("`n") | ForEach-Object { Write-Log "  $_" }; Write-Log "pip install stdout --- END ---" }

           if ($process.ExitCode -ne 0) {
                Write-Log "pip install command failed (ExitCode $($process.ExitCode))." -Level ERROR
                if ($stderrContent) { Write-Log "pip install stderr --- START ---"; $stderrContent.Split("`n") | ForEach-Object { Write-Log "  $_" -Level ERROR}; Write-Log "pip install stderr --- END ---" }
                throw "pip install command failed. Check logs in '$pipLogDir'."
           } else {
                Write-Log "pip install executed successfully."
                if ($stderrContent) { Write-Log "pip install stderr (might contain warnings) --- START ---"; $stderrContent.Split("`n") | ForEach-Object { Write-Log "  $_" -Level WARN}; Write-Log "pip install stderr --- END ---" }
                Write-Log "Dependencies processed successfully."
           }
       } 
       catch { Write-Log "Error during dependency installation: $($_.Exception.Message)" -Level ERROR; throw "FATAL: Failed to install dependencies. Error: $_" } 
       finally {
           if (Test-Path $tempReqFile) { Remove-Item $tempReqFile -ErrorAction SilentlyContinue }
           Write-Log "Cleaning up pip log files: $pipStdoutLog, $pipStderrLog"
           if (Test-Path $pipStdoutLog) { Remove-Item $pipStdoutLog -ErrorAction SilentlyContinue }
           if (Test-Path $pipStderrLog) { Remove-Item $pipStderrLog -ErrorAction SilentlyContinue }
           if ((Test-Path $pipLogDir) -and ((Get-ChildItem -Path $pipLogDir -Force | Measure-Object).Count -eq 0)) { 
                Write-Log "Removing empty pip log directory: $pipLogDir"
                Remove-Item $pipLogDir -Force -ErrorAction SilentlyContinue
           }
       }
   } else { Write-Log "No dependencies found in '$reqFile' (excluding python lines and comments) to install/update." }

    # --- Final Steps ---
    Write-Log "-----------------------------------------------------"

    # --- Update Registry with DisplayVersion ---
    if ($NewAppVersion -and $AppIdForRegistry) {
        Write-Log "Attempting to update DisplayVersion in registry for AppId '$AppIdForRegistry' to version '$NewAppVersion'."
        try {
            $uninstallKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($AppIdForRegistry)_is1"
            # Ensure the key exists, otherwise RegWriteStringValue might not work as expected by Inno Setup's functions
            if (-not (Test-Path $uninstallKeyPath)) {
                Write-Log "Registry key '$uninstallKeyPath' does not exist. Creating it."
                New-Item -Path $uninstallKeyPath -Force | Out-Null
            }
            Set-ItemProperty -Path $uninstallKeyPath -Name "DisplayVersion" -Value $NewAppVersion -Force
            Write-Log "Successfully updated DisplayVersion to '$NewAppVersion' in registry path '$uninstallKeyPath'."
        } catch {
            Write-Log "ERROR: Failed to update DisplayVersion in registry. Error: $($_.Exception.Message)" -Level ERROR
            # Do not throw here, as the main installation was successful. This is a secondary step.
        }
    } else {
        Write-Log "Skipping DisplayVersion registry update because NewAppVersion or AppIdForRegistry was not provided." -Level WARN
    }

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

Failed Command (if available):
$($_.InvocationInfo.Line)

Target Object (if available):
$($_.TargetObject)
-----------------------------------------------------
"@
    Write-Log $errorMessage -Level FATAL
    if ($null -eq $EarlyErrorLogPath) { 
        $EarlyErrorLogPath = Join-Path $env:TEMP "app_install_very_early_fallback_$(Get-Date -Format 'yyyyMMddHHmmss').log"
    }
    try {
        $errorMessage | Out-File -FilePath $EarlyErrorLogPath -Append -Encoding UTF8
        Write-Host "FATAL ERROR occurred. Details logged to '$LogFilePath' (and potentially '$EarlyErrorLogPath')."
    } catch { 
        Write-Host "FATAL ERROR occurred, and could not write to fallback log '$EarlyErrorLogPath'. Error during fallback: $($_.Exception.Message)"
        Write-Host $errorMessage
    }
    exit 1
}

# Success
Write-Log "Setup script completed successfully."
exit 0