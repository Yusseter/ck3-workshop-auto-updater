#ifndef AppVersion
    #define AppVersion "0.0.0-dev"
#endif

#define AppName "CK3 Workshop Auto Updater"
#define AppPublisher "Yusseter"
#define AppURL "https://github.com/Yusseter/ck3-workshop-auto-updater"

#ifdef DiagnosticNoVbs
    #define OutputSuffix "-no-compression-no-startup-no-vbs-test"
#else
    #ifdef DiagnosticNoCompression
        #ifdef DiagnosticNoStartup
            #define OutputSuffix "-no-compression-no-startup-test"
        #else
            #define OutputSuffix "-no-compression-test"
        #endif
    #else
        #ifdef DiagnosticNoStartup
            #define OutputSuffix "-no-startup-test"
        #else
            #define OutputSuffix ""
        #endif
    #endif
#endif

#ifdef DiagnosticNoCompression
    #define CompressionMode "none"
    #define SolidCompressionMode "no"
#else
    #define CompressionMode "lzma2"
    #define SolidCompressionMode "yes"
#endif

[Setup]
AppId={{D4D0B2D0-2A77-4A50-A239-55436F57B7D7}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={localappdata}\CK3WorkshopAutoUpdater
DefaultGroupName={#AppName}
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=CK3WorkshopAutoUpdater-Setup-v{#AppVersion}{#OutputSuffix}
Compression={#CompressionMode}
SolidCompression={#SolidCompressionMode}
WizardStyle=modern
CloseApplications=no
RestartApplications=no
UninstallDisplayName={#AppName}

[Files]
Source: "..\src\CK3WorkshopAutoUpdater.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\config.json"; DestDir: "{app}"; Flags: onlyifdoesntexist
#ifndef DiagnosticNoVbs
Source: "RunHidden.vbs"; DestDir: "{app}"; Flags: ignoreversion
#endif

[Dirs]
Name: "{app}\data"

[Icons]
#ifndef DiagnosticNoStartup
#ifndef DiagnosticNoVbs
Name: "{userstartup}\CK3 Workshop Auto Updater"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\RunHidden.vbs"""; WorkingDir: "{app}"; Comment: "Checks CK3 Workshop items at Windows sign-in"
#endif
#endif
#ifndef DiagnosticNoVbs
Name: "{group}\Run Now"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\RunHidden.vbs"""; WorkingDir: "{app}"
#endif
Name: "{group}\Open Logs"; Filename: "{sys}\explorer.exe"; Parameters: """{app}\data"""
Name: "{group}\Uninstall"; Filename: "{uninstallexe}"

[InstallDelete]
Type: files; Name: "{userstartup}\CK3 Workshop Auto Updater.lnk.disabled"

[UninstallDelete]
Type: files; Name: "{userstartup}\CK3 Workshop Auto Updater.lnk.disabled"
Type: files; Name: "{app}\config.json"
Type: filesandordirs; Name: "{app}\data"
Type: dirifempty; Name: "{app}"
[Code]
procedure CopyLegacyFile(const FileName: String);
var
  SourcePath: String;
  DestinationPath: String;
begin
  SourcePath :=
    ExpandConstant('{userdocs}\CK3WorkshopAutoUpdater\') +
    FileName;

  DestinationPath :=
    ExpandConstant('{app}\data\') +
    FileName;

  if FileExists(SourcePath) and
     not FileExists(DestinationPath) then
  begin
    FileCopy(SourcePath, DestinationPath, False);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    ForceDirectories(ExpandConstant('{app}\data'));

    CopyLegacyFile('State.json');
    CopyLegacyFile('History.log');
    CopyLegacyFile('LastRun.log');
  end;
end;
