#Requires -Version 5.1
<#
.SYNOPSIS
    Updates an existing Git repository to have InitGit setup (.gitignore, .gitattributes, LFS, merge driver, hooks).
.DESCRIPTION
    Run from a repo root or pass a path. Validates .git exists, then generates .gitignore, .gitattributes,
    scripts (merge-theirs, setup-merge-driver, pre-push), runs git lfs install, and configures merge driver
    plus post-merge and pre-push hooks. Safe to run on repos already partially or fully set up.
.EXAMPLE
    .\updateRepo.ps1
    Updates the current directory (must be repo root or inside a repo).
.EXAMPLE
    .\updateRepo.ps1 C:\Projects\MyGame
    Updates the repo at the given path.
#>

$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath 'CloneAndInitLib.ps1')

# Logging: prefix and level for console output
function Write-InitGitLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Ok', 'Warn', 'Err')]
        [string]$Level = 'Info'
    )
    $ts = Get-Date -Format 'HH:mm:ss'
    $prefix = switch ($Level) {
        'Info'  { "[$ts] [InitGit] " }
        'Ok'    { "[$ts] [InitGit] OK: " }
        'Warn'  { "[$ts] [InitGit] WARN: " }
        'Err'   { "[$ts] [InitGit] ERROR: " }
    }
    $color = switch ($Level) {
        'Ok'    { 'Green' }
        'Warn'  { 'Yellow' }
        'Err'   { 'Red' }
        default { 'White' }
    }
    Write-Host $prefix$Message -ForegroundColor $color
}

function Get-GitRepoRoot {
    param([string]$StartPath)
    $current = if ([System.IO.Directory]::Exists($StartPath)) { (Resolve-Path -LiteralPath $StartPath).Path } else { (Get-Location).Path }
    $dir = $current
    while ($dir) {
        $gitDir = Join-Path -Path $dir -ChildPath '.git'
        if (Test-Path -LiteralPath $gitDir -PathType Container) {
            return $dir
        }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

try {
    $targetPath = if ($args.Length -gt 0) { $args[0].Trim('"') } else { (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        Write-InitGitLog "Path is not a directory: $targetPath" -Level Err
        pause
        exit 1
    }

    Write-InitGitLog "Update repo to InitGit" -Level Info
    Write-InitGitLog "Target: $targetPath" -Level Info

    $repoRoot = Get-GitRepoRoot -StartPath $targetPath
    if (-not $repoRoot) {
        Write-InitGitLog "No Git repository found at or above: $targetPath" -Level Err
        pause
        exit 1
    }
    Write-InitGitLog "Repository root: $repoRoot" -Level Ok

    Push-Location -LiteralPath $repoRoot
    try {
        # .gitignore
        $gitignorePath = Join-Path -Path $repoRoot -ChildPath '.gitignore'
        Set-Content -LiteralPath $gitignorePath -Value $GitignoreContent -Encoding UTF8
        Write-InitGitLog "Generated: .gitignore" -Level Ok

        # .gitattributes
        $gitattributesPath = Join-Path -Path $repoRoot -ChildPath '.gitattributes'
        Set-Content -LiteralPath $gitattributesPath -Value $GitattributesContent -Encoding UTF8
        Write-InitGitLog "Generated: .gitattributes" -Level Ok

        # scripts folder
        $scriptsDir = Join-Path -Path $repoRoot -ChildPath 'scripts'
        $hooksDir = Join-Path -Path $scriptsDir -ChildPath 'hooks'
        New-Item -Path $scriptsDir -ItemType Directory -Force | Out-Null
        New-Item -Path $hooksDir -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $scriptsDir 'merge-theirs.bat') -Value $MergeTheirsBatContent -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $scriptsDir 'setup-merge-driver.bat') -Value $SetupMergeDriverBatContent -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $hooksDir 'pre-push') -Value $PrePushHookContent -Encoding ASCII -NoNewline:$false
        Write-InitGitLog "Generated: scripts\merge-theirs.bat, setup-merge-driver.bat, hooks\pre-push" -Level Ok

        Set-InitGitLocalHttpVersion | Out-Null

        $lfs = Install-InitGitGitLfsInRepo
        if ($lfs.Ok) {
            Write-InitGitLog $lfs.Message -Level Ok
        } else {
            Write-InitGitLog $lfs.Message -Level Warn
        }

        # Merge driver
        git config merge.theirs.driver "scripts/merge-theirs.bat"
        if ($LASTEXITCODE -eq 0) {
            Write-InitGitLog "Configured merge driver 'theirs'" -Level Ok
        } else {
            Write-InitGitLog "Failed to set merge driver" -Level Warn
        }

        if (Install-InitGitRepoHooks -RepoRoot $repoRoot) {
            Write-InitGitLog "Hooks: .git/hooks/post-merge, .git/hooks/pre-push" -Level Ok
        } else {
            Write-InitGitLog "Could not install hooks (scripts\hooks\pre-push missing)" -Level Warn
        }

        Write-InitGitLog "Done. Repo updated: $repoRoot" -Level Ok
    } finally {
        Pop-Location
    }
    pause
} catch {
    Write-InitGitLog $_.Exception.Message -Level Err
    Write-InitGitLog $_.ScriptStackTrace -Level Err
    pause
    exit 1
}
