# Check if running with admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "*** This script requires administrative privileges. ***"
    Write-Host "*** Please run it as an administrator. ***"
    pause
    exit
}

# Check if initGit.bat exists in System32 and remove it if found
$batFile = Join-Path $env:SystemRoot "System32\initGit.bat"
Write-Host "Checking for initGit.bat at path: $batFile"

if (Test-Path $batFile) {
    Write-Host "Found existing initGit.bat in System32, attempting to remove..."
    try {
        Remove-Item -Path $batFile -Force -ErrorAction Stop
        Write-Host "Successfully removed initGit.bat from System32"
        
        Write-Host "Copying initGit.bat to System32..."
        $sourceBatFile = Join-Path $scriptDir "initGit.bat"
        $destBatFile = Join-Path $env:SystemRoot "System32\initGit.bat"
        
        if (Test-Path $sourceBatFile) {
            Copy-Item -Path $sourceBatFile -Destination $destBatFile -Force -ErrorAction Stop
            Write-Host "Successfully copied initGit.bat to System32"
        } else {
            Write-Host "Warning: Source initGit.bat not found at $sourceBatFile"
        }
    }
    catch {
        Write-Host "Error occurred: $_"
        Write-Host "Are you running this as an administrator?"
        Write-Host "Check the System32 folder manually to ensure initGit.bat is removed."
        Write-Host "Press any key to end..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    }
} else {
    Write-Host "initGit.bat not found in System32, skipping removal step."
}


# Get the directory where the script is located
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Set source and destination paths
$sourceFile = Join-Path $scriptDir "initGit.ps1"
$destDir = $env:SystemRoot + "\System32"
$destFile = Join-Path $destDir "initGit.ps1"

# Copy the file to System32 directory
if (Test-Path $sourceFile) {
    Write-Host "Copying initGit.ps1 to $destDir..."
    try {
        Copy-Item -Path $sourceFile -Destination $destFile -Force
        Write-Host "initGit.ps1 successfully copied to $destDir."
    }
    catch {
        Write-Host "Failed to copy initGit.ps1: $_"
    }
}
else {
    Write-Host "initGit.ps1 not found in $scriptDir"
}

Write-Host "Finished!"
pause
Start-Sleep -Seconds 3