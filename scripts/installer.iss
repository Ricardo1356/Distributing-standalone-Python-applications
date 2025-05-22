[Setup]
; ATTENTION: Developer Action Recommended
; The AppId below uses an example GUID (ef824ac7-86d2-49a4-8bd5-b8b538fc11fe).
; For your application, it's highly recommended to generate a new, unique GUID.
; Please replace "ef824ac7-86d2-49a4-8bd5-b8b538fc11fe" with your new GUID in two places:
;   1. Here in the AppId definition.
;   2. In the [Code] section, within the GetInstalledVersion function (variable AppIdValue).
; Using a unique GUID helps prevent potential conflicts with other applications and ensures correct uninstall behavior.
AppId={{ef824ac7-86d2-49a4-8bd5-b8b538fc11fe}-{#AppName}}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={userpf}\{#AppName}
DefaultGroupName={#AppName}
OutputBaseFilename={#AppName}-{#AppVersion}
Compression=lzma
WizardStyle=modern
SolidCompression=yes
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\{#AppName}.ico
UninstallDisplayName={#AppName}
UninstallFilesDir={app}\_internal

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Run]
Filename: "powershell.exe"; Parameters: "-STA -ExecutionPolicy Bypass -NoProfile -File ""{app}\_internal\setup.ps1"" -InstallPath ""{app}"" -CurrentInstalledVersion ""{code:GetInstalledVersion}"" -NewAppVersion ""{#AppVersion}"" -AppIdForRegistry ""{{ef824ac7-86d2-49a4-8bd5-b8b538fc11fe}-{#AppName}}"""; Flags: waituntilterminated runhidden

[Icons]
Name: "{userprograms}\{#AppName}\{#AppName}"; Filename: "{app}\Env\pythonw.exe"; Parameters: """{app}\_internal\boot.py"""; WorkingDir: "{app}"; IconFilename: "{app}\{#AppName}.ico"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\Env\pythonw.exe"; Parameters: """{app}\_internal\boot.py"""; WorkingDir: "{app}"; IconFilename: "{app}\{#AppName}.ico"; Tasks: desktopicon
Name: "{app}\Run {#AppName}"; Filename: "{app}\Env\pythonw.exe"; Parameters: """{app}\_internal\boot.py"""; WorkingDir: "{app}"; IconFilename: "{app}\{#AppName}.ico"

[Tasks]
Name: desktopicon; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:";

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
function GetInstalledVersion(Param: String): String;
var
  UninstallKeyBase: string;
  InstalledVersion: string;
  AppIdValue: string;
begin
  Result := '';
  // ISPP replaces {#AppName} with its value, making it a literal part of the string.
  // Note: If you have updated the GUID in the [Setup] section's AppId,
  // please ensure it is also updated here to match.
  AppIdValue := '{{ef824ac7-86d2-49a4-8bd5-b8b538fc11fe}-{#AppName}}';
  UninstallKeyBase := 'Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\' + AppIdValue + '_is1';

  if RegQueryStringValue(HKCU, UninstallKeyBase, 'DisplayVersion', InstalledVersion) then
  begin
    Result := InstalledVersion;
    Exit;
  end;

  if RegQueryStringValue(HKLM, UninstallKeyBase, 'DisplayVersion', InstalledVersion) then
  begin
    Result := InstalledVersion;
    Exit;
  end;
end;