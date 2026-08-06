@echo off
REM Onboarding Finisher - double-click to apply per-user settings to the CURRENT account.
REM Run this AS THE USER ACCOUNT being handed to the end user. Do NOT run as administrator.
REM Keep Finish-Decrapifier.ps1 and mode.txt in this same folder.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Finish-Decrapifier.ps1"
