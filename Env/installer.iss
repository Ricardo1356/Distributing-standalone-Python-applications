; AppName and AppVersion are defined by the build script via /D command-line switches

[Setup]
AppId={{ef824ac7-86d2-49a4-8bd5-b8b538fc11fe}-{#AppName}}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={commonpf}\PythonApps\{#AppName}
DefaultGroupName={#AppName}
OutputBaseFilename={#AppName}-{#AppVersion}-Installer
Compression=lzma
WizardStyle=modern
SolidCompression=yes
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppName}.ico
UninstallDisplayName={#AppName}
UninstallFilesDir={app}\_internal

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Run]
Filename: "powershell.exe"; Parameters: "-STA -ExecutionPolicy Bypass -NoProfile -File ""{app}\_internal\setup.ps1"" -InstallPath ""{app}"""; Flags: waituntilterminated runhidden

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\Env\pythonw.exe"; Parameters: """{app}\_internal\boot.py"""; WorkingDir: "{app}"; IconFilename: "{app}\{#AppName}.ico"
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\Env\pythonw.exe"; Parameters: """{app}\_internal\boot.py"""; WorkingDir: "{app}"; IconFilename: "{app}\{#AppName}.ico"; Tasks: desktopicon
Name: "{app}\Run {#AppName}"; Filename: "{app}\Env\pythonw.exe"; Parameters: """{app}\_internal\boot.py"""; WorkingDir: "{app}"; IconFilename: "{app}\{#AppName}.ico"

[Tasks]
Name: desktopicon; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:";

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
