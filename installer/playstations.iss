; Instalador de EMUCHULL
[Setup]
AppName=EMUCHULL
AppVersion=1.0.0
DefaultDirName={commonpf}\EMUCHULL
DefaultGroupName=EMUCHULL
OutputBaseFilename=EMUCHULLSetup_x64
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern
PrivilegesRequired=admin
SetupIconFile=..\assets\icons\APP.ico

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
; Copia los archivos generados por `flutter build windows` (ejecutable + dll + assets)
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs
; Copia el icono del proyecto para que los accesos directos puedan usarlo
Source: "..\assets\icons\APP.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\EMUCHULL"; Filename: "{app}\emuchull.exe"; IconFilename: "{app}\APP.ico"
Name: "{commondesktop}\EMUCHULL"; Filename: "{app}\emuchull.exe"; Tasks: desktopicon; IconFilename: "{app}\APP.ico"

[Tasks]
Name: desktopicon; Description: "Crear acceso directo en el escritorio"; GroupDescription: "Accesos directos"; Flags: unchecked

[Run]
Filename: "{app}\emuchull.exe"; Description: "Ejecutar EMUCHULL"; Flags: nowait postinstall skipifsilent
