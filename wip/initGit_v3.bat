@echo off
set "current_dir=%cd%"
powershell.exe -ExecutionPolicy Bypass -File "%~dp0initGit.ps1" "%current_dir%"