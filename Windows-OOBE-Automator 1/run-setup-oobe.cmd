@echo off
setlocal
set "scriptDir=%~dp0"
set "ps1=%scriptDir%setup-oobe.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%ps1%\"' -Verb RunAs"
endlocal
