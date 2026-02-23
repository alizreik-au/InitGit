#Requires -Version 5.1
<#
.SYNOPSIS
    Installs or updates InitGit (init + clone-and-init) to the user's AppData\Local\InitGit.
.DESCRIPTION
    Copies scripts and docs so that cloneAndInit can run from the install folder and deploy
    into cloned repos. Optionally adds a context menu "Clone and init repo" on folders.
#>

$ErrorActionPreference = 'Stop'
$script:SourceDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$InstallDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'InitGit'

# What to copy: main scripts + scripts folder + docs folder
$CopyMap = @(
    @{ Src = 'initGit.ps1'; Dest = 'initGit.ps1' },
    @{ Src = 'initGit.bat'; Dest = 'initGit.bat' },
    @{ Src = 'cloneAndInit.ps1'; Dest = 'cloneAndInit.ps1' },
    @{ Src = 'cloneAndInit.bat'; Dest = 'cloneAndInit.bat' },
    @{ Src = 'CloneAndInitLib.ps1'; Dest = 'CloneAndInitLib.ps1' }
)

Write-Host "InitGit Installer" -ForegroundColor Cyan
Write-Host "=================" -ForegroundColor Cyan
Write-Host "Install/update to: $InstallDir" -ForegroundColor White
Write-Host ""

if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
    Write-Error "Source directory not found: $SourceDir"
    exit 1
}

if (Test-Path -LiteralPath $InstallDir -PathType Container) {
    Write-Host "Updating existing installation: removing old files..." -ForegroundColor Gray
    Get-ChildItem -LiteralPath $InstallDir -Force | Remove-Item -Recurse -Force
    Write-Host "  Cleared: $InstallDir" -ForegroundColor Green
} else {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
    Write-Host "Created: $InstallDir" -ForegroundColor Green
}

foreach ($entry in $CopyMap) {
    $src = Join-Path -Path $SourceDir -ChildPath $entry.Src
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        $dest = Join-Path -Path $InstallDir -ChildPath $entry.Dest
        Copy-Item -LiteralPath $src -Destination $dest -Force
        Write-Host "  Copied: $($entry.Dest)" -ForegroundColor Green
    } else {
        Write-Host "  Skipped (not found): $($entry.Src)" -ForegroundColor Yellow
    }
}

# Copy scripts and docs folders
$scriptsSrc = Join-Path -Path $SourceDir -ChildPath 'scripts'
$docsSrc = Join-Path -Path $SourceDir -ChildPath 'docs'
$scriptsDest = Join-Path -Path $InstallDir -ChildPath 'scripts'
$docsDest = Join-Path -Path $InstallDir -ChildPath 'docs'

if (Test-Path -LiteralPath $scriptsSrc -PathType Container) {
    New-Item -Path $scriptsDest -ItemType Directory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $scriptsSrc '*') -Destination $scriptsDest -Recurse -Force
    Write-Host "  Copied: scripts\" -ForegroundColor Green
}
if (Test-Path -LiteralPath $docsSrc -PathType Container) {
    New-Item -Path $docsDest -ItemType Directory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $docsSrc '*') -Destination $docsDest -Recurse -Force
    Write-Host "  Copied: docs\" -ForegroundColor Green
}

# Launcher: Clone and init from context menu (folder path = %1 or %V)
$batRunCloneAndInit = @"
@echo off
cd /d "%~dp0"
set "FOLDER=%~1"
if "%FOLDER%"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cloneAndInit.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cloneAndInit.ps1" "%FOLDER%"
)
if errorlevel 1 pause
"@
Set-Content -LiteralPath (Join-Path $InstallDir 'RunCloneAndInit.bat') -Value $batRunCloneAndInit -Encoding ASCII
Write-Host "  Created: RunCloneAndInit.bat" -ForegroundColor Green

# Standalone run (no args) - same as above with no folder
$batRunMe = @"
@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cloneAndInit.ps1" %*
if errorlevel 1 pause
"@
Set-Content -LiteralPath (Join-Path $InstallDir 'RunMe.bat') -Value $batRunMe -Encoding ASCII
Write-Host "  Created: RunMe.bat (Clone and init - prompts for URL and folder)" -ForegroundColor Green

# Add context menu .bat - merge the reg file (UAC)
$batAddContext = @"
@echo off
set "REGFILE=%LOCALAPPDATA%\InitGit\Add_InitGit_Context_Menu.reg"
if not exist "%REGFILE%" (
    echo Add_InitGit_Context_Menu.reg not found at %REGFILE%
    echo Run Install-InitGit first to install and create the reg file.
    pause
    exit /b 1
)
echo Adding "Clone and init repo" to folder context menu...
echo You may be prompted for Administrator approval.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'reg.exe' -ArgumentList 'import', \"\"\"%REGFILE%\"\"\" -Verb RunAs -Wait"
if errorlevel 1 (
    echo Failed. Right-click Add_InitGit_Context_Menu.reg and choose Merge, then accept UAC.
    pause
    exit /b 1
)
echo Done.
echo On Windows 11: right-click a folder (or empty area), then "Show more options" to see "Clone and init repo".
pause
"@
Set-Content -LiteralPath (Join-Path $InstallDir 'Add-InitGit-Context-Menu.bat') -Value $batAddContext -Encoding ASCII
Write-Host "  Created: Add-InitGit-Context-Menu.bat" -ForegroundColor Green

# .reg with install path (double backslashes for .reg)
$regPath = $InstallDir -replace '\\', '\\\\'
$regContent = @"
Windows Registry Editor Version 5.00

; Ensure double-click on folder opens it (default verb = open); our entry is extra context menu only.
[HKEY_CLASSES_ROOT\Folder\shell]
@="open"

; "Clone and init repo" - right-click a folder or background inside a folder (Show more options on Win11)

[HKEY_CLASSES_ROOT\Folder\shell\InitGit_CloneAndInit]
@="Clone and init repo"
"Icon"="C:\\\\Windows\\\\System32\\\\WindowsPowerShell\\\\v1.0\\\\powershell.exe"

[HKEY_CLASSES_ROOT\Folder\shell\InitGit_CloneAndInit\command]
@="\"$regPath\\\\RunCloneAndInit.bat\" \"%1\""

[HKEY_CLASSES_ROOT\Directory\Background\shell\InitGit_CloneAndInit]
@="Clone and init repo"
"Icon"="C:\\\\Windows\\\\System32\\\\WindowsPowerShell\\\\v1.0\\\\powershell.exe"
"NoWorkingDirectory"=""

[HKEY_CLASSES_ROOT\Directory\Background\shell\InitGit_CloneAndInit\command]
@="\"$regPath\\\\RunCloneAndInit.bat\" \"%V\""
"@
$regFile = Join-Path -Path $InstallDir -ChildPath 'Add_InitGit_Context_Menu.reg'
Set-Content -LiteralPath $regFile -Value $regContent -Encoding ASCII
Write-Host "  Created: Add_InitGit_Context_Menu.reg (points to $InstallDir)" -ForegroundColor Green

# Standalone fix: restore double-click = open folder (run this if clicking a folder ran the script instead of opening)
$fixFolderOpenReg = @"
Windows Registry Editor Version 5.00

; Restore default: double-click on a folder opens it (does not run InitGit).
[HKEY_CLASSES_ROOT\Folder\shell]
@="open"
"@
$fixFolderOpenFile = Join-Path -Path $InstallDir -ChildPath 'Fix-Folder-Open.reg'
Set-Content -LiteralPath $fixFolderOpenFile -Value $fixFolderOpenReg -Encoding ASCII
Write-Host "  Created: Fix-Folder-Open.reg (merge if double-click on folder runs script instead of opening)" -ForegroundColor Green

Write-Host ""
Write-Host "Installation complete." -ForegroundColor Green
Write-Host ""

$addContext = Read-Host "Add 'Clone and init repo' to folder right-click context menu? (Y/n)"
if ($addContext -ne 'n' -and $addContext -ne 'N') {
    try {
        $proc = Start-Process -FilePath 'reg.exe' -ArgumentList 'import', "`"$regFile`"" -Verb RunAs -Wait -PassThru
        if ($proc.ExitCode -eq 0) {
            Write-Host "Context menu added." -ForegroundColor Green
        } else {
            Write-Host "Reg merge may have been cancelled (UAC). Run Add-InitGit-Context-Menu.bat from the install folder." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Could not add context menu. Run Add-InitGit-Context-Menu.bat from: $InstallDir" -ForegroundColor Yellow
    }
} else {
    Write-Host "To add the context menu later, run Add-InitGit-Context-Menu.bat in the install folder." -ForegroundColor Gray
}

Write-Host ""
Write-Host "Installed location: $InstallDir" -ForegroundColor Cyan
Write-Host "  - Clone and init (prompt): RunMe.bat or RunCloneAndInit.bat" -ForegroundColor Gray
Write-Host "  - Init existing folder: initGit.bat (run from that folder)" -ForegroundColor Gray
Write-Host "  - Re-add context menu: Add-InitGit-Context-Menu.bat" -ForegroundColor Gray
Write-Host ""
Write-Host "Windows 11: The entry appears under 'Show more options' when you right-click a folder." -ForegroundColor Yellow
Write-Host ""
