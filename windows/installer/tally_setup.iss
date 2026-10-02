; Installer Windows di Tally (Inno Setup) — M54, 2 ott 2026.
;
; Sostituisce lo zip (M37/M46) con un vero installer: aprire TallySetup.exe
; aggiorna un'installazione precedente in-place (stesso AppId sotto),
; invece di richiedere di estrarre a mano una cartella sopra l'altra.
;
; Il database locale (.sqlite) vive in getApplicationSupportDirectory()
; (v. resolveDatabaseFile() in app_database.dart), MAI dentro la cartella
; dell'app installata da questo script — installare/aggiornare qui non
; tocca mai i dati dell'utente.
;
; Compilato da .github/workflows/windows-build.yml con ISCC.exe (già
; preinstallato sui runner windows-latest di GitHub Actions, insieme a
; WiX e NSIS — nessun nuovo strumento necessario in CI). Per compilare in
; locale su un PC di sviluppo serve installare Inno Setup una tantum
; (gratuito, https://jrsoftware.org/isinfo.php, o `winget install
; JRSoftware.InnoSetup`) — non necessario per l'uso normale del progetto,
; la distribuzione reale passa sempre da CI.

#define MyAppName "Tally"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "Mario Costa"
#define MyAppExeName "finance_app.exe"

[Setup]
; NON CAMBIARE MAI QUESTO GUID: è la chiave con cui Inno Setup riconosce
; un'installazione precedente con lo stesso AppId e la aggiorna in-place
; (stessa voce in "App e funzionalità", versione sostituita) invece di
; crearne una seconda. Generato una sola volta per questo progetto.
AppId={{6DB2F943-9EB2-45A9-B496-66343194EEE3}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; Cartella utente, senza privilegi di amministratore — nessun UAC, stesso
; principio di app moderne come VS Code (PrivilegesRequired=lowest sotto).
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
; Flutter Windows produce solo binari a 64 bit.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist_installer
OutputBaseFilename=TallySetup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Intera cartella di output della build release Flutter, già portabile
; (stesso contenuto che prima finiva nello zip) — nessuna selezione manuale
; di DLL/asset, copiata così com'è.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
