@echo off
REM Run after every merge so LFS pointer files are replaced with real binaries.
git lfs pull
exit /b 0
