; Inno-Setup-Skript für die BETA-Version (getrennt von der normalen Version: eigene AppId,
; eigener Installationsordner, eigene Spielstände unter %APPDATA%\LEITSTELLE112_Beta)
; Kompilieren: ISCC.exe installer\LEITSTELLE112_Beta.iss   (erwartet den Build unter build\windows_beta)

#define AppName "LEITSTELLE 112 BETA"
#define AppVersion "1.5.0"
#define AppExe "LEITSTELLE112_BETA.exe"

[Setup]
AppId={{6E0A1C7B-3D2B-4B6E-9F11-112BAVARBE7A1}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Leitstelle 112 Projekt
DefaultDirName={autopf}\LEITSTELLE 112 BETA
DefaultGroupName=LEITSTELLE 112 BETA
DisableProgramGroupPage=no
AllowNoIcons=yes
OutputDir=..\build\installer_beta
OutputBaseFilename=LEITSTELLE112_BETA_Setup_{#AppVersion}
SetupIconFile=..\assets\icons\icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog
LicenseFile=..\build\windows_beta\LIZENZHINWEISE.txt

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows_beta\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows_beta\config\*"; DestDir: "{app}\config"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\windows_beta\config_standard\*"; DestDir: "{app}\config_standard"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\windows_beta\LIESMICH.txt"; DestDir: "{app}"; Flags: ignoreversion isreadme
Source: "..\build\windows_beta\LIZENZHINWEISE.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Liesmich"; Filename: "{app}\LIESMICH.txt"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: dirifempty; Name: "{app}\config"
Type: dirifempty; Name: "{app}"
