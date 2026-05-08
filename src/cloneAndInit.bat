@echo off
set "parent_dir=%~1"
set "repo_url=%~2"
cd /d "%~dp0"
if defined parent_dir (
    if defined repo_url (
        powershell.exe -ExecutionPolicy Bypass -File "%~dp0cloneAndInit.ps1" "%parent_dir%" "%repo_url%"
    ) else (
        powershell.exe -ExecutionPolicy Bypass -File "%~dp0cloneAndInit.ps1" "%parent_dir%"
    )
) else (
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0cloneAndInit.ps1"
)
if errorlevel 1 pause
