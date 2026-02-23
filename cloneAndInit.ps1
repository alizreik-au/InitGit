#Requires -Version 5.1
<#
.SYNOPSIS
    Clones a Git repository and initializes it with InitGit scripts (merge driver, LFS hooks, .gitignore, .gitattributes).
.DESCRIPTION
    Prompts for (or accepts) a repo URL, clones into the given parent directory, then generates
    .gitignore, .gitattributes, scripts (merge-theirs, setup-merge-driver), and Git hooks (post-merge, pre-push)
    in the clone. No dependency on external scripts or templates folders.
#>

$ErrorActionPreference = "Stop"

# Dot-source shared helpers (used by tests as well)
. (Join-Path -Path $PSScriptRoot -ChildPath 'CloneAndInitLib.ps1')

# Embedded content: generated into the clone so the script is self-contained
$script:GitignoreContent = @"
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

$script:GitattributesContent = @"
content/** filter=lfs diff=lfs merge=lfs -text
import/** filter=lfs diff=lfs merge=lfs -text
plugin/** filter=lfs diff=lfs merge=lfs -text
*.fbx filter=lfs diff=lfs merge=lfs -text
*.uasset filter=lfs diff=lfs merge=lfs -text
"@

$script:MergeTheirsBatContent = @"
@echo off
REM Git merge driver: keep "theirs" (incoming) version. Args: %P %O %A %B -> copy %B to %A
REM /B = binary copy (required; default copy would treat as text and corrupt .uasset / LFS)
copy /B /Y "%~4" "%~3" >nul
exit /b 0
"@

$script:PrePushHookContent = @'
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

$script:SetupMergeDriverBatContent = @"
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

function Get-RepositoryUrl {
    param([string]$DefaultUrl = "")

    Add-Type -AssemblyName PresentationFramework

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Clone and init - Repository URL" Height="200" Width="600" WindowStartupLocation="CenterScreen"
        Background="#F0F0F0" ResizeMode="CanResize">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Text="Enter the repository URL to clone:" FontSize="16" Margin="0,0,0,10"/>
        <TextBox x:Name="UrlTextBox" Grid.Row="1" FontSize="14" Padding="5"/>
        <Button x:Name="OkButton" Content="OK" Grid.Row="2" HorizontalAlignment="Right" Margin="0,20,0,0" Padding="20,5" FontSize="14"/>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $urlTextBox = $window.FindName("UrlTextBox")
    $okButton = $window.FindName("OkButton")

    $urlTextBox.Text = $DefaultUrl
    $okButton.Add_Click({ $window.DialogResult = $true })

    $result = $window.ShowDialog()
    if ($result) { return $urlTextBox.Text }
    return $null
}

try {
    # Parent directory: from argument (context menu) or current location
    $parentDir = if ($args.Length -gt 0) { $args[0] } else { (Get-Location).Path }
    $parentDir = $parentDir.Trim('"')
    if (-not (Test-Path -LiteralPath $parentDir -PathType Container)) {
        Write-Host "Parent directory does not exist: $parentDir" -ForegroundColor Red
        pause
        exit 1
    }

    # Repo URL: from argument or GUI
    $url = if ($args.Length -gt 1) { $args[1] } else { $null }
    while ([string]::IsNullOrWhiteSpace($url)) {
        $url = Get-RepositoryUrl -DefaultUrl $url
        if ([string]::IsNullOrWhiteSpace($url)) {
            $response = Read-Host "No repository URL provided. Try again? (Y/N)"
            if ($response -eq 'N') {
                Write-Host "Exiting."
                pause
                exit 1
            }
        }
    }
    $url = $url.Trim()

    Write-Host "Clone and init" -ForegroundColor Cyan
    Write-Host "===============" -ForegroundColor Cyan
    Write-Host "Repository: $url"
    Write-Host "Parent directory: $parentDir"
    Write-Host ""

    # Clone
    Write-Host "Cloning repository..."
    Push-Location -LiteralPath $parentDir
    try {
        git clone $url
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Clone failed." -ForegroundColor Red
            pause
            exit 1
        }
    } finally {
        Pop-Location
    }

    $repoName = Get-RepoNameFromUrl -Url $url
    if (-not $repoName) {
        Write-Host "Could not infer repo folder name from URL. Please run setup-merge-driver manually in the cloned folder." -ForegroundColor Yellow
        pause
        exit 0
    }

    $clonePath = Join-Path -Path $parentDir -ChildPath $repoName
    if (-not (Test-Path -LiteralPath $clonePath -PathType Container)) {
        Write-Host "Cloned folder not found: $clonePath" -ForegroundColor Red
        pause
        exit 1
    }

    # Generate .gitignore and .gitattributes in the clone
    Set-Content -LiteralPath (Join-Path -Path $clonePath -ChildPath '.gitignore') -Value $GitignoreContent -Encoding UTF8
    Write-Host "  Generated: .gitignore" -ForegroundColor Green
    Set-Content -LiteralPath (Join-Path -Path $clonePath -ChildPath '.gitattributes') -Value $GitattributesContent -Encoding UTF8
    Write-Host "  Generated: .gitattributes" -ForegroundColor Green

    # Generate scripts folder: merge-theirs.bat, setup-merge-driver.bat, hooks/pre-push
    $scriptsDir = Join-Path -Path $clonePath -ChildPath 'scripts'
    $hooksDir = Join-Path -Path $scriptsDir -ChildPath 'hooks'
    New-Item -Path $scriptsDir -ItemType Directory -Force | Out-Null
    New-Item -Path $hooksDir -ItemType Directory -Force | Out-Null

    Set-Content -LiteralPath (Join-Path -Path $scriptsDir -ChildPath 'merge-theirs.bat') -Value $MergeTheirsBatContent -Encoding ASCII
    Set-Content -LiteralPath (Join-Path -Path $scriptsDir -ChildPath 'setup-merge-driver.bat') -Value $SetupMergeDriverBatContent -Encoding ASCII
    Set-Content -LiteralPath (Join-Path -Path $hooksDir -ChildPath 'pre-push') -Value $PrePushHookContent -Encoding ASCII -NoNewline:$false
    Write-Host "  Generated: scripts\merge-theirs.bat, scripts\setup-merge-driver.bat, scripts\hooks\pre-push" -ForegroundColor Green

    # Git LFS and merge driver / hooks
    Push-Location -LiteralPath $clonePath
    try {
        git lfs install
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Warning: git lfs install failed. LFS may not be active." -ForegroundColor Yellow
        }

        git config merge.theirs.driver "scripts/merge-theirs.bat"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Warning: failed to set merge driver." -ForegroundColor Yellow
        } else {
            Write-Host "  Configured: merge driver 'theirs'" -ForegroundColor Green
        }

        $gitDir = Join-Path -Path $clonePath -ChildPath '.git'
        $postMergeHook = Join-Path -Path $gitDir -ChildPath 'hooks\post-merge'
        $prePushHook = Join-Path -Path $gitDir -ChildPath 'hooks\pre-push'
        $postMergeContent = "#!/bin/sh`ngit lfs pull"
        Set-Content -LiteralPath $postMergeHook -Value $postMergeContent -Encoding ASCII -NoNewline:$false
        Copy-Item -LiteralPath (Join-Path -Path $hooksDir -ChildPath 'pre-push') -Destination $prePushHook -Force
        Write-Host "  Generated: .git/hooks/post-merge, .git/hooks/pre-push (LFS pull/push)" -ForegroundColor Green
    } finally {
        Pop-Location
    }

    Write-Host ""
    Write-Host "Done. Cloned repo: $clonePath" -ForegroundColor Green
    pause
} catch {
    Write-Host "An error occurred:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    pause
    exit 1
}
