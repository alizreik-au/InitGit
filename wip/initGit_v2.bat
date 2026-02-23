@echo off

echo Script started.
pause

:input_loop
REM Check if the repository address argument is provided
if "%~1"=="" (
    echo No argument provided, creating input dialog...
    
    REM Use PowerShell to create an input dialog and capture the result
    for /f "usebackq delims=" %%I in (`powershell -Command "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.Interaction]::InputBox('Please enter the repository URL:', 'Repository URL', '')"`) do set "userInput=%%I"
    
    echo After input dialog.
    echo Raw userInput: "%userInput%"
    
    REM Check if input is empty (user clicked Cancel or closed the window)
    if "%userInput%"=="" (
        choice /C YN /M "No repository URL provided. Do you want to try again?"
        if errorlevel 2 (
            echo Exiting script.
            pause
            exit /b 1
        ) else (
            goto input_loop
        )
    )
) else (
    REM Capture the repository address from the first argument
    set "userInput=%~1"
)

echo Repository URL: "%userInput%"
pause

REM ... rest of the script continues ...


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

echo Initializing Git LFS...
git lfs init

echo Configuring LFS lock verification...
git config lfs.%userInput%.git/info/lfs.locksverify true

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
