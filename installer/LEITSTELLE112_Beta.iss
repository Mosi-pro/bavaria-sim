; Inno-Setup-Skript für die BETA-Version (getrennt von der normalen Version: eigene AppId,
; eigener Installationsordner, eigene Spielstände unter %APPDATA%\LEITSTELLE112_Beta)
; Kompilieren: ISCC.exe installer\LEITSTELLE112_Beta.iss   (erwartet den Build unter build\windows_beta)
;
; Testversion aus Entwicklungszweigen: dasselbe Skript mit Schalter /DTest
;   ISCC.exe /DTest installer\LEITSTELLE112_Beta.iss   (erwartet den Build unter build\windows_test)
; -> eigene AppId, eigener Installationsordner und Startmenü-Eintrag, getrennt von Beta und normaler Version.

#define AppVersion "1.5.0"
#ifdef Test
  #define AppName "LEITSTELLE 112 TEST"
  #define AppExe "LEITSTELLE112_TEST.exe"
  #define AppGuid "{{A41F7C2E-5B19-4D8A-B3E2-112BAVAR7E57}"
  #define BuildDir "windows_test"
  #define OutDir "installer_test"
  #define OutName "LEITSTELLE112_TEST_Setup"
#else
  #define AppName "LEITSTELLE 112 BETA"
  #define AppExe "LEITSTELLE112_BETA.exe"
  #define AppGuid "{{6E0A1C7B-3D2B-4B6E-9F11-112BAVARBE7A1}"
  #define BuildDir "windows_beta"
  #define OutDir "installer_beta"
  #define OutName "LEITSTELLE112_BETA_Setup"
#endif

[Setup]
AppId={#AppGuid}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Leitstelle 112 Projekt
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=no
AllowNoIcons=yes
OutputDir=..\build\{#OutDir}
OutputBaseFilename={#OutName}_{#AppVersion}
SetupIconFile=..\assets\icons\icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog
LicenseFile=..\build\{#BuildDir}\LIZENZHINWEISE.txt

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\{#BuildDir}\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\{#BuildDir}\config\*"; DestDir: "{app}\config"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\{#BuildDir}\config_standard\*"; DestDir: "{app}\config_standard"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\{#BuildDir}\LIESMICH.txt"; DestDir: "{app}"; Flags: ignoreversion isreadme
Source: "..\build\{#BuildDir}\LIZENZHINWEISE.txt"; DestDir: "{app}"; Flags: ignoreversion

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
