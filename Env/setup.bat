@echo off
REM Launch the PowerShell script with a bypassed execution policy
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0\setup.ps1"
pause
