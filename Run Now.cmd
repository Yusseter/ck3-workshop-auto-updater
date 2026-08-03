@echo off
setlocal

set "VBS=%LOCALAPPDATA%\CK3WorkshopAutoUpdater\RunHidden.vbs"

if not exist "%VBS%" (
    echo CK3 Workshop Auto Updater is not installed.
    echo Run Install.cmd first.
    pause
    exit /b 1
)

start "" "%SystemRoot%\System32\wscript.exe" "%VBS%"
echo The updater was started invisibly.
timeout /t 2 /nobreak >nul
