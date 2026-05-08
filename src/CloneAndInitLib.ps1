#Requires -Version 5.1
<#
.SYNOPSIS
    Shared helpers and content for InitGit workflows.
.DESCRIPTION
    Get-RepoNameFromUrl returns the repository name from a Git URL.
    Content variables (GitignoreContent, GitattributesContent, etc.) are used when generating
    .gitignore, .gitattributes, and scripts in a repo.
#>

# Shared content: generated into repos so scripts stay self-contained (single source of truth)
$GitignoreContent = @"
Binaries
DerivedDataCache
Intermediate
Saved
.vscode
.vs
*.VC.db
*.opensdf
*.opendb
*.sdf
*.sln
*.suo
*.xcodeproj
*.xcworkspace
"@

$GitattributesContent = @"
content/** filter=lfs diff=lfs merge=lfs -text
import/** filter=lfs diff=lfs merge=lfs -text
plugin/** filter=lfs diff=lfs merge=lfs -text
*.fbx filter=lfs diff=lfs merge=lfs -text
*.uasset filter=lfs diff=lfs merge=lfs -text
"@

$MergeTheirsBatContent = @"
@echo off
REM Git merge driver: keep "theirs" (incoming) version. Args: %P %O %A %B -> copy %B to %A
REM /B = binary copy (required; default copy would treat as text and corrupt .uasset / LFS)
copy /B /Y "%~4" "%~3" >nul
exit /b 0
"@

$PrePushHookContent = @'
#!/bin/sh
# Push all LFS objects to the remote before the normal push (avoids "push succeeded but LFS didn't upload").
remote="$1"
git lfs push "$remote" --all || exit 1
# Run original LFS pre-push hook if it was preserved during setup
if [ -f .git/hooks/pre-push.lfs ]; then
  exec sh .git/hooks/pre-push.lfs "$@"
fi
exit 0
'@

$SetupMergeDriverBatContent = @"
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
"@

function Get-RepoNameFromUrl {
    [OutputType([string])]
    param(
        [string]$Url
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    # Strip query and fragment so repo name is path-safe
    $pathPart = ($Url -split '[?#]')[0].TrimEnd('/')
    $leaf = $pathPart -replace '.*/', ''
    $name = $leaf -replace '\.git$', ''
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    return $name
}

function ConvertTo-RemoteBranchInfo {
    [OutputType([object[]])]
    param(
        [string[]]$Lines
    )

    $branchInfo = @()
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $parts = $line -split '\|', 4
        if ($parts.Count -lt 4) { continue }

        $branchName = $parts[0] -replace '^origin/', ''
        try {
            $commitDate = [datetimeoffset]::Parse($parts[1]).LocalDateTime
        } catch {
            continue
        }

        $branchInfo += [pscustomobject]@{
            BranchName      = $branchName
            CommitDate      = $commitDate
            CommitDateText  = $commitDate.ToString('yyyy-MM-dd HH:mm')
            AuthorName      = $parts[2]
            Subject         = $parts[3]
        }
    }

    return ,@($branchInfo | Sort-Object -Property CommitDate -Descending)
}

function Get-RemoteBranchInfo {
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryUrl
    )

    $tempRepoRoot = Join-Path -Path $env:TEMP -ChildPath ("InitGitRemoteRefs_" + [guid]::NewGuid().ToString())
    New-Item -Path $tempRepoRoot -ItemType Directory -Force | Out-Null

    try {
        Push-Location -LiteralPath $tempRepoRoot
        try {
            git init --bare | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to initialize temporary bare repository."
            }

            git remote add origin $RepositoryUrl
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to add remote origin."
            }

            git fetch --quiet --depth 1 origin "+refs/heads/*:refs/remotes/origin/*"
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to fetch remote branches from $RepositoryUrl."
            }

            $format = "%(refname:short)|%(committerdate:iso8601)|%(authorname)|%(subject)"
            $lines = git for-each-ref refs/remotes/origin --sort=-committerdate --format=$format
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to enumerate remote branches."
            }
        } finally {
            Pop-Location
        }

        return ConvertTo-RemoteBranchInfo -Lines $lines
    } finally {
        if (Test-Path -LiteralPath $tempRepoRoot) {
            Remove-Item -LiteralPath $tempRepoRoot -Recurse -Force
        }
    }
}
