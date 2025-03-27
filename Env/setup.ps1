# Set silent progress and error preferences.
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# --- Helper: Compare two version strings using [version] ---
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

# --- Helper: Prompt the user for yes/no (returns $true if yes) ---
function Ask-YesNo($message) {
    $response = Read-Host "$message (Y/N)"
    return ($response -match '^(Y|y)')
}

# --- Helper: Generate run_app.bat based on installed metadata ---
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

# --- Helper: Generate setup.bat to launch the installer ---
function Generate-SetupBat($targetDir) {
    $batContent = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0\SetupFiles\setup.ps1"
pause
"@
    $batPath = Join-Path $targetDir "setup.bat"
    $batContent | Out-File -Encoding ASCII $batPath
    Write-Output "Generated setup.bat at '$batPath'."
}

Write-Output "=== Starting setup/update ==="

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

# Define marker location in ProgramData.
$markerDir = Join-Path $env:ProgramData $newAppName
$markerFile = Join-Path $markerDir "metadata.txt"

# Determine target installation directory.
if (Test-Path $markerFile) {
    # Read installed metadata from the marker.
    $installedMarker = @{}
    Get-Content $markerFile | ForEach-Object {
        if ($_ -match "^\s*([^=]+)\s*=\s*(.+)$") {
            $installedMarker[$matches[1]] = $matches[2]
        }
    }
    $installedVersion = $installedMarker["Version"]
    $installedPath    = $installedMarker["InstallPath"]
    Write-Output "Found marker in ProgramData:"
    Write-Output "  Installed Version: $installedVersion"
    Write-Output "  Installed Path: $installedPath"
    
    # Verify that the installation folder exists and has expected subfolders.
    $envFolder = Join-Path $installedPath "env"
    $setupFilesFolder = Join-Path $installedPath "SetupFiles"
    if ((-Not (Test-Path $installedPath)) -or (-Not (Test-Path $envFolder)) -or (-Not (Test-Path $setupFilesFolder))) {
        Write-Output "Marker found, but installation folder structure is missing or incomplete."
        Write-Output "Performing clean install..."
        if (Test-Path $installedPath) { Remove-Item $installedPath -Recurse -Force }
        New-Item -ItemType Directory -Path $installedPath | Out-Null
        $targetDir = $installedPath
    }
    else {
        $cmp = Compare-Versions $newVersion $installedVersion
        if ($cmp -le 0) {
            Write-Output "New package version ($newVersion) is same or older than installed version ($installedVersion)."
            if (-not (Ask-YesNo "Do you really want to install an older/same version? This will perform a clean install.")) {
                Write-Output "Update cancelled by user."
                exit
            }
            else {
                Write-Output "Performing clean install..."
                Remove-Item $installedPath -Recurse -Force
                New-Item -ItemType Directory -Path $installedPath | Out-Null
                $targetDir = $installedPath
            }
        }
        else {
            Write-Output "Updating existing installation from version $installedVersion to $newVersion."
            $targetDir = $installedPath
        }
    }
}
else {
    # No marker exists; use default installation folder.
    $targetDir = Join-Path "C:\Python Apps" $newAppName
    if (-Not (Test-Path $targetDir)) {
        Write-Output "No previous installation found. Creating new installation at: $targetDir"
        New-Item -ItemType Directory -Path $targetDir | Out-Null
    }
    if (-Not (Test-Path $markerDir)) {
        New-Item -ItemType Directory -Path $markerDir | Out-Null
    }
}

Write-Output "Target installation directory is: $targetDir"

# --- Copy Package Contents ---
# We copy the contents of the parent of $scriptDir (which is the packaged folder)
# Exclude any top-level BAT files so they don't overwrite our dynamically generated ones.
Write-Output "Copying package contents from '$scriptDir\..\*' to '$targetDir'..."
Copy-Item -Path "$($scriptDir)\..\*" -Destination $targetDir -Recurse -Force -Exclude *.bat

# --- Generate our BAT launchers (so they override any BAT files from the package) ---
Generate-SetupBat $targetDir
Generate-RunScript $targetDir

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

# --- Update marker file in ProgramData ---
$markerData = "AppName=$newAppName`nVersion=$newVersion`nInstallPath=$targetDir"
Set-Content -Path $markerFile -Value $markerData -Encoding UTF8
Write-Output "Updated marker file at $markerFile"

Read-Host -Prompt "Press Enter to exit"
