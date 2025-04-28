; MyAppInstaller.iss – prompts for install folder, default under ProgramFiles\PythonApps
; AppName and AppVersion are defined by the build script via /D command-line switches

[Setup]
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={commonpf}\PythonApps\{#AppName}
DefaultGroupName={#AppName}
OutputBaseFilename={#AppName}-{#AppVersion}-Installer
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppName}.ico
UninstallDisplayName={#AppName}
UninstallFilesDir={app}\SetupFiles

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
; Optional: Add an icon file to your build directory if you want one for the shortcuts/uninstaller
; Source: "{#BuildDir}\{#AppName}.ico"; DestDir: "{app}"

[Run]
; Pass the chosen {app} directory as the install path
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\SetupFiles\setup.ps1"" -InstallPath ""{app}"""; Flags: waituntilterminated runhidden

[Icons]
; Start Menu Shortcut - Use pythonw.exe to avoid console window
Name: "{group}\{#AppName}"; Filename: "{app}\Env\pythonw.exe"; Parameters: """{app}\SetupFiles\boot.py"""; WorkingDir: "{app}"; IconFilename: "{app}\{#AppName}.ico"
; Desktop Shortcut (Optional) - Use pythonw.exe to avoid console window
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\Env\pythonw.exe"; Parameters: """{app}\SetupFiles\boot.py"""; WorkingDir: "{app}"; IconFilename: "{app}\{#AppName}.ico"; Tasks: desktopicon
; Shortcut directly in the installation folder
Name: "{app}\Run {#AppName}"; Filename: "{app}\Env\pythonw.exe"; Parameters: """{app}\SetupFiles\boot.py"""; WorkingDir: "{app}"; IconFilename: "{app}\{#AppName}.ico"

[Tasks]
; Add a checkbox during setup to let the user choose whether to create a desktop icon
Name: desktopicon; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:";

[UninstallDelete]
; Remove the entire application directory and all its contents during uninstall
Type: filesandordirs; Name: "{app}"
