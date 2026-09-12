@echo off
pushd "%~dp0" || exit /b 1
start "" /b powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "ToolLauncher.ps1"
popd
exit /b
