@echo off
setlocal
title CK3 Workshop Auto Updater - Uninstall

set "POWERSHELL_EXE="

for /f "delims=" %%I in ('where pwsh.exe 2^>nul') do if not defined POWERSHELL_EXE set "POWERSHELL_EXE=%%I"

if not defined POWERSHELL_EXE if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "POWERSHELL_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined POWERSHELL_EXE if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not defined POWERSHELL_EXE (
    echo Neither PowerShell 7 nor Windows PowerShell 5.1 was found.
    pause
    exit /b 1
)

echo PowerShell runtime: %POWERSHELL_EXE%
echo.

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
    echo Uninstallation failed with exit code %EXITCODE%.
)

pause
exit /b %EXITCODE%
