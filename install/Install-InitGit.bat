@echo off
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-InitGit.ps1"
if errorlevel 1 pause
