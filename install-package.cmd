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

rem Explorer drop-target: pass each path as a named -Package so powershell -File
rem does not drop positional arguments.
set "PSARGS="
:collect
if "%~1"=="" goto run
set PSARGS=%PSARGS% -Package "%~1"
shift
goto collect

:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-package.ps1" %PSARGS%
set EXITCODE=%ERRORLEVEL%
echo.
echo Exit %EXITCODE%
pause
exit /b %EXITCODE%
