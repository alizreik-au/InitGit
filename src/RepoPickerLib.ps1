#Requires -Version 5.1
<#
.SYNOPSIS
    Repo URL picker helpers: GitHub/Azure DevOps REST, profiles, credential hints, disk preflight, WPF dialog.
.DESCRIPTION
    Dot-source after CloneAndInitLib.ps1. PATs are never written to repo-profiles.json.
    Environment: GITHUB_TOKEN, AZURE_DEVOPS_EXT_PAT, AZURE_DEVOPS_ORG, INITGIT_MIN_FREE_BYTES
#>

# TLS 1.2 for GitHub API on older .NET defaults
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$script:InitGitProfilesFileName = 'repo-profiles.json'

function Get-InitGitProfilesPath {
    [OutputType([string])]
    param()
    $dir = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'InitGit'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    return (Join-Path -Path $dir -ChildPath $script:InitGitProfilesFileName)
}

function Get-InitGitRepoProviderType {
    <#
    .SYNOPSIS
        Classifies URL or explicit provider string as GitHub or AzureDevOps.
    #>
    [OutputType([string])]
    param(
        [string]$UrlOrEmpty,
        [ValidateSet('GitHub', 'AzureDevOps', 'Unknown')]
        [string]$Explicit = 'Unknown'
    )
    if ($Explicit -ne 'Unknown') { return $Explicit }
    if ([string]::IsNullOrWhiteSpace($UrlOrEmpty)) { return 'Unknown' }
    $u = $UrlOrEmpty.Trim().ToLowerInvariant()
    if ($u -match 'dev\.azure\.com' -or $u -match 'visualstudio\.com') { return 'AzureDevOps' }
    if ($u -match 'github\.com' -or $u -match 'github\.enterprise') { return 'GitHub' }
    return 'Unknown'
}

function Get-InitGitGitHubOwnerRepoFromUrl {
    [OutputType([string[]])]
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return @($null, $null) }
    $pathPart = ($Url -split '[?#]')[0].TrimEnd('/')
    if ($pathPart -match '^https?://([^/]+)/([^/]+)/([^/]+)') {
        $hostPart = $Matches[1]
        $seg1 = $Matches[2]
        $seg2 = $Matches[3] -replace '\.git$', ''
        if ($hostPart -match 'github') {
            if ($seg1 -eq '_git') { return @($null, $null) }
            return @($seg1, $seg2)
        }
    }
    if ($pathPart -match '^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$') {
        return @($Matches[1], $Matches[2])
    }
    return @($null, $null)
}

function ConvertFrom-GitHubLinkHeaderNextUri {
    [OutputType([string])]
    param([string]$LinkHeader)
    if ([string]::IsNullOrWhiteSpace($LinkHeader)) { return $null }
    foreach ($part in ($LinkHeader -split ',')) {
        if ($part -match '^\s*<([^>]+)>\s*;\s*rel="next"') {
            return $Matches[1].Trim()
        }
    }
    return $null
}

function Get-InitGitCmdkeyGitTargets {
    [OutputType([string[]])]
    param()
    $lines = & cmdkey.exe /list 2>$null
    if (-not $lines) { return @() }
    $targets = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        if ($line -match '^\s*Target:\s*(.+)') {
            $t = $Matches[1].Trim()
            if ($t -match 'git:https://(github\.com|dev\.azure\.com)' -or $t -match 'LegacyGeneric:target=git:') {
                $targets.Add($t) | Out-Null
            }
        }
    }
    return ,$targets.ToArray()
}

function Get-InitGitEnvImplicitProfiles {
    [OutputType([object[]])]
    param()
    $list = [System.Collections.Generic.List[object]]::new()
    if ($env:GITHUB_TOKEN) {
        $list.Add([pscustomobject]@{
                Id          = 'env:GITHUB_TOKEN'
                DisplayName = 'GitHub (GITHUB_TOKEN)'
                Provider    = 'GitHub'
                Org         = [string]$null
                ApiBase     = 'https://api.github.com'
                FromEnv     = $true
            }) | Out-Null
    }
    if ($env:AZURE_DEVOPS_EXT_PAT) {
        $org = if ($env:AZURE_DEVOPS_ORG) { $env:AZURE_DEVOPS_ORG } else { '' }
        $dn = if ($org) { "Azure DevOps (PAT from env) - $org" } else { 'Azure DevOps (PAT from env)' }
        $list.Add([pscustomobject]@{
                Id          = 'env:AZURE_DEVOPS_EXT_PAT'
                DisplayName = $dn
                Provider    = 'AzureDevOps'
                Org         = $org
                ApiBase     = [string]$null
                FromEnv     = $true
            }) | Out-Null
    }
    return ,$list.ToArray()
}

function Get-InitGitSavedProfiles {
    [OutputType([object[]])]
    param()
    $path = Get-InitGitProfilesPath
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $arr = $raw | ConvertFrom-Json
        if ($arr -isnot [System.Array]) { $arr = @($arr) }
        $out = foreach ($p in $arr) {
            if (-not $p.DisplayName -or -not $p.Provider) { continue }
            [pscustomobject]@{
                Id          = [string]$p.Id
                DisplayName = [string]$p.DisplayName
                Provider    = [string]$p.Provider
                Org         = [string]$p.Org
                ApiBase     = if ($p.ApiBase) { [string]$p.ApiBase } else { '' }
                FromEnv     = $false
            }
        }
        return ,@($out)
    } catch {
        return @()
    }
}

function Save-InitGitSavedProfiles {
    param([Parameter(Mandatory)][object[]]$Profiles)
    $path = Get-InitGitProfilesPath
    $serializable = foreach ($p in $Profiles) {
        if ($p.FromEnv) { continue }
        [ordered]@{
            Id          = $p.Id
            DisplayName = $p.DisplayName
            Provider    = $p.Provider
            Org         = $p.Org
            ApiBase     = $p.ApiBase
        }
    }
    $arr = @($serializable)
    $json = if ($arr.Count -gt 0) { $arr | ConvertTo-Json -Depth 4 } else { '[]' }
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
}

function Merge-InitGitProfileLists {
    [OutputType([object[]])]
    param(
        [object[]]$Saved,
        [object[]]$EnvProfiles,
        [string[]]$CmdkeyHints
    )
    $seen = @{}
    $merged = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $EnvProfiles) {
        $key = $e.Id
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $merged.Add($e) | Out-Null
        }
    }
    foreach ($s in $Saved) {
        $key = if ($s.Id) { $s.Id } else { "saved:$($s.DisplayName)" }
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $merged.Add($s) | Out-Null
        }
    }
    $i = 0
    foreach ($c in $CmdkeyHints) {
        $i++
        $key = "cmdkey:$c"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $merged.Add([pscustomobject]@{
                Id          = $key
                DisplayName = "Credential: $c"
                Provider    = 'Unknown'
                Org         = [string]$null
                ApiBase     = [string]$null
                FromEnv     = $false
                HintOnly    = $true
            }) | Out-Null
    }
    return ,$merged.ToArray()
}

function Get-InitGitPatForProfile {
    param(
        [object]$Profile
    )
    if (-not $Profile) { return $null }
    if ($Profile.Id -eq 'env:GITHUB_TOKEN') { return $env:GITHUB_TOKEN }
    if ($Profile.Id -eq 'env:AZURE_DEVOPS_EXT_PAT') { return $env:AZURE_DEVOPS_EXT_PAT }
    return $null
}

function Invoke-InitGitGitHubUserReposPage {
    param(
        [string]$Pat,
        [string]$ApiBase = 'https://api.github.com',
        [string]$NextUri = $null
    )
    if ([string]::IsNullOrWhiteSpace($Pat)) { throw 'GitHub PAT is required.' }
    $base = $ApiBase.TrimEnd('/')
    $uri = if ($NextUri) { $NextUri } else { "$base/user/repos?per_page=30&page=1" }
    $headers = @{
        Authorization = "Bearer $Pat"
        Accept        = 'application/vnd.github+json'
        'User-Agent'  = 'InitGit-RepoPicker'
    }
    $params = @{
        Uri             = $uri
        Headers         = $headers
        Method          = 'Get'
        UseBasicParsing = $true
    }
    try {
        $response = Invoke-WebRequest @params -ErrorAction Stop
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        throw "GitHub API error ($code): $($_.Exception.Message)"
    }
    $link = $response.Headers['Link']
    $next = ConvertFrom-GitHubLinkHeaderNextUri -LinkHeader $link
    $items = ($response.Content | ConvertFrom-Json)
    if ($items -isnot [System.Array]) { $items = @($items) }
    $repos = foreach ($r in $items) {
        $cloneUrl = $r.clone_url
        if (-not $cloneUrl) { continue }
        [pscustomobject]@{
            Name     = [string]$r.full_name
            CloneUrl = $cloneUrl
        }
    }
    return [pscustomobject]@{ Repos = @($repos); NextUri = $next }
}

function Invoke-InitGitAzureDevOpsReposPage {
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Pat,
        [string]$ContinuationToken = $null
    )
    $orgSeg = $Organization.Trim()
    $uri = "https://dev.azure.com/$orgSeg/_apis/git/repositories?api-version=7.0&`$top=100"
    if ($ContinuationToken) {
        $uri += '&continuationToken=' + [Uri]::EscapeDataString($ContinuationToken)
    }
    $pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":${Pat}"))
    $headers = @{ Authorization = "Basic $pair" }
    try {
        $response = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get -UseBasicParsing -ErrorAction Stop
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        throw "Azure DevOps API error ($code): $($_.Exception.Message)"
    }
    $ct = $response.Headers['x-ms-continuationtoken']
    if ([string]::IsNullOrWhiteSpace($ct)) {
        $ct = $response.Headers['X-Ms-Continuationtoken']
    }
    $json = $response.Content | ConvertFrom-Json
    $items = $json.value
    if (-not $items) { $items = @() }
    $repos = foreach ($r in $items) {
        $clone = $r.remoteUrl
        if (-not $clone) { $clone = $r.url }
        if (-not $clone) { $clone = $r.webUrl }
        if (-not $clone) { continue }
        $proj = $r.project.name
        $nm = if ($proj) { "$proj / $($r.name)" } else { [string]$r.name }
        [pscustomobject]@{
            Name     = $nm
            CloneUrl = [string]$clone
        }
    }
    return [pscustomobject]@{ Repos = @($repos); ContinuationToken = $ct }
}

function Get-InitGitGitHubRepoSizeKb {
    param(
        [string]$Owner,
        [string]$Repo,
        [string]$Pat,
        [string]$ApiBase = 'https://api.github.com'
    )
    if ([string]::IsNullOrWhiteSpace($Owner) -or [string]::IsNullOrWhiteSpace($Repo) -or [string]::IsNullOrWhiteSpace($Pat)) {
        return $null
    }
    $uri = "$( $ApiBase.TrimEnd('/') )/repos/$Owner/$Repo"
    try {
        $headers = @{
            Authorization = "Bearer $Pat"
            Accept        = 'application/vnd.github+json'
            'User-Agent'  = 'InitGit'
        }
        $r = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
        return [int]$r.size
    } catch {
        return $null
    }
}

function Get-InitGitDriveFreeBytes {
    [OutputType([long])]
    param([Parameter(Mandatory)][string]$Path)
    try {
        $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    } catch {
        $full = $Path
    }
    $root = [System.IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($root)) { return -1 }
    $driveLetter = $root.TrimEnd('\').TrimEnd('/')
    if ($driveLetter.Length -eq 1) { $driveLetter = "${driveLetter}:" }
    $vol = Get-Volume -FilePath $full -ErrorAction SilentlyContinue
    if ($vol -and $null -ne $vol.SizeRemaining) {
        return [long]$vol.SizeRemaining
    }
    $driveName = $driveLetter.TrimEnd(':')
    $d = Get-PSDrive -Name $driveName -PSProvider FileSystem -ErrorAction SilentlyContinue
    if ($d -and $null -ne $d.Free) { return [long]$d.Free }
    return -1
}

function Get-InitGitMinFreeBytesThreshold {
    [OutputType([long])]
    param()
    if ($env:INITGIT_MIN_FREE_BYTES -match '^\d+$') {
        return [long]$env:INITGIT_MIN_FREE_BYTES
    }
    return 10GB
}

function Format-InitGitByteSize {
    param([long]$Bytes)
    if ($Bytes -lt 0) { return 'unknown' }
    $gb = [math]::Round($Bytes / 1GB, 2)
    return "$gb GB ($Bytes bytes)"
}

function Show-InitGitLowDiskSpaceDialog {
    param(
        [long]$FreeBytes,
        [long]$MinBytes,
        [string]$DriveLabel = ''
    )
    Add-Type -AssemblyName PresentationFramework
    $freeTxt = Format-InitGitByteSize -Bytes $FreeBytes
    $minTxt = Format-InitGitByteSize -Bytes $MinBytes
    $msg = "Free space on the destination drive is low.`n`nAvailable: $freeTxt`nRecommended minimum (INITGIT_MIN_FREE_BYTES): $minTxt`n`nClone may fail or fill the disk. Continue anyway?"
    $r = [System.Windows.MessageBox]::Show($msg, 'InitGit - disk space', 'YesNo', 'Warning', 'No')
    return ($r -eq 'Yes')
}

function Show-InitGitRepositoryUrlDialog {
    <#
    .SYNOPSIS
        WPF modal: provider, profiles, PAT, load repos (paged), manual URL.
    #>
    [OutputType([string])]
    param(
        [string]$DefaultUrl = '',
        [string]$DialogTitle = 'Repository URL'
    )

    Add-Type -AssemblyName PresentationFramework

    $cmdHints = Get-InitGitCmdkeyGitTargets
    $envProfs = Get-InitGitEnvImplicitProfiles
    $saved = Get-InitGitSavedProfiles
    $allProfiles = Merge-InitGitProfileLists -Saved $saved -EnvProfiles $envProfs -CmdkeyHints $cmdHints

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Repository URL" Height="560" Width="720" WindowStartupLocation="CenterScreen"
        Background="#F0F0F0" ResizeMode="CanResize">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Text="Provider" FontWeight="SemiBold" Margin="0,0,0,4"/>
    <ComboBox x:Name="ProviderCombo" Grid.Row="1" Margin="0,0,0,10" IsEditable="False"/>
    <TextBlock Grid.Row="2" Text="Profile / account" FontWeight="SemiBold" Margin="0,0,0,4"/>
    <ComboBox x:Name="ProfileCombo" Grid.Row="3" Margin="0,0,0,8" IsEditable="True" StaysOpenOnEdit="True" IsTextSearchEnabled="True"/>
    <StackPanel Grid.Row="4" Orientation="Horizontal" Margin="0,0,0,8">
      <TextBlock Text="Azure org: " VerticalAlignment="Center" Margin="0,0,6,0"/>
      <TextBox x:Name="OrgTextBox" Width="220" VerticalAlignment="Center"/>
      <TextBlock Text="  GitHub API: " VerticalAlignment="Center" Margin="12,0,6,0"/>
      <TextBox x:Name="ApiBaseTextBox" Width="260" VerticalAlignment="Center"/>
    </StackPanel>
    <StackPanel Grid.Row="5" Orientation="Horizontal" Margin="0,0,0,8">
      <TextBlock Text="PAT (not saved unless you click Save profile)" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <PasswordBox x:Name="PatPasswordBox" Width="280" VerticalAlignment="Center"/>
      <Button x:Name="TestConnButton" Content="Test connection" Margin="10,0,0,0" Padding="10,4"/>
      <Button x:Name="SaveProfileButton" Content="Save profile..." Margin="8,0,0,0" Padding="10,4"/>
    </StackPanel>
    <StackPanel Grid.Row="6" Orientation="Horizontal" Margin="0,0,0,8">
      <Button x:Name="LoadReposButton" Content="Load repositories" Padding="12,5"/>
      <Button x:Name="LoadMoreButton" Content="Load more" Margin="8,0,0,0" Padding="12,5" IsEnabled="False"/>
      <TextBlock x:Name="RepoHintText" Text="Select a repo below or type the clone URL." VerticalAlignment="Center" Margin="14,0,0,0" TextWrapping="Wrap" Foreground="#444"/>
    </StackPanel>
    <ComboBox x:Name="RepoCombo" Grid.Row="7" Margin="0,0,0,8" IsEditable="True" StaysOpenOnEdit="True" IsTextSearchEnabled="True"/>
    <TextBlock Grid.Row="8" Text="Repository URL (clone)" FontWeight="SemiBold" Margin="0,0,0,4"/>
    <TextBox x:Name="UrlTextBox" Grid.Row="9" FontSize="13" Padding="6" Height="64" TextWrapping="Wrap" AcceptsReturn="False" VerticalScrollBarVisibility="Auto"/>
    <StackPanel Grid.Row="10" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="OkButton" Content="OK" Width="100" Margin="0,0,8,0" Padding="14,6" IsDefault="True"/>
      <Button x:Name="CancelButton" Content="Cancel" Width="100" Padding="14,6"/>
    </StackPanel>
    <TextBlock x:Name="StatusText" Grid.Row="10" VerticalAlignment="Bottom" HorizontalAlignment="Left"
               Foreground="#333" TextWrapping="Wrap" MaxWidth="420" Margin="0,0,0,36"/>
  </Grid>
</Window>
'@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $window.Title = $DialogTitle

    $providerCombo = $window.FindName('ProviderCombo')
    $profileCombo = $window.FindName('ProfileCombo')
    $orgTextBox = $window.FindName('OrgTextBox')
    $apiBaseTextBox = $window.FindName('ApiBaseTextBox')
    $patBox = $window.FindName('PatPasswordBox')
    $testConnButton = $window.FindName('TestConnButton')
    $saveProfileButton = $window.FindName('SaveProfileButton')
    $loadReposButton = $window.FindName('LoadReposButton')
    $loadMoreButton = $window.FindName('LoadMoreButton')
    $repoHintText = $window.FindName('RepoHintText')
    $repoCombo = $window.FindName('RepoCombo')
    $repoCombo.DisplayMemberPath = 'Name'
    $urlTextBox = $window.FindName('UrlTextBox')
    $okButton = $window.FindName('OkButton')
    $cancelButton = $window.FindName('CancelButton')
    $statusText = $window.FindName('StatusText')

    [void]$providerCombo.Items.Add('GitHub')
    [void]$providerCombo.Items.Add('Azure DevOps')
    $providerCombo.SelectedIndex = 0

    $apiBaseTextBox.Text = 'https://api.github.com'

    $dialogProfiles = [System.Collections.ArrayList]::new()
    foreach ($p in $allProfiles) { [void]$dialogProfiles.Add($p) }

    $pickerState = @{
        NextGitHubUri = [string]$null
        NextAzToken   = [string]$null
    }

    $repoList = [System.Collections.Generic.List[object]]::new()

    foreach ($p in $dialogProfiles) {
        [void]$profileCombo.Items.Add($p.DisplayName)
    }
    if ($profileCombo.Items.Count -gt 0) { $profileCombo.SelectedIndex = 0 }

    $urlTextBox.Text = $DefaultUrl

    function Get-SelectedProfileObject {
        $idx = $profileCombo.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $dialogProfiles.Count) { return $null }
        return $dialogProfiles[$idx]
    }

    function Get-EffectivePat {
        $prof = Get-SelectedProfileObject
        $fromEnv = Get-InitGitPatForProfile -Profile $prof
        if ($fromEnv) { return $fromEnv }
        return $patBox.Password
    }

    function Update-ProviderUi {
        $isAz = ($providerCombo.SelectedItem -eq 'Azure DevOps')
        $orgTextBox.IsEnabled = $isAz
        $apiBaseTextBox.IsEnabled = -not $isAz
        if ($isAz) {
            if (-not $orgTextBox.Text -and $env:AZURE_DEVOPS_ORG) {
                $orgTextBox.Text = $env:AZURE_DEVOPS_ORG
            }
        }
    }

    function Set-Status {
        param([string]$Text)
        $statusText.Text = $Text
    }

    $profileCombo.Add_SelectionChanged({ Update-ProviderUi })
    $providerCombo.Add_SelectionChanged({
            Update-ProviderUi
            $repoList.Clear()
            $repoCombo.Items.Clear()
            $pickerState.NextGitHubUri = $null
            $pickerState.NextAzToken = $null
            $loadMoreButton.IsEnabled = $false
            Set-Status -Text 'Provider changed. Load repositories again.'
        })

    $repoCombo.Add_SelectionChanged({
            $si = $repoCombo.SelectedItem
            if ($si -and ($si -is [pscustomobject] -or $si.PSObject.Properties['CloneUrl'])) {
                $cu = $si.CloneUrl
                if ($cu) { $urlTextBox.Text = [string]$cu }
            }
        })

    $testConnButton.Add_Click({
            Set-Status -Text 'Testing...'
            try {
                $pat = Get-EffectivePat
                if ($providerCombo.SelectedItem -eq 'GitHub') {
                    if ([string]::IsNullOrWhiteSpace($pat)) { throw 'Enter PAT or select env profile with GITHUB_TOKEN.' }
                    $h = @{ Authorization = "Bearer $pat"; 'User-Agent' = 'InitGit' }
                    $null = Invoke-RestMethod -Uri "$( $apiBaseTextBox.Text.TrimEnd('/') )/user" -Headers $h -Method Get -ErrorAction Stop
                    Set-Status -Text 'GitHub: connection OK.'
                } else {
                    if ([string]::IsNullOrWhiteSpace($pat)) { throw 'Enter PAT or env AZURE_DEVOPS_EXT_PAT.' }
                    $org = $orgTextBox.Text.Trim()
                    if (-not $org) { throw 'Enter Azure DevOps organization name.' }
                    $pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":${pat}"))
                    $uri = "https://dev.azure.com/$org/_apis/projects?api-version=7.0&`$top=1"
                    $null = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Basic $pair" } -Method Get -ErrorAction Stop
                    Set-Status -Text 'Azure DevOps: connection OK.'
                }
            } catch {
                Set-Status -Text ("Error: " + $_.Exception.Message)
            }
        })

    $saveProfileButton.Add_Click({
            Add-Type -AssemblyName Microsoft.VisualBasic
            $name = [Microsoft.VisualBasic.Interaction]::InputBox('Display name for this profile', 'Save profile', 'My account')
            if ([string]::IsNullOrWhiteSpace($name)) { return }
            $newId = [guid]::NewGuid().ToString('n')
            $prov = if ($providerCombo.SelectedItem -eq 'Azure DevOps') { 'AzureDevOps' } else { 'GitHub' }
            $newProf = [pscustomobject]@{
                Id          = $newId
                DisplayName = $name.Trim()
                Provider    = $prov
                Org         = $orgTextBox.Text.Trim()
                ApiBase     = $apiBaseTextBox.Text.Trim()
                FromEnv     = $false
            }
            [void]$dialogProfiles.Add($newProf)
            [void]$profileCombo.Items.Add($newProf.DisplayName)
            $profileCombo.SelectedIndex = $profileCombo.Items.Count - 1
            $savedList = Get-InitGitSavedProfiles
            $savedList = @($savedList) + @([pscustomobject]@{
                    Id = $newId; DisplayName = $newProf.DisplayName; Provider = $prov
                    Org = $newProf.Org; ApiBase = $newProf.ApiBase; FromEnv = $false
                })
            Save-InitGitSavedProfiles -Profiles $savedList
            Set-Status -Text 'Profile saved (PAT is not stored in the file; paste PAT again next time or use env vars).'
        })

    function Invoke-LoadReposPage {
        param([bool]$Append)
        if (-not $Append) {
            $repoList.Clear()
            $repoCombo.Items.Clear()
            $pickerState.NextGitHubUri = $null
            $pickerState.NextAzToken = $null
        }
        $pat = Get-EffectivePat
        if ($providerCombo.SelectedItem -eq 'Azure DevOps') {
            $org = $orgTextBox.Text.Trim()
            if (-not $org) {
                Set-Status -Text 'Enter Azure DevOps organization.'
                return
            }
            if ([string]::IsNullOrWhiteSpace($pat)) {
                Set-Status -Text 'Enter PAT (or use AZURE_DEVOPS_EXT_PAT).'
                return
            }
            try {
                $page = Invoke-InitGitAzureDevOpsReposPage -Organization $org -Pat $pat -ContinuationToken $pickerState.NextAzToken
                foreach ($r in $page.Repos) {
                    $repoList.Add($r) | Out-Null
                    [void]$repoCombo.Items.Add($r)
                }
                $pickerState.NextAzToken = $page.ContinuationToken
                $loadMoreButton.IsEnabled = -not [string]::IsNullOrWhiteSpace($pickerState.NextAzToken)
                Set-Status -Text ("Loaded " + $page.Repos.Count + " repositories (Azure).")
            } catch {
                Set-Status -Text $_.Exception.Message
            }
            return
        }
        if ([string]::IsNullOrWhiteSpace($pat)) {
            Set-Status -Text 'Enter PAT (or use GITHUB_TOKEN profile).'
            return
        }
        try {
            $page = Invoke-InitGitGitHubUserReposPage -Pat $pat -ApiBase $apiBaseTextBox.Text.Trim() -NextUri $pickerState.NextGitHubUri
            foreach ($r in $page.Repos) {
                $repoList.Add($r) | Out-Null
                [void]$repoCombo.Items.Add($r)
            }
            $pickerState.NextGitHubUri = $page.NextUri
            $loadMoreButton.IsEnabled = -not [string]::IsNullOrWhiteSpace($pickerState.NextGitHubUri)
            Set-Status -Text ("Loaded " + $page.Repos.Count + " repositories (GitHub). More: " + (-not [string]::IsNullOrWhiteSpace($pickerState.NextGitHubUri)))
        } catch {
            Set-Status -Text $_.Exception.Message
        }
    }

    $loadReposButton.Add_Click({
            $loadReposButton.IsEnabled = $false
            $window.Dispatcher.Invoke([action] { }, 'Render', $null, $null) | Out-Null
            try {
                Invoke-LoadReposPage -Append $false
            } finally {
                $loadReposButton.IsEnabled = $true
            }
        })

    $loadMoreButton.Add_Click({
            $loadMoreButton.IsEnabled = $false
            try {
                Invoke-LoadReposPage -Append $true
            } finally {
                $loadMoreButton.IsEnabled = (-not [string]::IsNullOrWhiteSpace($pickerState.NextGitHubUri)) -or (-not [string]::IsNullOrWhiteSpace($pickerState.NextAzToken))
            }
        })

    $okButton.Add_Click({
            if ([string]::IsNullOrWhiteSpace($urlTextBox.Text)) {
                Set-Status -Text 'Enter a repository URL.'
                return
            }
            $window.DialogResult = $true
        })
    $cancelButton.Add_Click({ $window.DialogResult = $false })

    Update-ProviderUi

    $null = $window.ShowDialog()
    if ($window.DialogResult -eq $true) {
        return $urlTextBox.Text.Trim()
    }
    return $null
}

# Back-compat alias
function Get-RepositoryUrlFromDialog {
    param([string]$DefaultUrl = '', [string]$DialogTitle = 'Repository URL')
    return Show-InitGitRepositoryUrlDialog -DefaultUrl $DefaultUrl -DialogTitle $DialogTitle
}
