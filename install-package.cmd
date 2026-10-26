@echo off
setlocal
cd /d "%~dp0"

if "%~1"=="" (
    echo Drop a .hap / .app / .hsp ^(or a folder of them^) onto this file.
    echo Or: install-package.cmd "D:\path\to\app.hap"
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-package.ps1" %*
set EXITCODE=%ERRORLEVEL%
echo.
echo Exit %EXITCODE%
pause
exit /b %EXITCODE%
