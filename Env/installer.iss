; -------- MinimalInstallerVisiblePS.iss --------
[Setup]
AppName=YourApp
AppVersion=1.0
DefaultDirName={pf}\YourApp      ; where files will be copied

[Files]
; Point Source to the folder created by your packaging script
Source: "C:\Path\To\Build\*";  DestDir: "{app}";  Flags: recursesubdirs ignoreversion

[Run]
Filename: "powershell.exe"; \
    Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\SetupFiles\setup.ps1"""; \
    Flags: waituntilterminated
; ----------------------------------------------
