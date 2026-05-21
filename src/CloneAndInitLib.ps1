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
git config --local http.version HTTP/1.1
if %ERRORLEVEL% neq 0 (
  echo Failed to set http.version HTTP/1.1.
  exit /b 1
)
echo Configured: http.version = HTTP/1.1

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

function Set-InitGitLocalHttpVersion {
    <#
    .SYNOPSIS
        Sets [http] version = HTTP/1.1 in the repository .git/config (local scope).
    #>
    [OutputType([bool])]
    param(
        [switch]$Quiet
    )
    if (-not $Quiet) {
        Write-Host 'Configuring Git for HTTP/1.1...'
    }
    git config --local http.version HTTP/1.1
    if ($LASTEXITCODE -ne 0) {
        if (-not $Quiet) {
            Write-Host '  Warning: failed to set http.version HTTP/1.1' -ForegroundColor Yellow
        }
        return $false
    }
    if (-not $Quiet) {
        Write-Host '  Configured: http.version = HTTP/1.1' -ForegroundColor Green
    }
    return $true
}

function Install-InitGitGitLfsInRepo {
    <#
    .SYNOPSIS
        Runs git lfs install without failing when hooks already exist (common on re-run).
    #>
    [OutputType([hashtable])]
    param()
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = @(git lfs install 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { "$_" }
            })
        $text = ($out -join ' ').Trim()
        if ($LASTEXITCODE -eq 0) {
            return @{ Ok = $true; Message = 'Git LFS installed' }
        }
        if ($text -match 'Hook already exists') {
            $null = @(git lfs install --skip-repo 2>&1 | Out-Null)
            return @{
                Ok      = $true
                Message = 'Git LFS already configured (pre-push hook exists); applying InitGit hooks'
            }
        }
        return @{ Ok = $false; Message = "git lfs install: $text" }
    } finally {
        $ErrorActionPreference = $prevEap
    }
}

function Install-InitGitRepoHooks {
    <#
    .SYNOPSIS
        Installs post-merge (lfs pull) and InitGit pre-push; backs up existing pre-push to pre-push.lfs when needed.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$RepoRoot
    )
    $gitDir = Join-Path -Path $RepoRoot -ChildPath '.git'
    $hooksDir = Join-Path -Path $gitDir -ChildPath 'hooks'
    $scriptsPrePush = Join-Path -Path $RepoRoot -ChildPath 'scripts\hooks\pre-push'
    if (-not (Test-Path -LiteralPath $scriptsPrePush)) {
        return $false
    }

    New-Item -Path $hooksDir -ItemType Directory -Force | Out-Null

    $postMergeHook = Join-Path -Path $hooksDir -ChildPath 'post-merge'
    if (Test-Path -LiteralPath $postMergeHook) {
        $existing = Get-Content -LiteralPath $postMergeHook -Raw -ErrorAction SilentlyContinue
        if ($existing -and ($existing -notmatch 'git lfs pull')) {
            Add-Content -LiteralPath $postMergeHook -Value "`ngit lfs pull" -Encoding ASCII
        }
    } else {
        Set-Content -LiteralPath $postMergeHook -Value "#!/bin/sh`ngit lfs pull" -Encoding ASCII -NoNewline:$false
    }

    $prePushHook = Join-Path -Path $hooksDir -ChildPath 'pre-push'
    $prePushLfs = Join-Path -Path $hooksDir -ChildPath 'pre-push.lfs'
    if (Test-Path -LiteralPath $prePushHook) {
        $existing = Get-Content -LiteralPath $prePushHook -Raw -ErrorAction SilentlyContinue
        $isInitGitHook = $existing -match 'git lfs push.*--all'
        if (-not $isInitGitHook -and -not (Test-Path -LiteralPath $prePushLfs)) {
            Copy-Item -LiteralPath $prePushHook -Destination $prePushLfs -Force
        }
    }
    Copy-Item -LiteralPath $scriptsPrePush -Destination $prePushHook -Force
    return $true
}

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
