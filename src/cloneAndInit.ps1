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

# Dot-source shared helpers and content (used by tests as well)
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

function Select-RemoteBranch {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Branches
    )

    Add-Type -AssemblyName PresentationFramework

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Clone and init - Select branch" Height="520" Width="980" WindowStartupLocation="CenterScreen"
        Background="#F0F0F0" ResizeMode="CanResize">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Text="Select a remote branch to clone. Branches are ordered by most recent commit." FontSize="16" Margin="0,0,0,12"/>
        <ListView x:Name="BranchListView" Grid.Row="1" Margin="0,0,0,12">
            <ListView.View>
                <GridView>
                    <GridViewColumn Header="Branch" Width="240" DisplayMemberBinding="{Binding BranchName}" />
                    <GridViewColumn Header="Last Commit" Width="150" DisplayMemberBinding="{Binding CommitDateText}" />
                    <GridViewColumn Header="Author" Width="160" DisplayMemberBinding="{Binding AuthorName}" />
                    <GridViewColumn Header="Subject" Width="380" DisplayMemberBinding="{Binding Subject}" />
                </GridView>
            </ListView.View>
        </ListView>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="CancelButton" Content="Cancel" Width="100" Margin="0,0,8,0" Padding="12,6"/>
            <Button x:Name="SelectButton" Content="Clone branch" Width="120" Padding="12,6" IsDefault="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $branchListView = $window.FindName("BranchListView")
    $selectButton = $window.FindName("SelectButton")
    $cancelButton = $window.FindName("CancelButton")

    $branchListView.ItemsSource = $Branches
    if ($Branches.Count -gt 0) {
        $branchListView.SelectedIndex = 0
    }

    $branchListView.Add_MouseDoubleClick({
        if ($branchListView.SelectedItem) {
            $window.DialogResult = $true
        }
    })
    $selectButton.Add_Click({ $window.DialogResult = $true })
    $cancelButton.Add_Click({ $window.DialogResult = $false })

    $result = $window.ShowDialog()
    if ($result -and $branchListView.SelectedItem) {
        return $branchListView.SelectedItem
    }
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

    Write-Host "Loading remote branches..."
    $remoteBranches = Get-RemoteBranchInfo -RepositoryUrl $url
    if (-not $remoteBranches -or $remoteBranches.Count -eq 0) {
        Write-Host "No remote branches found for: $url" -ForegroundColor Red
        pause
        exit 1
    }

    $selectedBranch = if ($args.Length -gt 2) {
        $remoteBranches | Where-Object { $_.BranchName -eq $args[2] } | Select-Object -First 1
    } else {
        Select-RemoteBranch -Branches $remoteBranches
    }
    if (-not $selectedBranch) {
        Write-Host "No branch selected. Exiting." -ForegroundColor Yellow
        pause
        exit 1
    }

    Write-Host "Clone and init" -ForegroundColor Cyan
    Write-Host "===============" -ForegroundColor Cyan
    Write-Host "Repository: $url"
    Write-Host "Branch: $($selectedBranch.BranchName)"
    Write-Host "Parent directory: $parentDir"
    Write-Host ""

    # Clone
    Write-Host "Cloning repository..."
    Push-Location -LiteralPath $parentDir
    try {
        git clone --branch $selectedBranch.BranchName --single-branch $url
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
