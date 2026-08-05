#ifndef AppVersion
    #define AppVersion "0.0.0-dev"
#endif

#define AppName "CK3 Workshop Auto Updater"
#define AppPublisher "Yusseter"
#define AppURL "https://github.com/Yusseter/ck3-workshop-auto-updater"

[Setup]
AppId={{9DF0C266-F13A-40F8-BED8-44FBD66E7846}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={tmp}\CK3WorkshopAutoUpdater-MinimalInnoTest
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=CK3WorkshopAutoUpdater-Setup-v{#AppVersion}-minimal-inno-test
Compression=none
SolidCompression=no
WizardStyle=modern
CloseApplications=no
RestartApplications=no
Uninstallable=no
CreateUninstallRegKey=no
