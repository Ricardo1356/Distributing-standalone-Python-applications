; --- MyAppInstaller.iss ---
[Setup]
AppName=MyPythonApp
AppVersion=1.0
DefaultDirName={pf}\MyPythonApp
DefaultGroupName=MyPythonApp
OutputBaseFilename=MyPythonInstaller
Compression=lzma
SolidCompression=yes
; We need admin privileges because the script writes to %ProgramData% and may remove folders
PrivilegesRequired=admin

[Files]
; 1) Include your entire "SetupFiles" directory (which holds setup.ps1, metadata.txt, etc.)
;    Adjust the source path to where these files live on your dev machine:
Source: "C:\path\to\SetupFiles\*"; DestDir: "{app}\SetupFiles"; Flags: recursesubdirs ignoreversion

; 2) If you have other files (like your main .zip or a packaged folder) you want installed:
;    Example: a build artifact MyApp.zip
Source: "C:\School\b\ENV2"; DestDir: "{app}\SetupFiles"; Flags: ignoreversion

; (Add any other files you need copied into {app}. For example, you might be
;  packaging the entire output from your dev script. If so, specify them here.)

[Run]
; After files are installed to {app}, run the PowerShell script.
; We'll do it in hidden mode so the user doesn't see a console window:
Filename: "powershell.exe"; \
    Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\SetupFiles\setup.ps1"" -Silent"; \
    Flags: waituntilterminated runhidden
