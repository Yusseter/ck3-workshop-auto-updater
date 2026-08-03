@echo off
setlocal

set "DATA=%LOCALAPPDATA%\CK3WorkshopAutoUpdater\data"

if not exist "%DATA%" (
    echo The data folder does not exist yet.
    echo Run Install.cmd first.
    pause
    exit /b 1
)

start "" explorer.exe "%DATA%"
