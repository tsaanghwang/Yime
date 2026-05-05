#define MyAppName "Yime"
#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif
#ifndef MyPortableDistDir
  #define MyPortableDistDir AddBackslash(SourcePath) + "dist\\Yime"
#endif
#ifndef MySetupOutputDir
  #define MySetupOutputDir AddBackslash(SourcePath) + "dist\\setup"
#endif

[Setup]
AppId={{A3E50D5E-1E9E-43A0-8F9D-A9BA8F4FC3D8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Yime Prototype
AppPublisherURL=https://github.com/tsaanghwang/Yime
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
LicenseFile=LICENSE
OutputDir={#MySetupOutputDir}
OutputBaseFilename=Yime-Setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
SetupLogging=yes
UninstallDisplayIcon={app}\Yime.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "{#MyPortableDistDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\Yime.exe"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\Yime.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Yime.exe"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
