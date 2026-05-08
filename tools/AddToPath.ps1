# Check if running with admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "*** This script requires administrative privileges. ***"
    Write-Host "*** Please run it as an administrator. ***"
    pause
    exit
}
# Get the directory where the script is located
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$sourceScriptsDir = Join-Path $repoRoot "src"
Write-Host "Script directory: $scriptDir"

$batFile = Join-Path $env:SystemRoot "System32\initGit.bat"
Write-Host "Checking for initGit.bat at path: $batFile"

$sourceBatFile = Join-Path $sourceScriptsDir "initGit.bat"
$destBatFile = Join-Path $env:SystemRoot "System32\initGit.bat"

Write-Host "Source bat file path: $sourceBatFile"
Write-Host "Destination bat file path: $destBatFile"

# Remove existing file if present
if (Test-Path $batFile) {
    Write-Host "Found existing initGit.bat in System32, attempting to remove..."
    try {
        Remove-Item -Path $batFile -Force -ErrorAction Stop
        Write-Host "Successfully removed initGit.bat from System32"
    }
    catch {
        Write-Host "Error occurred while removing existing file: $_"
        exit
    }
}

# Copy new file
Write-Host "Copying initGit.bat to System32..."
if (Test-Path $sourceBatFile) {
    try {
        Copy-Item -Path $sourceBatFile -Destination $destBatFile -Force -ErrorAction Stop
        Write-Host "Successfully copied initGit.bat to System32"
    }
    catch {
        Write-Host "Error occurred while copying file: $_"
        exit
    }
} else {
    Write-Host "Error: Source initGit.bat not found at $sourceBatFile"
}

# Verify the file was copied successfully
if (Test-Path $destBatFile) {
    Write-Host "Verified: initGit.bat is present in System32"
} else {
    Write-Host "Error: Failed to copy initGit.bat to System32"
}

# Get the directory where the script is located
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Set source and destination paths
$sourceFile = Join-Path $sourceScriptsDir "initGit.ps1"
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
    Write-Host "initGit.ps1 not found in $sourceScriptsDir"
}

Write-Host "Finished!"
Start-Sleep -Seconds 3
