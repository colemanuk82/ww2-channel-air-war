; Inno Setup script for WW2 Channel Air War. Build: ISCC.exe installer\setup.iss  (output: build\WW2ChannelAirWar_Setup_v2.29.exe)
; Installs per-user (no administrator rights).
#define AppName "WW2 Channel Air War"
#define AppVer "2.29"

[Setup]
AppId={{6E1C7B2A-5D0B-4B8E-9C53-2F4A7A1D9E10}
AppName={#AppName}
AppVersion={#AppVer}
AppPublisher=WW2 Channel Air War
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
OutputDir=..\build
OutputBaseFilename=WW2ChannelAirWar_Setup_v{#AppVer}
Compression=lzma2/max
SolidCompression=yes
LicenseFile=..\docs\legal\EULA.txt
UninstallDisplayIcon={app}\WW2ChannelAirWar.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
DisableProgramGroupPage=yes

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "..\build\WW2ChannelAirWar.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\legal\EULA.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\legal\PRIVACY.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\legal\CREDITS.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\WW2ChannelAirWar.exe"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\WW2ChannelAirWar.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\WW2ChannelAirWar.exe"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; NVIDIA DLSS components that older versions (built on the RTX engine) could download are removed with the game
Type: filesandordirs; Name: "{app}\licenses"
Type: files; Name: "{app}\sl.*.dll"
Type: files; Name: "{app}\nvngx_*.dll"
Type: files; Name: "{app}\NvLowLatencyVk.dll"
