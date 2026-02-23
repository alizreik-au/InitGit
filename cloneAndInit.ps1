#Requires -Version 5.1
<#
.SYNOPSIS
    Clones a Git repository and initializes it with InitGit scripts (merge driver, LFS hooks, docs).
.DESCRIPTION
    Prompts for (or accepts) a repo URL, clones into the given parent directory, copies scripts
    and docs from this installation into the clone, and runs setup-merge-driver.bat.
#>

$ErrorActionPreference = "Stop"

# Dot-source shared helpers (used by tests as well)
. (Join-Path -Path $PSScriptRoot -ChildPath 'CloneAndInitLib.ps1')

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

    # Paths relative to this script (works from repo or from %LOCALAPPDATA%\InitGit)
    $scriptRoot = $PSScriptRoot
    $scriptsSource = Join-Path -Path $scriptRoot -ChildPath 'scripts'
    $docsSource = Join-Path -Path $scriptRoot -ChildPath 'docs'

    if (-not (Test-Path -LiteralPath $scriptsSource -PathType Container)) {
        Write-Host "Scripts folder not found: $scriptsSource" -ForegroundColor Red
        pause
        exit 1
    }

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

    # Copy scripts and docs into the clone
    $scriptsDest = Join-Path -Path $clonePath -ChildPath 'scripts'
    $docsDest = Join-Path -Path $clonePath -ChildPath 'docs'

    if (-not (Test-Path -LiteralPath $scriptsDest -PathType Container)) {
        New-Item -Path $scriptsDest -ItemType Directory -Force | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path -Path $scriptsSource -ChildPath '*') -Destination $scriptsDest -Recurse -Force
    Write-Host "  Copied: scripts -> $clonePath\scripts" -ForegroundColor Green

    if (Test-Path -LiteralPath $docsSource -PathType Container) {
        if (-not (Test-Path -LiteralPath $docsDest -PathType Container)) {
            New-Item -Path $docsDest -ItemType Directory -Force | Out-Null
        }
        Copy-Item -LiteralPath (Join-Path -Path $docsSource -ChildPath '*') -Destination $docsDest -Recurse -Force
        Write-Host "  Copied: docs -> $clonePath\docs" -ForegroundColor Green
    }

    # Run setup-merge-driver in the clone
    $setupBat = Join-Path -Path $clonePath -ChildPath 'scripts\setup-merge-driver.bat'
    if (Test-Path -LiteralPath $setupBat -PathType Leaf) {
        Write-Host "Running merge driver and hooks setup..."
        Push-Location -LiteralPath $clonePath
        try {
            & cmd /c "`"$setupBat`""
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Setup reported an error. Check $clonePath\scripts\setup-merge-driver.bat" -ForegroundColor Yellow
            } else {
                Write-Host "  Setup complete: merge driver and LFS hooks configured." -ForegroundColor Green
            }
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "  setup-merge-driver.bat not found; skipping merge driver setup." -ForegroundColor Yellow
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
