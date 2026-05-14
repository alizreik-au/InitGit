#Requires -Version 5.1
<#
.SYNOPSIS
    Small WPF helpers for InitGit installer (prerequisite prompt, context menu prompt).
#>

function Show-InitGitInstallerMessage {
    param(
        [string]$Message,
        [string]$Title = 'InitGit Installer'
    )
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Information')
}

function Show-InitGitPrerequisitesInstallDialog {
    param(
        [string[]]$MissingLines,
        [bool]$WingetAvailable
    )
    Add-Type -AssemblyName PresentationFramework

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="InitGit - Missing components" Height="360" Width="520" WindowStartupLocation="CenterScreen"
        Background="#F5F5F5" ResizeMode="CanResize">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock TextWrapping="Wrap" Margin="0,0,0,10"
      Text="Some tools recommended for InitGit are missing. Install them now with winget (recommended), or install manually later."/>
    <ListBox x:Name="MissingList" Grid.Row="1" Margin="0,0,0,10"/>
    <TextBlock x:Name="WingetNote" Grid.Row="2" TextWrapping="Wrap" Margin="0,0,0,10" Foreground="#444"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="NoBtn" Content="Skip" Width="90" Margin="0,0,8,0" Padding="10,5" IsCancel="True"/>
      <Button x:Name="YesBtn" Content="Install with winget" Width="150" Padding="10,5" IsDefault="True"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $list = $window.FindName('MissingList')
    $note = $window.FindName('WingetNote')
    $yes = $window.FindName('YesBtn')
    $no = $window.FindName('NoBtn')
    foreach ($line in $MissingLines) { [void]$list.Items.Add($line) }
    if ($WingetAvailable) {
        $note.Text = 'winget was found. You may see one or more UAC prompts for package installs.'
    } else {
        $note.Text = 'winget was not found. Use Skip, then install Git from https://git-scm.com/download/win , Git LFS from https://git-lfs.com , and ensure Git Credential Manager is enabled.'
        $yes.IsEnabled = $false
    }
    $yes.Add_Click({ $window.Tag = 'Yes'; $window.DialogResult = $true })
    $no.Add_Click({ $window.Tag = 'No'; $window.DialogResult = $false })
    $null = $window.ShowDialog()
    return ($window.Tag -eq 'Yes')
}

function Show-InitGitContextMenuRegDialog {
    Add-Type -AssemblyName PresentationFramework
    $msg = @"
Add InitGit entries to the folder right-click menu?

This merges a .reg file (UAC). On Windows 11, use 'Show more options' on a folder to see:
Clone and init repo, Update repo to InitGit, Init copied folder.

You can run Add-InitGit-Context-Menu.bat later from the install folder if you skip.
"@
    $r = [System.Windows.MessageBox]::Show($msg, 'InitGit - Context menu', 'YesNo', 'Question', 'Yes')
    return ($r -eq 'Yes')
}

function Invoke-InitGitWingetInstallMissing {
    param(
        [bool]$NeedGit,
        [bool]$NeedLfs,
        [bool]$NeedGcm
    )
    $parts = @()
    if ($NeedGit) {
        $parts += 'winget install -e --id Git.Git --source winget --accept-package-agreements --accept-source-agreements --scope user'
    }
    if ($NeedLfs) {
        $parts += 'winget install -e --id GitHub.git-lfs --source winget --accept-package-agreements --accept-source-agreements --scope user'
    }
    if ($NeedGcm) {
        $parts += 'winget install -e --id Microsoft.GitCredentialManagerCore --source winget --accept-package-agreements --accept-source-agreements --scope user'
    }
    if ($parts.Count -eq 0) { return }
    $body = ($parts -join "`r`n") + "`r`n" + 'exit $LASTEXITCODE' + "`r`n"
    $tmp = Join-Path -Path $env:TEMP -ChildPath ("InitGit-winget-" + [guid]::NewGuid().ToString('n') + '.ps1')
    try {
        Set-Content -LiteralPath $tmp -Value $body -Encoding UTF8
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tmp
        ) -Wait
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Update-InitGitSessionPathFromMachine {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}
