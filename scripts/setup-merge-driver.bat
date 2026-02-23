@echo off
REM One-time setup after clone: configures the "theirs" merge driver and post-merge LFS pull.
REM Run from repo root: scripts\setup-merge-driver.bat

set DRIVER_CMD=scripts/merge-theirs.bat
git config merge.theirs.driver "%DRIVER_CMD%"
if %ERRORLEVEL% neq 0 (
  echo Failed to set merge driver.
  exit /b 1
)
echo Merge driver "theirs" configured. .uasset conflicts will keep the incoming branch version.

REM Ensure post-merge hook runs "git lfs pull" so pointer files become real binaries after merge.
set HOOK=.git\hooks\post-merge
if not exist "%HOOK%" (
  echo #!/bin/sh > "%HOOK%"
  echo git lfs pull >> "%HOOK%"
  echo Post-merge hook created: will run "git lfs pull" after every merge.
) else (
  findstr /C:"git lfs pull" "%HOOK%" >nul 2>&1
  if %ERRORLEVEL% neq 0 (
    echo. >> "%HOOK%"
    echo git lfs pull >> "%HOOK%"
    echo Post-merge hook updated: will run "git lfs pull" after every merge.
  ) else (
    echo Post-merge hook already runs "git lfs pull".
  )
)

REM Ensure pre-push hook runs "git lfs push REMOTE --all" so LFS objects are always uploaded when pushing.
set PREPUSH=.git\hooks\pre-push
findstr /C:"git lfs push" "%PREPUSH%" >nul 2>&1
if %ERRORLEVEL% neq 0 (
  if exist "%PREPUSH%" copy /Y "%PREPUSH%" ".git\hooks\pre-push.lfs" >nul
  copy /Y "scripts\hooks\pre-push" "%PREPUSH%" >nul
  echo Pre-push hook installed: will run "git lfs push REMOTE --all" before every push.
) else (
  echo Pre-push hook already runs "git lfs push".
)
