@echo off
setlocal
title CK3 Workshop Auto Updater - Build Release

set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%POWERSHELL_EXE%" (
    echo Windows PowerShell 5.1 was not found.
    pause
    exit /b 1
)

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Build-Release.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
    echo Release build failed with exit code %EXITCODE%.
)

pause
exit /b %EXITCODE%
