; ============================================================
; مثبّت Gaming Hall (Inno Setup 6) — واجهة عربية + أيقونة سطح مكتب
; قبل الـ Compile نفّذ:  flutter build windows --release
; الناتج: build\installer\GamingHall-Setup-1.0.0.exe
; ============================================================
#define MyAppName "Gaming Hall"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Gaming Hall"
#define MyAppExe "gaming_hall.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
; لا تغيّر هذا المعرّف أبدًا بعد أول نسخة تبيعها (يربط التحديثات بالنسخة المثبّتة)
AppId={{DCB2834F-7597-4603-903A-3B33095064E9}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\GamingHall
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=GamingHall-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; التطبيق يبقى شغّالًا بالخلفية (System Tray): نغلقه تلقائيًا عند التحديث/الإزالة
CloseApplications=yes
RestartApplications=no

[Languages]
; العربية إن كان ملفها موجودًا مع Inno Setup، وإلا تُترك الإنجليزية فقط (بدون خطأ)
#if FileExists(CompilerPath + "Languages\Arabic.isl")
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
#endif
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; أيقونة سطح المكتب: محدّدة افتراضيًا
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
