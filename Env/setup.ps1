param(
    [string]$InstallPath = $null
)

# Set silent progress and error preferences.
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Add debugging to capture and display errors
$ErrorLogPath = "$env:TEMP\app_install_error.log"
try {
    # --- Helper functions remain unchanged ---
    function Compare-Versions($v1, $v2) {
        try {
            $ver1 = [version]$v1
            $ver2 = [version]$v2
            return $ver1.CompareTo($ver2)
        }
        catch {
            Write-Output "Version comparison failed: $_"
            return 0
        }
    }

    function Ask-YesNo($message) {
        $response = Read-Host "$message (Y/N)"
        return ($response -match '^(Y|y)')
    }

    function Generate-RunScript($targetDir) {
        $metaFile = Join-Path $targetDir "SetupFiles\metadata.txt"
        if (-Not (Test-Path $metaFile)) {
            Write-Output "Warning: metadata.txt not found in $targetDir\SetupFiles. Skipping run_app.bat update."
            return
        }
        $installedMetadata = @{}
        Get-Content $metaFile | ForEach-Object {
            if ($_ -match "^\s*([^=]+)\s*=\s*(.+)$") {
                $installedMetadata[$matches[1]] = $matches[2]
            }
        }
        $appVersionInstalled = $installedMetadata["Version"]
        $batContent = @"
@echo off
cd /d "%~dp0"
echo Launching the application...
echo Application Version: $appVersionInstalled
env\python.exe SetupFiles\boot.py
pause
"@
        $batPath = Join-Path $targetDir "run_app.bat"
        $batContent | Out-File -Encoding ASCII $batPath
        Write-Output "Generated run_app.bat at '$batPath'."
    }

    function Generate-SetupBat($targetDir) {
        $batContent = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0\SetupFiles\setup.ps1" -InstallPath "%~dp0"
pause
"@
        $batPath = Join-Path $targetDir "setup.bat"
        $batContent | Out-File -Encoding ASCII $batPath
        Write-Output "Generated setup.bat at '$batPath'."
    }

    Write-Output "=== Starting setup/update ==="
    Write-Output "Running with user: $env:USERNAME"
    Write-Output "Current directory: $(Get-Location)"
    
    # Additional debugging for InstallPath
    Write-Output "InstallPath parameter received: '$InstallPath'"

    # Determine the folder where this script is located.
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    Write-Output "Script directory is: $scriptDir"

    # Read package metadata from metadata.txt (assumed to be in the same folder as this script).
    $packageMetadataFile = Join-Path $scriptDir "metadata.txt"
    if (-Not (Test-Path $packageMetadataFile)) {
        throw "No metadata.txt found in $scriptDir. Aborting."
    }

    $packageMetadata = @{}
    Get-Content $packageMetadataFile | ForEach-Object {
        if ($_ -match "^\s*([^=]+)\s*=\s*(.+)$") {
            $packageMetadata[$matches[1]] = $matches[2]
        }
    }

    $newAppName    = $packageMetadata["AppName"]
    $newEntryFile  = $packageMetadata["EntryFile"]
    $newVersion    = $packageMetadata["Version"]
    $appFolderName = $packageMetadata["AppFolder"]

    Write-Output "Package metadata:"
    Write-Output "  AppName: $newAppName"
    Write-Output "  AppFolder: $appFolderName"
    Write-Output "  EntryFile: $newEntryFile"
    Write-Output "  New Package Version: $newVersion"

    # Determine target installation directory
    if ($InstallPath -eq $null -or $InstallPath -eq "") {
        # Use current directory as default if no path provided
        $targetDir = (Get-Location).Path
        Write-Output "No installation path provided, using current directory: $targetDir"
    } else {
        # Use the provided path
        $targetDir = $InstallPath
        
        # Create the directory if it doesn't exist
        if (-Not (Test-Path $targetDir)) {
            Write-Output "Creating installation directory: $targetDir"
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
    }

    Write-Output "Target installation directory is: $targetDir"
    Write-Output "Testing write permissions to target directory..."
    
    try {
        # Test writing permissions by creating and removing a test file
        $testFilePath = Join-Path $targetDir "test_write_permissions.tmp"
        "test" | Out-File -FilePath $testFilePath -ErrorAction Stop
        Remove-Item -Path $testFilePath -ErrorAction Stop
        Write-Output "Write permissions confirmed."
    } catch {
        Write-Output "ERROR: Cannot write to target directory. The installation may need administrator privileges."
        Write-Output "Error details: $_"
        throw "Installation failed due to insufficient permissions. Try running the installer as administrator."
    }

    # --- Copy Package Contents ---
    # We copy the contents of the parent of $scriptDir (which is the packaged folder)
    # Exclude any top-level BAT files so they don't overwrite our dynamically generated ones.
    $sourceDir = Split-Path -Parent $scriptDir
    Write-Output "Copying package contents from '$sourceDir\*' to '$targetDir'..."
    
    try {
        # Use robocopy instead of Copy-Item for better handling of permissions and errors
        # /E - copy subdirectories, including empty ones
        # /NFL - No file list - don't log file names
        # /NDL - No directory list - don't log directory names
        # /NJH - No job header
        # /NJS - No job summary
        # /XF - exclude files matching the specified names/paths/wildcards
        $robocopyArgs = @(
            "`"$sourceDir`"",
            "`"$targetDir`"", 
            "/E", 
            "/NFL", 
            "/NDL",
            "/NJH",
            "/NJS",
            "/XF", "*.bat"
        )
        
        Write-Output "Running: robocopy $robocopyArgs"
        $robocopyResult = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
        
        # Robocopy exit codes: 0 = no files copied, 1 = files copied successfully
        # Exit codes 0-7 are considered success
        if ($robocopyResult.ExitCode -gt 7) {
            Write-Output "WARNING: Robocopy reported some issues (exit code $($robocopyResult.ExitCode))"
        } else {
            Write-Output "Files copied successfully."
        }
    } catch {
        Write-Output "ERROR during file copy: $_"
        throw "Failed to copy application files."
    }

    # --- Generate our BAT launchers (so they override any BAT files from the package) ---
    Generate-SetupBat $targetDir
    Generate-RunScript $targetDir

    # --- Rest of the script remains the same ---
    # --- Determine required Python version from the requirements.txt in the app folder ---
    $reqFile = Join-Path $targetDir "$appFolderName\requirements.txt"
    if (-Not (Test-Path $reqFile)) { throw "Could not find $appFolderName\requirements.txt in $targetDir. Aborting setup." }
    Write-Output "Found requirements file at: $reqFile"
    $requiredPythonVersion = "3.10.0"  # default
    foreach ($line in Get-Content $reqFile) {
        if ($line -match "python==([\d\.]+)") {
            $requiredPythonVersion = $matches[1]
            Write-Output "Found required Python version: $requiredPythonVersion"
            break
        }
    }
    Write-Output "Using required Python version: $requiredPythonVersion"

    # --- Check bundled Python in the env folder ---
    $envDir = Join-Path $targetDir "env"
    $pythonExe = Join-Path $envDir "python.exe"
    $needPythonUpdate = $false
    if (Test-Path $pythonExe) {
        try {
            $installedPythonVerStr = & $pythonExe -c "import platform; print(platform.python_version())"
            Write-Output "Installed bundled Python version: $installedPythonVerStr"
            if ([version]$installedPythonVerStr -ne [version]$requiredPythonVersion) {
                Write-Output "Installed Python version does not match required version. Updating bundled Python..."
                $needPythonUpdate = $true
            }
        }
        catch {
            Write-Output "Error determining installed Python version. Will update bundled Python."
            $needPythonUpdate = $true
        }
    }
    else {
        Write-Output "No bundled Python found. Need to download."
        $needPythonUpdate = $true
    }

    if ($needPythonUpdate) {
        if (Test-Path $envDir) { Remove-Item $envDir -Recurse -Force }
        New-Item -ItemType Directory -Path $envDir | Out-Null
        Write-Output "Downloading embeddable Python $requiredPythonVersion..."
        $zipUrl = "https://www.python.org/ftp/python/$requiredPythonVersion/python-$requiredPythonVersion-embed-amd64.zip"
        Write-Output "Downloading from URL: $zipUrl"
        $zipFile = Join-Path $envDir "python-embed.zip"
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile
        Write-Output "Extracting Python embeddable package..."
        Expand-Archive -Path $zipFile -DestinationPath $envDir -Force
        Remove-Item $zipFile
        Write-Output "Bundled Python updated."
        
        $customPthFile = Join-Path $targetDir "SetupFiles\custom_pth.txt"
        if (Test-Path $customPthFile) {
            $pthFile = Get-ChildItem -Path $envDir -Filter "*._pth" | Select-Object -First 1
            if ($pthFile) {
                Write-Output "Replacing _pth file '$($pthFile.FullName)' with custom version from '$customPthFile'..."
                $customContent = Get-Content $customPthFile -Raw
                Set-Content -Path $pthFile.FullName -Value $customContent -Encoding ASCII
                Write-Output "New _pth file content:"
                Write-Output (Get-Content $pthFile.FullName -Raw)
            }
            else {
                Write-Output "No _pth file found in '$envDir'."
            }
        }
    }

    # --- Ensure pip is installed in the env ---
    Write-Output "Checking if pip is installed..."
    $pipVersion = ""
    try {
        $pipVersion = & $pythonExe -m pip --version 2>&1
    } catch {
        Write-Output "pip is not installed."
    }
    if ($pipVersion -notmatch "pip") {
        Write-Output "Attempting to install pip..."
        $env:PYTHONHOME = $envDir
        $env:PYTHONPATH = $envDir
        $getPipUrl = "https://bootstrap.pypa.io/get-pip.py"
        $getPipFile = Join-Path $envDir "get-pip.py"
        Write-Output "Downloading get-pip.py from $getPipUrl..."
        Invoke-WebRequest -Uri $getPipUrl -OutFile $getPipFile
        Write-Output "Running get-pip.py..."
        & $pythonExe $getPipFile
        Remove-Item $getPipFile
        Write-Output "Finished installing pip."
        $pipVersion = & $pythonExe -m pip --version 2>&1
        if ($pipVersion -notmatch "pip") { throw "Failed to install pip." }
        else { Write-Output "pip installed successfully: $pipVersion" }
    }
    else {
        Write-Output "pip is already installed: $pipVersion"
    }

    # --- Update Dependencies ---
    Write-Output "Installing/updating dependencies from $reqFile..."
    $deps = Get-Content $reqFile | Where-Object { $_ -notmatch "^\s*python\s*==" }
    if ($deps) {
        $tempReqFile = Join-Path $targetDir "temp_requirements.txt"
        $deps | Out-File -Encoding ASCII $tempReqFile
        Write-Output "Running: & $pythonExe -m pip install -r $tempReqFile"
        & $pythonExe -m pip install -r $tempReqFile
        Remove-Item $tempReqFile
        Write-Output "Dependencies updated."
    }
    else {
        Write-Output "No dependencies to install/update."
    }

    # --- Re-generate run_app.bat based on installed metadata ---
    Generate-RunScript $targetDir

    Write-Output "Update complete. Application version updated to $newVersion."
    Write-Output "Installation/Update is complete at: $targetDir"

    Read-Host -Prompt "Press Enter to exit"
    
} catch {
    $errorMessage = "ERROR: $($_.Exception.Message)`r`n$($_.ScriptStackTrace)"
    $errorMessage | Out-File -FilePath $ErrorLogPath -Append
    Write-Output $errorMessage
    Write-Output "Installation failed. Error log saved to: $ErrorLogPath"
    Read-Host -Prompt "Press Enter to exit"
    exit 1
}