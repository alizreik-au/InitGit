#Requires -Version 5.1
<#
.SYNOPSIS
    Initializes an existing folder as a Git repo and applies the InitGit setup.
.DESCRIPTION
    Run from a copied project folder that has no .git directory yet. The script creates the repository,
    writes the standard .gitignore and .gitattributes files, generates the shared scripts/hooks, and
    configures Git LFS plus the merge driver.
#>

$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath 'CloneAndInitLib.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'RepoPickerLib.ps1')

try {
    $targetPath = if ($args.Length -gt 0) { $args[0].Trim('"') } else { (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        Write-Host "Path is not a directory: $targetPath" -ForegroundColor Red
        pause
        exit 1
    }

    $repoRoot = (Resolve-Path -LiteralPath $targetPath).Path
    $gitDir = Join-Path -Path $repoRoot -ChildPath '.git'

    if (Test-Path -LiteralPath $gitDir -PathType Container) {
        Write-Host "This folder already has a Git repository: $repoRoot" -ForegroundColor Yellow
        Write-Host "Use updateRepo.ps1 instead." -ForegroundColor Yellow
        pause
        exit 1
    }

    Write-Host "Initialize existing folder as InitGit repository" -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "Target: $repoRoot"
    Write-Host ""

    do {
        $url = if ($args.Length -gt 1) { $args[1] } else { $null }
        if ([string]::IsNullOrWhiteSpace($url)) {
            $url = Get-RepositoryUrlFromDialog -DefaultUrl $url -DialogTitle 'Init copied folder - Repository URL'
        }
        if ([string]::IsNullOrWhiteSpace($url)) {
            if (-not (Show-InitGitYesNoMessage -Message 'No repository URL was entered. Try again?' -Title 'Init copied folder')) {
                Write-Host "Exiting." -ForegroundColor Yellow
                pause
                exit 1
            }
        }
    } while ([string]::IsNullOrWhiteSpace($url))
    $url = $url.Trim()

    Push-Location -LiteralPath $repoRoot
    try {
        Write-Host "Initializing Git repository..."
        git init
        if ($LASTEXITCODE -ne 0) {
            Write-Host "git init failed." -ForegroundColor Red
            pause
            exit 1
        }

        Set-Content -LiteralPath (Join-Path -Path $repoRoot -ChildPath '.gitignore') -Value $GitignoreContent -Encoding UTF8
        Write-Host "  Generated: .gitignore" -ForegroundColor Green

        Set-Content -LiteralPath (Join-Path -Path $repoRoot -ChildPath '.gitattributes') -Value $GitattributesContent -Encoding UTF8
        Write-Host "  Generated: .gitattributes" -ForegroundColor Green

        & git remote add origin -- $url
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Linked remote origin: $url" -ForegroundColor Green
        } else {
            Write-Host "  Warning: failed to add remote origin." -ForegroundColor Yellow
        }

        $scriptsDir = Join-Path -Path $repoRoot -ChildPath 'scripts'
        $hooksDir = Join-Path -Path $scriptsDir -ChildPath 'hooks'
        New-Item -Path $scriptsDir -ItemType Directory -Force | Out-Null
        New-Item -Path $hooksDir -ItemType Directory -Force | Out-Null

        Set-Content -LiteralPath (Join-Path -Path $scriptsDir -ChildPath 'merge-theirs.bat') -Value $MergeTheirsBatContent -Encoding ASCII
        Set-Content -LiteralPath (Join-Path -Path $scriptsDir -ChildPath 'setup-merge-driver.bat') -Value $SetupMergeDriverBatContent -Encoding ASCII
        Set-Content -LiteralPath (Join-Path -Path $hooksDir -ChildPath 'pre-push') -Value $PrePushHookContent -Encoding ASCII -NoNewline:$false
        Write-Host "  Generated: scripts\merge-theirs.bat, scripts\setup-merge-driver.bat, scripts\hooks\pre-push" -ForegroundColor Green

        git lfs install
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Warning: git lfs install failed. LFS may not be active." -ForegroundColor Yellow
        }

        git config merge.theirs.driver "scripts/merge-theirs.bat"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Configured: merge driver 'theirs'" -ForegroundColor Green
        } else {
            Write-Host "  Warning: failed to set merge driver." -ForegroundColor Yellow
        }

        $postMergeHook = Join-Path -Path $gitDir -ChildPath 'hooks\post-merge'
        $prePushHook = Join-Path -Path $gitDir -ChildPath 'hooks\pre-push'
        $postMergeContent = "#!/bin/sh`ngit lfs pull"
        Set-Content -LiteralPath $postMergeHook -Value $postMergeContent -Encoding ASCII -NoNewline:$false
        Copy-Item -LiteralPath (Join-Path -Path $hooksDir -ChildPath 'pre-push') -Destination $prePushHook -Force
        Write-Host "  Generated: .git/hooks/post-merge, .git/hooks/pre-push" -ForegroundColor Green

        Write-Host ""
        Write-Host "Done. Repo initialized: $repoRoot" -ForegroundColor Green
    } finally {
        Pop-Location
    }
    pause
} catch {
    Write-Host "An error occurred:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    pause
    exit 1
}
