@echo off
setlocal
title CK3 Workshop Auto Updater - Install

where pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo PowerShell 7 ^(pwsh.exe^) is required.
    echo Install PowerShell 7, then run this installer again.
    pause
    exit /b 1
)

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
    echo Installation failed with exit code %EXITCODE%.
)

pause
exit /b %EXITCODE%
