@echo off
cd /d "%~dp0"
set "FOLDER=%~1"
if "%FOLDER%"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0updateRepo.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0updateRepo.ps1" "%FOLDER%"
)
if errorlevel 1 pause
