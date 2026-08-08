; Inno Setup script for Relocate (Windows).
;   1. pyinstaller packaging\Relocate.spec
;   2. iscc packaging\installer.iss
;
; Mirrors the macOS .pkg: installs the app, and points people at the Apple device
; stack they need for usbmux to see an iPhone at all.

#define AppName "Relocate"
#define AppVersion "1.0.0"
#define AppPublisher "Relocate"
#define AppExeName "Relocate.exe"

[Setup]
AppId={{7C4C0F1E-4C4B-4C7E-9C0B-2F1D9E3A55D1}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=Relocate-Setup-{#AppVersion}
SetupIconFile=..\relocate\resources\icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
; Per-machine install needs elevation; switch to lowest + {autopf}=userpf for per-user.
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "..\dist\Relocate\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[Code]
{ Relocate reaches the iPhone through Apple Mobile Device Service, which ships with
  iTunes or the Apple Devices app. Without it Windows cannot see the device at all,
  so warn rather than fail silently later. }
function AppleMobileDeviceSupportPresent(): Boolean;
begin
  Result :=
    RegKeyExists(HKLM, 'SOFTWARE\Apple Inc.\Apple Mobile Device Support') or
    RegKeyExists(HKLM, 'SOFTWARE\WOW6432Node\Apple Inc.\Apple Mobile Device Support') or
    DirExists(ExpandConstant('{commonpf}\Common Files\Apple\Mobile Device Support')) or
    DirExists(ExpandConstant('{commonpf32}\Common Files\Apple\Mobile Device Support'));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if not AppleMobileDeviceSupportPresent() then
      MsgBox(
        'Apple Mobile Device Support was not detected.' #13#13
        'Relocate needs it to see an iPhone over USB. Install the Apple Devices app '
        'from the Microsoft Store (or iTunes from apple.com), then reconnect your iPhone.' #13#13
        'Relocate is installed and will still open — see Help > iPhone Setup Tutorial.',
        mbInformation, MB_OK);
  end;
end;
