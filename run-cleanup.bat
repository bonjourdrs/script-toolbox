@echo off
setlocal EnableExtensions

rem Junk-cleanup launcher. Arguments are passed through to cleanup.ps1.
set "SCRIPT=%~dp0cleanup.ps1"
if not exist "%SCRIPT%" (
    echo [Error] cleanup.ps1 was not found beside this launcher.
    pause
    exit /b 2
)

rem RemoteSigned permits local scripts but avoids bypassing the downloaded-file policy.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo [Error] Cleanup ended with exit code %EXIT_CODE%.
)
pause
exit /b %EXIT_CODE%
