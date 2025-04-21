[Setup]
AppName={#AppName}
AppVersion={#AppVer}
DefaultDirName={pf}\{#AppName}
OutputBaseFilename={#OutputName}
OutputDir=.

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Run]
Filename: "powershell.exe"; \
    Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\SetupFiles\setup.ps1"""; \
    Flags: waituntilterminated
