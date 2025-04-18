[Setup]
AppName=TestInstaller
AppVersion=1.1
DefaultDirName=C:\Python Apps\TestInstaller
OutputBaseFilename=TestInstallerInstaller
PrivilegesRequired=admin
Compression=lzma
SolidCompression=yes
OutputDir=Output

[Files]
; This includes all packaged files from _temp\TestInstaller into the user-chosen {app}.
Source: "_temp\TestInstaller\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\TestInstaller"; Filename: "{app}\run_app.bat"
Name: "{userdesktop}\TestInstaller"; Filename: "{app}\run_app.bat"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"

[Run]
; Pass the final install location as -TargetPath, and place the log next to the installer exe (i.e. {src})
Filename: "powershell.exe"; \
  Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\SetupFiles\setup.ps1"" -TargetPath ""{app}"" -LogPath ""{src}\testinstaller_setup.log"""; \
  Flags: waituntilterminated
