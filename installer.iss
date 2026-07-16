; RemoteSupport Installer Script (Inno Setup)
; Derlemek icin: Inno Setup Compiler ile bu dosyayi acip "Compile" deyin,
; ya da komut satirindan: iscc installer.iss

#define MyAppName "RemoteSupport"
#define MyAppVersion "1.0"
#define MyAppExeName "RemoteSupport.exe"
#define MyBuildDir "C:\Users\onur_\rustdesk\flutter\build\windows\x64\runner\Release"

[Setup]
AppId={{A1B2C3D4-1234-5678-9ABC-REMOTESUPPORT}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=C:\Users\onur_\Desktop
OutputBaseFilename=RemoteSupportSetup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Files]
; Build klasorundeki HER SEYI (exe + tum dll'ler) kopyala
Source: "{#MyBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[Run]
; Servisi kur ve baslat - RustDesk'in kendi --install-service komutunu kullaniyoruz
Filename: "{app}\{#MyAppExeName}"; Parameters: "--install-service"; Flags: runhidden waituntilterminated
; Kurulum bitince uygulamayi ac (opsiyonel, istenmezse bu satiri silin)
Filename: "{app}\{#MyAppExeName}"; Description: "RemoteSupport'u baslat"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{app}\{#MyAppExeName}"; Parameters: "--uninstall-service"; Flags: runhidden waituntilterminated
