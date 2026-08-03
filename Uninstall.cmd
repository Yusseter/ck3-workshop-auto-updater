@echo off
setlocal
title CK3 Workshop Auto Updater - Uninstall

where pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo PowerShell 7 ^(pwsh.exe^) is required.
    pause
    exit /b 1
)

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
pause
exit /b %EXITCODE%
