; MyAppInstaller.iss – prompts for install folder, default under ProgramFiles\PythonApps

#define AppName "MyPythonApp"
#define AppVersion "1.0.0"

[Setup]
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={commonpf}\PythonApps\{#AppName}
DefaultGroupName={#AppName}
OutputBaseFilename={#AppName}_Installer
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppName}.ico  ; Optional: Specify an icon for the uninstaller
UninstallDisplayName={#AppName} (Remove Only)

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
; Optional: Add an icon file to your build directory if you want one for the uninstaller
; Source: "{#BuildDir}\{#AppName}.ico"; DestDir: "{app}"

[Run]
; Pass the chosen {app} directory as the install path
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\SetupFiles\setup.ps1"" -InstallPath ""{app}"""; Flags: waituntilterminated

[UninstallDelete]
; Remove the entire application directory and all its contents during uninstall
Type: filesandordirs; Name: "{app}"