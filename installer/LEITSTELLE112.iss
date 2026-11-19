; Inno-Setup-Skript für LEITSTELLE 112
; Kompilieren: ISCC.exe installer\LEITSTELLE112.iss   (erwartet den fertigen Build unter build\windows)

#define AppName "LEITSTELLE 112"
#define AppVersion "1.4.1"
#define AppExe "LEITSTELLE112.exe"

[Setup]
AppId={{6E0A1C7B-3D2B-4B6E-9F11-112BAVAR1A01}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Leitstelle 112 Projekt
DefaultDirName={autopf}\LEITSTELLE 112
DefaultGroupName=LEITSTELLE 112
DisableProgramGroupPage=no
AllowNoIcons=yes
OutputDir=..\build\installer
OutputBaseFilename=LEITSTELLE112_Setup_{#AppVersion}
SetupIconFile=..\assets\icons\icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog
LicenseFile=..\build\windows\LIZENZHINWEISE.txt

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\config\*"; DestDir: "{app}\config"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\windows\config_standard\*"; DestDir: "{app}\config_standard"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\windows\LIESMICH.txt"; DestDir: "{app}"; Flags: ignoreversion isreadme
Source: "..\build\windows\LIZENZHINWEISE.txt"; DestDir: "{app}"; Flags: ignoreversion

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
