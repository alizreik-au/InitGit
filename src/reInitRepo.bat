@echo off
setlocal
set "current_dir=%~dp0"
if "%~1"=="" (
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0reInitRepo.ps1"
) else (
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0reInitRepo.ps1" "%~1"
)
