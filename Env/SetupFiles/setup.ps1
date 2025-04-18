$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# --- Logging ---
function Log {
    param($msg)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "$timestamp $msg"
    $line | Out-File -Append -FilePath $Global:LogFile
    Write-Output $line
}

# --- Compare two version strings using [version] ---
function Compare-Versions($v1, $v2) {
    try {
        return ([version]$v1).CompareTo([version]$v2)
    } catch {
        Log "Version comparison failed: $_"
        return 0
    }
}

# --- Generate run_app.bat ---
function Generate-RunScript($targetDir, $version) {
    $bat = @"
@echo off
cd /d "%~dp0"
echo Launching the application...
echo Application Version: $version
env\python.exe SetupFiles\boot.py
pause
"@
    $path = Join-Path $targetDir "run_app.bat"
    $bat | Out-File -Encoding ASCII $path
    Log "Generated run_app.bat at '$path'."
}

# --- Generate setup.bat ---
function Generate-SetupBat($targetDir) {
    $bat = '@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0\SetupFiles\setup.ps1"
pause'
    $path = Join-Path $targetDir "setup.bat"
    $bat | Out-File -Encoding ASCII $path
    Log "Generated setup.bat at '$path'."
}

# --- MAIN SCRIPT START ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$logName = "testinstaller_setup.log"
$LogFile = Join-Path $PSScriptRoot "..\..\Output\$logName"
Log "=== Starting setup/update ==="

$targetDir = $env:TargetPath
if (-not $targetDir) {
    $targetDir = Join-Path "C:\Python Apps" "TestInstaller"
    Log "No -TargetPath passed, using default: $targetDir"
}
Log "User-chosen install directory: $targetDir"

$setupFiles = Join-Path $targetDir "SetupFiles"
Log "SetupFiles directory: $setupFiles"

# --- Load metadata ---
$metadata = Join-Path $setupFiles "metadata.txt"
if (-Not (Test-Path $metadata)) { throw "Missing metadata.txt in $setupFiles" }

$meta = @{}
Get-Content $metadata | ForEach-Object {
    if ($_ -match "^\s*([^=]+)\s*=\s*(.+)$") { $meta[$matches[1]] = $matches[2] }
}
$appName = $meta["AppName"]
$appFolder = $meta["AppFolder"]
$entryFile = $meta["EntryFile"]
$newVersion = $meta["Version"]
Log "Package metadata:`n  AppName: $appName`n  AppFolder: $appFolder`n  EntryFile: $entryFile`n  New Package Version: $newVersion"

# --- Marker ---
$markerDir = Join-Path $env:ProgramData $appName
$markerFile = Join-Path $markerDir "metadata.txt"
$doClean = $false

if (Test-Path $markerFile) {
    $installedMeta = @{}
    Get-Content $markerFile | ForEach-Object {
        if ($_ -match "^\s*([^=]+)\s*=\s*(.+)$") { $installedMeta[$matches[1]] = $matches[2] }
    }
    $installedVer = $installedMeta["Version"]
    $installedPath = $installedMeta["InstallPath"]
    Log "Marker found in ProgramData:`n  Installed Version: $installedVer`n  Installed Path: $installedPath"

    if ((Compare-Versions $newVersion $installedVer) -le 0) {
        Log "New version ($newVersion) is same/older than installed ($installedVer)."
        $doClean = $true
    }
} else {
    Log "No marker found; fresh install to $targetDir."
    $doClean = $true
}

if ($doClean -and (Test-Path $targetDir)) {
    Remove-Item $targetDir -Recurse -Force
}
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
Log "Effective installation path: $targetDir"

# --- Copy Package Contents ---
if ($scriptDir -eq $targetDir) {
    Log "Source ($scriptDir) and destination ($targetDir) are identical. Skipping file copy."
} else {
    Copy-Item -Path "$scriptDir\..\*" -Destination $targetDir -Recurse -Force -Exclude *.bat
    Log "Copied setup package to: $targetDir"
}

# --- Generate Scripts ---
Generate-SetupBat $targetDir
Generate-RunScript $targetDir $newVersion

# --- Python + pip Setup ---
$reqPath = Join-Path $targetDir "$appFolder\requirements.txt"
if (-Not (Test-Path $reqPath)) { throw "Could not find $appFolder\requirements.txt in $targetDir. Aborting setup." }
Log "Found requirements file at: $reqPath"

$pythonVer = "3.10.0"
foreach ($line in Get-Content $reqPath) {
    if ($line -match "python==([\d\.]+)") {
        $pythonVer = $matches[1]
        Log "Found required Python version: $pythonVer"
        break
    }
}
Log "Using required Python version: $pythonVer"

$envPath = Join-Path $targetDir "env"
$pyExe = Join-Path $envPath "python.exe"

if (-not (Test-Path $pyExe)) {
    Log "No bundled Python found. Need to download."
    New-Item -ItemType Directory -Path $envPath -Force | Out-Null
    $zip = "python-$pythonVer-embed-amd64.zip"
    $url = "https://www.python.org/ftp/python/$pythonVer/$zip"
    $dl = Join-Path $envPath $zip
    Log "Downloading from URL: $url"
    Invoke-WebRequest -Uri $url -OutFile $dl
    Expand-Archive -Path $dl -DestinationPath $envPath -Force
    Remove-Item $dl

    $pthFile = Get-ChildItem $envPath -Filter "*.pth" | Select-Object -First 1
    $customPth = Join-Path $setupFiles "custom_pth.txt"
    if (Test-Path $customPth -and $pthFile) {
        $correctZip = "python" + ($pythonVer -replace '\.', '') + ".zip"
        $newContent = Get-Content $customPth -Raw -Encoding ASCII
        $newContent = ($newContent -replace "^python.*?\.zip", $correctZip)
        Log "Using correct _pth first line: $correctZip"
        Log "Replacing _pth file '$($pthFile.FullName)' with updated content from '$customPth'..."
        $newContent | Out-File -Encoding ASCII $pthFile.FullName
        Log "New _pth file content:`n$newContent"
    }
    Log "Bundled Python updated."
}

# --- pip install ---
Log "Checking if pip is installed..."
$testPip = & $pyExe -m pip --version 2>&1
if ($testPip -notmatch "pip") {
    Log "Attempting to install pip..."
    $env:PYTHONHOME = $envPath
    $env:PYTHONPATH = $envPath
    $getPip = Join-Path $envPath "get-pip.py"
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $getPip
    $pipOut = & $pyExe $getPip 2>&1
    Log "Output from get-pip.py: $pipOut"
    Remove-Item $getPip
    $testPip = & $pyExe -m pip --version 2>&1
}
if ($testPip -notmatch "pip") {
    Log "Failed to install pip. Output: $testPip"
} else {
    Log "pip is already installed: $testPip"
}

# --- Dependencies ---
Log "Installing/updating dependencies from $reqPath..."
$tempReq = Join-Path $targetDir "temp_requirements.txt"
Get-Content $reqPath | Where-Object { $_ -notmatch "^\s*python\s*==" } | Set-Content -Encoding ASCII $tempReq
$pipResult = & $pyExe -m pip install -r $tempReq 2>&1
Log "Output from pip install: $pipResult"
Remove-Item $tempReq -Force
Log "Dependencies updated."

# --- Re-gen run_app.bat ---
Generate-RunScript $targetDir $newVersion

# --- Marker ---
if (-Not (Test-Path $markerDir)) {
    New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
}
$markerData = "AppName=$appName`nVersion=$newVersion`nInstallPath=$targetDir"
Set-Content -Path $markerFile -Value $markerData -Encoding UTF8
Log "Updated marker file at: $markerFile"

Log "Update complete. Application version updated to $newVersion."
Log "Installation/Update is complete at: $targetDir"

Read-Host -Prompt "Press Enter to exit"
