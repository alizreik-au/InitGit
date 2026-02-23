@echo off
REM Run Pester tests with ExecutionPolicy Bypass so unsigned scripts load.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path 'tests' -PassThru"
if errorlevel 1 pause
