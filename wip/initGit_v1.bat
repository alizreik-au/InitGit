@echo off
REM Check if the repository address argument is provided
if "%~1"=="" (
    echo No repository URL provided. Exiting script.
    exit /b 1
)

REM Capture the repository address from the first argument
set "userInput=%~1"

echo Initializing Git repository...
git init

echo Adding Git remote...
git remote add origin %userInput%

REM Configure HTTP 1.1
echo Configuring Git for HTTP/1.1...
git config --local http.version HTTP/1.1

REM Install LFS into repo
echo Installing Git LFS...
git lfs install

echo Tracking files with Git LFS...
git lfs track "content/**"
git lfs track "import/**"
git lfs track "plugin/**"
git lfs track "*.fbx"

REM Define the name of the .gitignore file
set gitignoreFile=.gitignore

REM Create or overwrite the .gitignore file with the specified entries
(
echo Binaries
echo DerivedDataCache
echo Intermediate
echo Saved
echo .vscode
echo .vs
echo *.VC.db
echo *.opensdf
echo *.opendb
echo *.sdf
echo *.sln
echo *.suo
echo *.xcodeproj
echo *.xcworkspace
) > %gitignoreFile%

REM Verify the file creation
if exist %gitignoreFile% (
    echo .gitignore file has been created successfully.
) else (
    echo Failed to create .gitignore file.
)

echo Script completed.
pause
