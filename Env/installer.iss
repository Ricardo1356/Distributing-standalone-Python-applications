[Setup]
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={commonpf}\PythonApps\{#AppName}
DefaultGroupName={#AppName}
OutputBaseFilename={#AppName}-{#AppVersion}-Installer
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
UninstallDisplayIcon={app}\_internal\{#AppName}.ico
UninstallDisplayName={#AppName} (Remove Only)
UninstallFilesDir={app}\_internal

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
Source: "{#BuildDir}\_internal\*"; DestDir: "{app}\_internal"; Flags: ignoreversion


[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\env\pythonw.exe"; Parameters: """{app}\_internal\boot.py"""; WorkingDir: "{app}"; IconFilename: "{app}\_internal\{#AppName}.ico"
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\env\pythonw.exe"; Parameters: """{app}\_internal\boot.py"""; WorkingDir: "{app}"; IconFilename: "{app}\_internal\{#AppName}.ico"; Tasks: desktopicon
Name: "{app}\Run {#AppName}"; Filename: "{app}\env\pythonw.exe"; Parameters: """{app}\_internal\boot.py"""; WorkingDir: "{app}"; IconFilename: "{app}\_internal\{#AppName}.ico"

[Tasks]
Name: desktopicon; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:";

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
var
  SetupScriptFailed: Boolean; // Flag to track script failure

// Function to log messages to a temp file
procedure LogMessage(Msg: string);
var
  LogFileName: string;
begin
  LogFileName := ExpandConstant('{tmp}\InnoSetupRunResult.log');
  SaveStringToFile(LogFileName, Msg + #13#10, True);
end;

// Function to execute the PowerShell setup script
function RunPowerShellSetup: Boolean;
var
  ResultCode: Integer;
  PSPath: string;
  Params: string;
  AppPath: string;
begin
  AppPath := ExpandConstant('{app}'); // Get installation path
  PSPath := 'powershell.exe';
  Params := '-ExecutionPolicy Bypass -NoProfile -File "' + AppPath + '\_internal\setup.ps1" -InstallPath "' + AppPath + '"';

  LogMessage('Executing: ' + PSPath + ' ' + Params);

  // Execute PowerShell, hide the window, wait for it, and capture the exit code
  if not Exec(PSPath, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    LogMessage('Exec failed to run PowerShell itself.');
    Result := False; // Exec itself failed
  end
  else
  begin
    LogMessage('PowerShell setup.ps1 ResultCode: ' + IntToStr(ResultCode));
    // Return True if PowerShell script succeeded (ExitCode 0), False otherwise
    Result := (ResultCode = 0);
  end;
end;

// Called when the installation step changes
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    // Run the setup script during the main installation phase
    SetupScriptFailed := not RunPowerShellSetup(); // Set flag if script fails

    // If the script failed, abort the installation immediately
    if SetupScriptFailed then
    begin
      LogMessage('Setup script failed. Aborting installation.');
      // Abort the installation process. DeinitializeSetup should still run.
      WizardForm.Close; // This signals an abort/close request
    end;
  end;
end;

// Called just before Setup terminates.
procedure DeinitializeSetup();
begin
  // If the script failed during installation, show the error message now.
  if SetupScriptFailed then
  begin
    MsgBox('Setup failed because the required configuration script did not complete successfully. Please check the logs (' + ExpandConstant('{tmp}\InnoSetupRunResult.log') + ' and C:\Program Files\PythonApps\Logs) for details. The application might be partially installed and require manual uninstallation.', mbError, MB_OK);
  end;
end;

// Initialize the flag
procedure InitializeWizard;
begin
  SetupScriptFailed := False;
end;
