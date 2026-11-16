; Instalador de QvaTube para Windows (Inno Setup 6).
; Lo compila .github/workflows/escritorio.yml:
;   iscc /DAppVersion=1.2.11 /DSourceDir=build\windows\x64\runner\Release windows\packaging\qvatube.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
AppId={{6B2D8E1A-4F3C-4E8B-9A71-2C5D0E9F7A41}
AppName=QvaTube
AppVersion={#AppVersion}
AppVerName=QvaTube {#AppVersion}
AppPublisher=QvaTube
AppPublisherURL=https://qvatube.hidenplay.net
AppSupportURL=https://t.me/qvatube
DefaultDirName={autopf}\QvaTube
DefaultGroupName=QvaTube
DisableProgramGroupPage=yes
; Sin permisos de administrador: se instala para el usuario actual.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=QvaTube-{#AppVersion}-windows-x64-instalador
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\qvatube.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Cierra QvaTube si está abierta al actualizar.
CloseApplications=yes

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\QvaTube"; Filename: "{app}\qvatube.exe"
Name: "{group}\Desinstalar QvaTube"; Filename: "{uninstallexe}"
Name: "{autodesktop}\QvaTube"; Filename: "{app}\qvatube.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\qvatube.exe"; Description: "{cm:LaunchProgram,QvaTube}"; Flags: nowait postinstall skipifsilent
