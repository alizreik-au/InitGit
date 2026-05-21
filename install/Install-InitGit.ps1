#Requires -Version 5.1
<#
.SYNOPSIS
    Installs or updates InitGit (init + clone-and-init) to the user's AppData\Local\InitGit.
.DESCRIPTION
    Copies scripts and docs so that cloneAndInit can run from the install folder and deploy
    into cloned repos. Optionally adds a context menu "Clone and init repo" on folders.
#>

$ErrorActionPreference = 'Stop'
$script:SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:ScriptsSourceDir = Join-Path -Path $SourceRoot -ChildPath 'src'
$InstallDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'InitGit'

# What to copy: main scripts + scripts folder + docs folder
$CopyMap = @(
    @{ Src = 'initGit.ps1'; Dest = 'initGit.ps1' },
    @{ Src = 'initGit.bat'; Dest = 'initGit.bat' },
    @{ Src = 'cloneAndInit.ps1'; Dest = 'cloneAndInit.ps1' },
    @{ Src = 'cloneAndInit.bat'; Dest = 'cloneAndInit.bat' },
    @{ Src = 'updateRepo.ps1'; Dest = 'updateRepo.ps1' },
    @{ Src = 'updateRepo.bat'; Dest = 'updateRepo.bat' },
    @{ Src = 'reInitRepo.ps1'; Dest = 'reInitRepo.ps1' },
    @{ Src = 'reInitRepo.bat'; Dest = 'reInitRepo.bat' },
    @{ Src = 'CloneAndInitLib.ps1'; Dest = 'CloneAndInitLib.ps1' },
    @{ Src = 'RepoPickerLib.ps1'; Dest = 'RepoPickerLib.ps1' }
)

Write-Host "InitGit Installer" -ForegroundColor Cyan
Write-Host "=================" -ForegroundColor Cyan
Write-Host "Install/update to: $InstallDir" -ForegroundColor White
Write-Host ""

. (Join-Path -Path $PSScriptRoot -ChildPath 'InstallDialogHelpers.ps1')

$prereqResultPath = Join-Path -Path $env:TEMP -ChildPath ("InitGit-prereq-" + [guid]::NewGuid().ToString('n') + '.json')
$checkScriptSource = Join-Path -Path $PSScriptRoot -ChildPath 'Check-InitGit-Prerequisites.ps1'
if (Test-Path -LiteralPath $checkScriptSource) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $checkScriptSource, '-ResultPath', $prereqResultPath
    ) -WindowStyle Hidden | Out-Null
    Write-Host "Started prerequisite check in the background..." -ForegroundColor Gray
} else {
    Write-Host "Check-InitGit-Prerequisites.ps1 not found; skipping background check." -ForegroundColor Yellow
}

if (-not (Test-Path -LiteralPath $ScriptsSourceDir -PathType Container)) {
    Write-Error "Source directory not found: $ScriptsSourceDir"
    exit 1
}

$preserveNames = @('UserData')
if (Test-Path -LiteralPath $InstallDir -PathType Container) {
    Write-Host "Updating existing installation: removing old files (preserving UserData)..." -ForegroundColor Gray
    Get-ChildItem -LiteralPath $InstallDir -Force |
        Where-Object { $preserveNames -notcontains $_.Name } |
        Remove-Item -Recurse -Force
    Write-Host "  Cleared install files under: $InstallDir" -ForegroundColor Green
} else {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
    Write-Host "Created: $InstallDir" -ForegroundColor Green
}

foreach ($entry in $CopyMap) {
    $src = Join-Path -Path $ScriptsSourceDir -ChildPath $entry.Src
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        $dest = Join-Path -Path $InstallDir -ChildPath $entry.Dest
        Copy-Item -LiteralPath $src -Destination $dest -Force
        Write-Host "  Copied: $($entry.Dest)" -ForegroundColor Green
    } else {
        Write-Host "  Skipped (not found): $($entry.Src)" -ForegroundColor Yellow
    }
}

$installHelperSrc = Join-Path -Path $PSScriptRoot -ChildPath 'InstallDialogHelpers.ps1'
$checkSrc = Join-Path -Path $PSScriptRoot -ChildPath 'Check-InitGit-Prerequisites.ps1'
foreach ($pair in @(
        @{ Src = $installHelperSrc; Dest = 'InstallDialogHelpers.ps1' },
        @{ Src = $checkSrc; Dest = 'Check-InitGit-Prerequisites.ps1' }
    )) {
    if (Test-Path -LiteralPath $pair.Src -PathType Leaf) {
        Copy-Item -LiteralPath $pair.Src -Destination (Join-Path $InstallDir $pair.Dest) -Force
        Write-Host "  Copied: $($pair.Dest)" -ForegroundColor Green
    }
}

# Copy scripts and docs folders
$scriptsSrc = Join-Path -Path $SourceRoot -ChildPath 'scripts'
$docsSrc = Join-Path -Path $SourceRoot -ChildPath 'docs'
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

# Launcher: Update repo to InitGit from context menu (folder path = %1 or %V)
$batRunUpdateRepo = @"
@echo off
cd /d "%~dp0"
set "FOLDER=%~1"
if "%FOLDER%"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0updateRepo.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0updateRepo.ps1" "%FOLDER%"
)
if errorlevel 1 pause
"@
Set-Content -LiteralPath (Join-Path $InstallDir 'RunUpdateRepo.bat') -Value $batRunUpdateRepo -Encoding ASCII
Write-Host "  Created: RunUpdateRepo.bat" -ForegroundColor Green

# Launcher: Initialize copied folder that does not have .git yet
$batRunReInitRepo = @"
@echo off
cd /d "%~dp0"
set "FOLDER=%~1"
if "%FOLDER%"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0reInitRepo.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0reInitRepo.ps1" "%FOLDER%"
)
if errorlevel 1 pause
"@
Set-Content -LiteralPath (Join-Path $InstallDir 'RunReInitRepo.bat') -Value $batRunReInitRepo -Encoding ASCII
Write-Host "  Created: RunReInitRepo.bat" -ForegroundColor Green

# Add context menu .bat - merge the reg file (UAC)
$batAddContext = @"
@echo off
set "REGFILE=%LOCALAPPDATA%\InitGit\Add_InitGit_Context_Menu.reg"
if not exist "%REGFILE%" (
    echo Add_InitGit_Context_Menu.reg not found at %REGFILE%
    echo Run "Install InitGit.bat" from the repo root first to install and create the reg file.
    pause
    exit /b 1
)
echo Adding InitGit context menu entries (Clone and init repo, Update repo to InitGit, Init copied folder)...
echo You may be prompted for Administrator approval.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'reg.exe' -ArgumentList 'import', \"\"\"%REGFILE%\"\"\" -Verb RunAs -Wait"
if errorlevel 1 (
    echo Failed. Right-click Add_InitGit_Context_Menu.reg and choose Merge, then accept UAC.
    pause
    exit /b 1
)
echo Done.
echo On Windows 11: right-click a folder (or empty area), then "Show more options" to see "Clone and init repo", "Update repo to InitGit", and "Init copied folder".
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

; "Update repo to InitGit" - right-click a folder (repo root or inside repo) or background

[HKEY_CLASSES_ROOT\Folder\shell\InitGit_UpdateRepo]
@="Update repo to InitGit"
"Icon"="C:\\\\Windows\\\\System32\\\\WindowsPowerShell\\\\v1.0\\\\powershell.exe"

[HKEY_CLASSES_ROOT\Folder\shell\InitGit_UpdateRepo\command]
@="\"$regPath\\\\RunUpdateRepo.bat\" \"%1\""

[HKEY_CLASSES_ROOT\Directory\Background\shell\InitGit_UpdateRepo]
@="Update repo to InitGit"
"Icon"="C:\\\\Windows\\\\System32\\\\WindowsPowerShell\\\\v1.0\\\\powershell.exe"
"NoWorkingDirectory"=""

[HKEY_CLASSES_ROOT\Directory\Background\shell\InitGit_UpdateRepo\command]
@="\"$regPath\\\\RunUpdateRepo.bat\" \"%V\""

; "Init copied folder" - right-click a non-git folder or background

[HKEY_CLASSES_ROOT\Folder\shell\InitGit_ReInitRepo]
@="Init copied folder"
"Icon"="C:\\\\Windows\\\\System32\\\\WindowsPowerShell\\\\v1.0\\\\powershell.exe"

[HKEY_CLASSES_ROOT\Folder\shell\InitGit_ReInitRepo\command]
@="\"$regPath\\\\RunReInitRepo.bat\" \"%1\""

[HKEY_CLASSES_ROOT\Directory\Background\shell\InitGit_ReInitRepo]
@="Init copied folder"
"Icon"="C:\\\\Windows\\\\System32\\\\WindowsPowerShell\\\\v1.0\\\\powershell.exe"
"NoWorkingDirectory"=""

[HKEY_CLASSES_ROOT\Directory\Background\shell\InitGit_ReInitRepo\command]
@="\"$regPath\\\\RunReInitRepo.bat\" \"%V\""
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

# Wait for prerequisite JSON (written by parallel child)
$prereq = $null
$prereqTimedOut = $false
if (Test-Path -LiteralPath $checkScriptSource) {
    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $prereqResultPath) {
            try {
                $raw = Get-Content -LiteralPath $prereqResultPath -Raw -Encoding UTF8 -ErrorAction Stop
                $prereq = $raw | ConvertFrom-Json
                if ($null -ne $prereq.GitPresent) { break }
            } catch { }
        }
        Start-Sleep -Milliseconds 200
    }
    if ($null -eq $prereq -or $null -eq $prereq.GitPresent) {
        $prereqTimedOut = $true
        Write-Host "Prerequisite check did not finish within 120 seconds." -ForegroundColor Yellow
        Show-InitGitInstallerMessage -Message @"
Could not verify Git, Git LFS, or Git Credential Manager in time.

Install Git from https://git-scm.com/download/win if clone or init fails. You can run this installer again to retry winget installs.
"@
    }
}

$checkScriptInstalled = Join-Path -Path $InstallDir -ChildPath 'Check-InitGit-Prerequisites.ps1'

$wingetOk = $false
try {
    & winget.exe --version 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $wingetOk = $true }
} catch { }

$missing = @()
if ($prereqTimedOut -and -not $prereq) {
    $missing += 'Could not verify Git or Git LFS (check timed out).'
} elseif ($prereq) {
    if (-not $prereq.GitPresent) { $missing += 'Git is missing or not on PATH.' }
    if (-not $prereq.LfsPresent) { $missing += 'Git LFS is missing.' }
    if (-not $prereq.GcmPresent) { $missing += 'Git Credential Manager was not detected.' }
    foreach ($m in $prereq.Messages) { if ($m) { $missing += [string]$m } }
}
$missing = @($missing | Select-Object -Unique)

if ($missing.Count -gt 0) {
    $doInstall = Show-InitGitPrerequisitesInstallDialog -MissingLines $missing -WingetAvailable:$wingetOk
    if ($doInstall -and $wingetOk) {
        $needGit = if ($prereq) { -not $prereq.GitPresent } else { $true }
        $needLfs = if ($prereq) { -not $prereq.LfsPresent } else { $true }
        $needGcm = if ($prereq) { -not $prereq.GcmPresent } else { $false }

        if ($needGit) {
            $wingetResult = Invoke-InitGitWingetInstallMissing -NeedGit $true -NeedLfs $false -NeedGcm $false
            Update-InitGitSessionPathFromMachine
            $prereq = Invoke-InitGitRunPrerequisiteCheck -CheckScriptPath $checkScriptInstalled
            if (-not $wingetResult.Success) {
                Write-Host "winget Git install exited with code $($wingetResult.ExitCode) (cancelled or failed)." -ForegroundColor Yellow
            }
            if ($prereq -and $prereq.GcmPresent) { $needGcm = $false }
            $needLfs = if ($prereq) { -not $prereq.LfsPresent } else { $needLfs }
            $needGcm = if ($prereq) { -not $prereq.GcmPresent } else { $needGcm }
        }

        if ($needLfs -or $needGcm) {
            $wingetResult = Invoke-InitGitWingetInstallMissing -NeedGit $false -NeedLfs:$needLfs -NeedGcm:$needGcm
            Update-InitGitSessionPathFromMachine
            $prereq = Invoke-InitGitRunPrerequisiteCheck -CheckScriptPath $checkScriptInstalled
            if (-not $wingetResult.Success) {
                Write-Host "winget install exited with code $($wingetResult.ExitCode) (cancelled or failed)." -ForegroundColor Yellow
            }
        }

        Write-Host "winget installs finished (or were cancelled). If tools are still missing, open a new PowerShell window and run this installer again." -ForegroundColor Yellow
    } elseif (-not $wingetOk) {
        Show-InitGitInstallerMessage -Message ("Missing: `n- " + ($missing -join "`n- ") + "`n`nInstall Git from https://git-scm.com/download/win and Git LFS from https://git-lfs.com when ready.")
    }
}

if (Test-Path -LiteralPath $prereqResultPath) {
    Remove-Item -LiteralPath $prereqResultPath -Force -ErrorAction SilentlyContinue
}

if (Show-InitGitContextMenuRegDialog) {
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
Write-Host "  - Init copied folder with no git: reInitRepo.bat or right-click folder -> Init copied folder" -ForegroundColor Gray
Write-Host "  - Init existing folder: initGit.bat (run from that folder)" -ForegroundColor Gray
Write-Host "  - Update existing repo to InitGit: updateRepo.bat or right-click folder -> Update repo to InitGit" -ForegroundColor Gray
Write-Host "  - Re-add context menu: Add-InitGit-Context-Menu.bat" -ForegroundColor Gray
Write-Host ""
Write-Host "Windows 11: The entry appears under 'Show more options' when you right-click a folder." -ForegroundColor Yellow
Write-Host "Repo picker: use a GitHub or Azure DevOps PAT with repo/code read scope to list remotes." -ForegroundColor Gray
Write-Host ""
