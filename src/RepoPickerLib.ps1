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
$script:InitGitUserDataFolderName = 'UserData'
$script:InitGitDefaultAzureOrg = 'affirmer'
$script:InitGitDefaultAzureCloneUrl = 'https://affirmer@dev.azure.com/affirmer/Affirmer_Git/_git/'

function Get-InitGitDefaultRepositoryUrl {
    [OutputType([string])]
    param()
    return $script:InitGitDefaultAzureCloneUrl
}

function Get-InitGitDefaultAzureOrganization {
    [OutputType([string])]
    param()
    if (-not [string]::IsNullOrWhiteSpace($env:AZURE_DEVOPS_ORG)) {
        return $env:AZURE_DEVOPS_ORG.Trim()
    }
    return $script:InitGitDefaultAzureOrg
}

function Get-InitGitPatFromGitCredentialManager {
    <#
    .SYNOPSIS
        Reads a stored PAT/password from Git Credential Manager for dev.azure.com.
    #>
    [OutputType([string])]
    param(
        [string]$HostName = 'dev.azure.com',
        [string]$Username
    )
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $user = if ([string]::IsNullOrWhiteSpace($Username)) { 'git' } else { $Username.Trim() }
    $stdin = "protocol=https`nhost=$HostName`nusername=$user`n`n"
    foreach ($helper in @('credential-manager', 'credential-manager-core')) {
        try {
            $out = $stdin | & git $helper get 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($out)) { continue }
            foreach ($line in ($out -split "`r?`n")) {
                if ($line -match '^password=(.+)$') { return $Matches[1].Trim() }
            }
        } catch { }
    }
    try {
        $out = $stdin | & git credential fill 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) {
            foreach ($line in ($out -split "`r?`n")) {
                if ($line -match '^password=(.+)$') { return $Matches[1].Trim() }
            }
        }
    } catch { }
    return $null
}

function Test-InitGitHasAzureDevOpsCredential {
    [OutputType([bool])]
    param([string]$Organization = '')
    if (-not [string]::IsNullOrWhiteSpace($env:AZURE_DEVOPS_EXT_PAT)) { return $true }
    foreach ($t in (Get-InitGitCmdkeyGitTargets)) {
        if ($t -match 'dev\.azure\.com') { return $true }
    }
    $org = if ([string]::IsNullOrWhiteSpace($Organization)) { Get-InitGitDefaultAzureOrganization } else { $Organization.Trim() }
    return -not [string]::IsNullOrWhiteSpace((Get-InitGitPatFromGitCredentialManager -Username $org))
}

function Save-InitGitAzureDevOpsPatToCredentialManager {
    <#
    .SYNOPSIS
        Stores an Azure DevOps PAT in Git Credential Manager (and cmdkey fallback).
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Pat,
        [string]$Organization = ''
    )
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }
    $user = if ([string]::IsNullOrWhiteSpace($Organization)) { Get-InitGitDefaultAzureOrganization } else { $Organization.Trim() }
    $stdin = @(
        'protocol=https'
        'host=dev.azure.com'
        "username=$user"
        "password=$Pat"
        ''
    ) -join "`n"
    foreach ($helper in @('credential-manager', 'credential-manager-core')) {
        try {
            $stdin | & git $helper store 2>$null
            if ($LASTEXITCODE -eq 0) { return $true }
        } catch { }
    }
    try {
        $stdin | & git credential store 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
    } catch { }
    try {
        & cmdkey.exe /generic:'git:https://dev.azure.com' /user:$user /pass:$Pat 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Show-InitGitAzurePatDialog {
    <#
    .SYNOPSIS
        Prompts for an Azure DevOps PAT (saved to GCM by the caller).
    #>
    [OutputType([string])]
    param(
        [string]$Organization = '',
        [string]$Title = 'Azure DevOps - Personal Access Token'
    )
    Add-Type -AssemblyName PresentationFramework
    $orgLabel = if ([string]::IsNullOrWhiteSpace($Organization)) { Get-InitGitDefaultAzureOrganization } else { $Organization.Trim() }
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title" Height="240" Width="480" WindowStartupLocation="CenterScreen"
        Background="#F5F5F5" ResizeMode="NoResize">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock TextWrapping="Wrap" Margin="0,0,0,12"
      Text="Enter a Personal Access Token for Azure DevOps organization '$orgLabel' with Code (read) scope. InitGit will save it in Git Credential Manager for git clone and fetch."/>
    <TextBlock Grid.Row="1" FontWeight="SemiBold" Margin="0,0,0,6" Text="Token"/>
    <PasswordBox x:Name="PatBox" Grid.Row="2" MinHeight="32" VerticalAlignment="Top"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="CancelBtn" Content="Cancel" MinWidth="90" Margin="0,0,8,0" Padding="10,6" IsCancel="True"/>
      <Button x:Name="OkBtn" Content="Save and continue" MinWidth="130" Padding="10,6" IsDefault="True"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $patBox = $window.FindName('PatBox')
    $ok = $window.FindName('OkBtn')
    $cancel = $window.FindName('CancelBtn')
    $ok.Add_Click({
            if ([string]::IsNullOrWhiteSpace($patBox.Password)) { return }
            $window.Tag = $patBox.Password
            $window.DialogResult = $true
        })
    $cancel.Add_Click({ $window.DialogResult = $false })
    $null = $window.ShowDialog()
    if ($window.DialogResult -eq $true) { return [string]$window.Tag }
    return $null
}

function Get-InitGitInstallRoot {
    [OutputType([string])]
    param()
    return (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'InitGit')
}

function Get-InitGitUserDataDir {
    [OutputType([string])]
    param()
    $dir = Join-Path -Path (Get-InitGitInstallRoot) -ChildPath $script:InitGitUserDataFolderName
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    return $dir
}

function Get-InitGitPathsToPreserveOnInstall {
    <#
    .SYNOPSIS
        Relative paths under InitGit install root that must not be deleted on update.
    #>
    [OutputType([string[]])]
    param()
    return ,@($script:InitGitUserDataFolderName)
}

function Get-InitGitProfilesPath {
    [OutputType([string])]
    param()
    $userDataDir = Get-InitGitUserDataDir
    $newPath = Join-Path -Path $userDataDir -ChildPath $script:InitGitProfilesFileName
    $legacyPath = Join-Path -Path (Get-InitGitInstallRoot) -ChildPath $script:InitGitProfilesFileName
    if ((Test-Path -LiteralPath $legacyPath) -and -not (Test-Path -LiteralPath $newPath)) {
        try {
            Move-Item -LiteralPath $legacyPath -Destination $newPath -Force
        } catch {
            Copy-Item -LiteralPath $legacyPath -Destination $newPath -Force
        }
    }
    return $newPath
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
    if ($pathPart -match '^https?://([^/]+)/([^/]+)/([^/]+?)(?:\.git)?(?:/|$)') {
        $hostPart = $Matches[1]
        $seg1 = $Matches[2]
        $seg2 = $Matches[3]
        if ($hostPart -match 'github') {
            if ($seg1 -eq '_git') { return @($null, $null) }
            if ($seg2 -match '^(tree|blob|pull|commits|releases|wiki|settings)$') { return @($null, $null) }
            return @($seg1, $seg2)
        }
    }
    if ($pathPart -match '^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$') {
        return @($Matches[1], $Matches[2])
    }
    return @($null, $null)
}

function ConvertTo-GitHubLinkHeaderString {
    [OutputType([string])]
    param($LinkHeader)
    if ($null -eq $LinkHeader) { return $null }
    if ($LinkHeader -is [System.Array]) {
        return ($LinkHeader | Select-Object -First 1)
    }
    return [string]$LinkHeader
}

function ConvertFrom-GitHubLinkHeaderNextUri {
    [OutputType([string])]
    param([string]$LinkHeader)
    $LinkHeader = ConvertTo-GitHubLinkHeaderString -LinkHeader $LinkHeader
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
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Profiles
    )
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

function Add-InitGitSavedProfile {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$Provider,
        [string]$Org = '',
        [string]$ApiBase = ''
    )
    $name = $DisplayName.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($p in (Get-InitGitSavedProfiles)) {
        if ($p.DisplayName -eq $name) { continue }
        $list.Add($p) | Out-Null
    }
    $list.Add([pscustomobject]@{
            Id          = [guid]::NewGuid().ToString('n')
            DisplayName = $name
            Provider    = $Provider
            Org         = $Org
            ApiBase     = $ApiBase
            FromEnv     = $false
        }) | Out-Null
    Save-InitGitSavedProfiles -Profiles $list.ToArray()
}

function Resolve-InitGitPat {
    param(
        [string]$TypedPat,
        [ValidateSet('GitHub', 'AzureDevOps')]
        [string]$Provider
    )
    if (-not [string]::IsNullOrWhiteSpace($TypedPat)) { return $TypedPat.Trim() }
    if ($Provider -eq 'AzureDevOps' -and $env:AZURE_DEVOPS_EXT_PAT) { return $env:AZURE_DEVOPS_EXT_PAT }
    if ($Provider -eq 'GitHub' -and $env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }
    return $null
}

function Get-InitGitRepoListPage {
    <#
    .SYNOPSIS
        Fetches one page of repositories (for background jobs / runspaces). Returns serializable hashtable.
    #>
    param(
        [ValidateSet('GitHub', 'AzureDevOps')]
        [string]$Provider,
        [Parameter(Mandatory)][string]$Pat,
        [string]$ApiBase = 'https://api.github.com',
        [string]$Organization = '',
        [string]$NextGitHubUri = $null,
        [string]$NextAzToken = $null
    )
    try {
        if ($Provider -eq 'AzureDevOps') {
            $page = Invoke-InitGitAzureDevOpsReposPage -Organization $Organization -Pat $Pat -ContinuationToken $NextAzToken
            return @{
                Ok            = $true
                Repos         = @($page.Repos)
                NextGitHubUri = $null
                NextAzToken   = $page.ContinuationToken
                Error         = $null
            }
        }
        $page = Invoke-InitGitGitHubUserReposPage -Pat $Pat -ApiBase $ApiBase -NextUri $NextGitHubUri
        return @{
            Ok            = $true
            Repos         = @($page.Repos)
            NextGitHubUri = $page.NextUri
            NextAzToken   = $null
            Error         = $null
        }
    } catch {
        return @{
            Ok            = $false
            Repos         = @()
            NextGitHubUri = $null
            NextAzToken   = $null
            Error         = $_.Exception.Message
        }
    }
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
    $link = ConvertTo-GitHubLinkHeaderString -LinkHeader $response.Headers['Link']
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
    if ([string]::IsNullOrWhiteSpace($orgSeg)) {
        throw 'Azure DevOps organization name is required.'
    }
    $orgEnc = [Uri]::EscapeDataString($orgSeg)
    $uri = "https://dev.azure.com/$orgEnc/_apis/git/repositories?api-version=7.0&`$top=100"
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
        Simple WPF modal: clone URL first; optional expander to list repos with a PAT.
    #>
    [OutputType([string])]
    param(
        [string]$DefaultUrl = '',
        [string]$DialogTitle = 'Repository URL'
    )

    if ([string]::IsNullOrWhiteSpace($DefaultUrl)) {
        $DefaultUrl = Get-InitGitDefaultRepositoryUrl
    }

    Add-Type -AssemblyName PresentationFramework

    $apiDefault = 'https://api.github.com'
    $pickerState = @{
        NextGitHubUri    = [string]$null
        NextAzToken      = [string]$null
        LoadGeneration   = 0
    }
    $repoList = [System.Collections.Generic.List[object]]::new()
    $savedProfilesByName = @{}

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Repository URL" MinWidth="440" MinHeight="360" Width="640" Height="520"
        WindowStartupLocation="CenterScreen" Background="#F5F5F5" ResizeMode="CanResize">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Grid Grid.Row="0" Margin="0,0,0,12">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <TextBlock Grid.Column="0" TextWrapping="Wrap" FontSize="14" Foreground="#222" VerticalAlignment="Center"
        Text="Azure DevOps clone URL (edit below). Use Load Repositories to pick a repo from your organization."/>
      <Button x:Name="LoadReposTopButton" Grid.Column="1" Content="Load Repositories"
              MinWidth="150" Padding="12,8" Margin="12,0,0,0" VerticalAlignment="Top"/>
    </Grid>
    <TextBlock Grid.Row="1" FontWeight="SemiBold" Margin="0,0,0,6" Text="Clone URL"/>
    <TextBox x:Name="UrlTextBox" Grid.Row="2" MinHeight="96" VerticalAlignment="Stretch"
             FontSize="13" Padding="8" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto"/>
    <Expander x:Name="OptionalExpander" Grid.Row="3" Margin="0,12,0,0" IsExpanded="True"
              Header="Azure DevOps account (org, token, repository list)">
      <ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="280" HorizontalScrollBarVisibility="Disabled">
        <Grid Margin="0,8,0,0">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0" TextWrapping="Wrap" Foreground="#444" Margin="0,0,0,6"
            Text="Configured for Azure DevOps. Paste a read-only token below, or sign in when you click Load Repositories (saved to Git Credential Manager)."/>
          <TextBlock x:Name="EnvPatHint" Grid.Row="1" TextWrapping="Wrap" Foreground="#666" Margin="0,0,0,8" FontSize="11"/>
          <Grid Grid.Row="2" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto" MinWidth="100"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Saved name" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <ComboBox x:Name="SavedProfileCombo" Grid.Column="1" MinHeight="28" IsEditable="False" HorizontalAlignment="Stretch"/>
          </Grid>
          <Grid Grid.Row="3" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto" MinWidth="100"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Account" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <ComboBox x:Name="ProviderCombo" Grid.Column="1" MinHeight="28" IsEditable="False" HorizontalAlignment="Stretch"/>
          </Grid>
          <Grid x:Name="OrgRow" Grid.Row="4" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto" MinWidth="100"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Azure org" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <TextBox x:Name="OrgTextBox" Grid.Column="1" MinHeight="28" VerticalAlignment="Stretch"/>
          </Grid>
          <Grid Grid.Row="5" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto" MinWidth="100"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Token" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <PasswordBox x:Name="PatPasswordBox" Grid.Column="1" MinHeight="28"/>
          </Grid>
          <StackPanel Grid.Row="6" Orientation="Horizontal" Margin="0,0,0,8">
            <Button x:Name="LoadMoreButton" Content="Load more" Padding="12,6" IsEnabled="False"/>
          </StackPanel>
          <TextBlock Grid.Row="7" Text="Choose a repo (fills the clone URL above)" Margin="0,0,0,4"/>
          <ComboBox x:Name="RepoCombo" Grid.Row="8" MinHeight="30" IsEditable="True" StaysOpenOnEdit="True" IsTextSearchEnabled="True" HorizontalAlignment="Stretch"/>
          <Expander x:Name="ExpertExpander" Grid.Row="9" Margin="0,12,0,0" IsExpanded="False" Header="Expert: switch to GitHub, API URL, test token, save profile name">
            <StackPanel Margin="0,8,0,0">
              <TextBlock Text="GitHub API (leave default for github.com)" Margin="0,0,0,4"/>
              <TextBox x:Name="ApiBaseTextBox" MinHeight="28" Margin="0,0,0,8"/>
              <StackPanel Orientation="Horizontal">
                <Button x:Name="TestConnButton" Content="Test connection" Padding="10,5" Margin="0,0,8,0"/>
                <Button x:Name="SaveProfileButton" Content="Save profile name..." Padding="10,5"/>
              </StackPanel>
            </StackPanel>
          </Expander>
        </Grid>
      </ScrollViewer>
    </Expander>
    <TextBlock x:Name="StatusText" Grid.Row="4" TextWrapping="Wrap" Foreground="#555" Margin="0,8,0,0" FontSize="12"/>
    <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="OkButton" Content="Continue" MinWidth="110" Margin="0,0,10,0" Padding="14,8" IsDefault="True"/>
      <Button x:Name="CancelButton" Content="Cancel" MinWidth="110" Padding="14,8"/>
    </StackPanel>
  </Grid>
</Window>
'@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $window.Title = $DialogTitle

    $urlTextBox = $window.FindName('UrlTextBox')
    $optionalExpander = $window.FindName('OptionalExpander')
    $providerCombo = $window.FindName('ProviderCombo')
    $orgRow = $window.FindName('OrgRow')
    $orgTextBox = $window.FindName('OrgTextBox')
    $apiBaseTextBox = $window.FindName('ApiBaseTextBox')
    $patBox = $window.FindName('PatPasswordBox')
    $testConnButton = $window.FindName('TestConnButton')
    $saveProfileButton = $window.FindName('SaveProfileButton')
    $loadReposTopButton = $window.FindName('LoadReposTopButton')
    $loadMoreButton = $window.FindName('LoadMoreButton')
    $repoCombo = $window.FindName('RepoCombo')
    $repoCombo.DisplayMemberPath = 'Name'
    $okButton = $window.FindName('OkButton')
    $cancelButton = $window.FindName('CancelButton')
    $statusText = $window.FindName('StatusText')
    $envPatHint = $window.FindName('EnvPatHint')
    $savedProfileCombo = $window.FindName('SavedProfileCombo')

    [void]$providerCombo.Items.Add('GitHub')
    [void]$providerCombo.Items.Add('Azure DevOps')
    $providerCombo.SelectedItem = 'Azure DevOps'
    $apiBaseTextBox.Text = $apiDefault
    $orgTextBox.Text = Get-InitGitDefaultAzureOrganization

    if ([string]::IsNullOrWhiteSpace($DefaultUrl)) {
        $urlTextBox.Text = Get-InitGitDefaultRepositoryUrl
    } else {
        $urlTextBox.Text = $DefaultUrl
    }

    function Get-ProviderKind {
        if ($providerCombo.SelectedItem -eq 'Azure DevOps') { return 'AzureDevOps' }
        return 'GitHub'
    }

    function Get-EffectivePat {
        $typed = ''
        try { $typed = $patBox.Password } catch { }
        return Resolve-InitGitPat -TypedPat $typed -Provider (Get-ProviderKind)
    }

    function Update-EnvPatHint {
        $hints = @()
        if ($env:GITHUB_TOKEN) { $hints += 'GITHUB_TOKEN is set (used when Token field is empty).' }
        if ($env:AZURE_DEVOPS_EXT_PAT) { $hints += 'AZURE_DEVOPS_EXT_PAT is set (used when Token field is empty).' }
        $envPatHint.Text = if ($hints.Count -gt 0) { ($hints -join ' ') } else { '' }
    }

    function Refresh-SavedProfileCombo {
        $script:savedProfilesByName = @{}
        $savedProfileCombo.Items.Clear()
        [void]$savedProfileCombo.Items.Add('(none)')
        foreach ($p in (Get-InitGitSavedProfiles)) {
            $script:savedProfilesByName[$p.DisplayName] = $p
            [void]$savedProfileCombo.Items.Add($p.DisplayName)
        }
        $savedProfileCombo.SelectedIndex = 0
    }

    function Sync-ProviderFromUrl {
        $t = $urlTextBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { return }
        $kind = Get-InitGitRepoProviderType -UrlOrEmpty $t
        if ($kind -eq 'AzureDevOps') {
            $providerCombo.SelectedItem = 'Azure DevOps'
            if (-not $orgTextBox.Text.Trim()) {
                $m = [regex]::Match($t, 'dev\.azure\.com/([^/]+)/', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                if ($m.Success) { $orgTextBox.Text = $m.Groups[1].Value }
            }
        } elseif ($kind -eq 'GitHub') {
            $providerCombo.SelectedItem = 'GitHub'
        }
    }

    function Update-ProviderUi {
        $isAz = ($providerCombo.SelectedItem -eq 'Azure DevOps')
        $orgRow.Visibility = if ($isAz) { 'Visible' } else { 'Collapsed' }
        $orgTextBox.IsEnabled = $isAz
    }

    function Set-Status {
        param([string]$Text)
        $statusText.Text = $Text
    }

    $urlTextBox.Add_LostFocus({ Sync-ProviderFromUrl })
    $savedProfileCombo.Add_SelectionChanged({
            $name = [string]$savedProfileCombo.SelectedItem
            if ([string]::IsNullOrWhiteSpace($name) -or $name -eq '(none)') { return }
            $p = $script:savedProfilesByName[$name]
            if (-not $p) { return }
            if ($p.Provider -eq 'AzureDevOps') {
                $providerCombo.SelectedItem = 'Azure DevOps'
            } else {
                $providerCombo.SelectedItem = 'GitHub'
            }
            if ($p.Org) { $orgTextBox.Text = $p.Org }
            if ($p.ApiBase) { $apiBaseTextBox.Text = $p.ApiBase }
            Update-ProviderUi
        })

    $providerCombo.Add_SelectionChanged({
            Update-ProviderUi
            Update-EnvPatHint
            $pickerState.LoadGeneration++
            $repoList.Clear()
            $repoCombo.Items.Clear()
            $pickerState.NextGitHubUri = $null
            $pickerState.NextAzToken = $null
            $loadMoreButton.IsEnabled = $false
            Set-Status -Text ''
        })

    $repoCombo.Add_SelectionChanged({
            $si = $repoCombo.SelectedItem
            if ($si -and ($si.PSObject.Properties['CloneUrl'])) {
                $cu = $si.CloneUrl
                if ($cu) { $urlTextBox.Text = [string]$cu }
            }
        })

    $testConnButton.Add_Click({
            Set-Status -Text 'Testing...'
            try {
                $pat = Get-EffectivePat
                if ($providerCombo.SelectedItem -eq 'GitHub') {
                    if ([string]::IsNullOrWhiteSpace($pat)) { throw 'Enter a token or set GITHUB_TOKEN.' }
                    $h = @{ Authorization = "Bearer $pat"; 'User-Agent' = 'InitGit' }
                    $null = Invoke-RestMethod -Uri "$( $apiBaseTextBox.Text.TrimEnd('/') )/user" -Headers $h -Method Get -ErrorAction Stop
                    Set-Status -Text 'GitHub: connection OK.'
                } else {
                    if ([string]::IsNullOrWhiteSpace($pat)) { throw 'Enter a token or set AZURE_DEVOPS_EXT_PAT.' }
                    $org = $orgTextBox.Text.Trim()
                    if (-not $org) { throw 'Enter your Azure DevOps organization name.' }
                    $orgEnc = [Uri]::EscapeDataString($org)
                    $pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":${pat}"))
                    $uri = "https://dev.azure.com/$orgEnc/_apis/projects?api-version=7.0&`$top=1"
                    $null = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Basic $pair" } -Method Get -ErrorAction Stop
                    Set-Status -Text 'Azure DevOps: connection OK.'
                }
            } catch {
                Set-Status -Text ("Error: " + $_.Exception.Message)
            }
        })

    $saveProfileButton.Add_Click({
            Add-Type -AssemblyName Microsoft.VisualBasic
            $name = [Microsoft.VisualBasic.Interaction]::InputBox('Profile display name (token is never saved to disk)', 'Save profile', 'My account')
            if ([string]::IsNullOrWhiteSpace($name)) { return }
            $prov = Get-ProviderKind
            Add-InitGitSavedProfile -DisplayName $name -Provider $prov -Org $orgTextBox.Text.Trim() -ApiBase $apiBaseTextBox.Text.Trim()
            Refresh-SavedProfileCombo
            $savedProfileCombo.SelectedItem = $name.Trim()
            Set-Status -Text 'Saved profile name (token not stored).'
        })

    function Resolve-AzureDevOpsPatForLoad {
        $org = $orgTextBox.Text.Trim()
        if (-not $org) {
            $orgTextBox.Text = Get-InitGitDefaultAzureOrganization
            $org = $orgTextBox.Text.Trim()
        }
        $pat = Get-EffectivePat
        if ([string]::IsNullOrWhiteSpace($pat)) {
            $pat = Get-InitGitPatFromGitCredentialManager -Username $org
        }
        if ([string]::IsNullOrWhiteSpace($pat)) {
            $pat = Show-InitGitAzurePatDialog -Organization $org
            if ([string]::IsNullOrWhiteSpace($pat)) { return $null }
            $saved = Save-InitGitAzureDevOpsPatToCredentialManager -Pat $pat -Organization $org
            if ($saved) {
                Set-Status -Text 'Token saved to Git Credential Manager.'
            } else {
                Set-Status -Text 'Token accepted but could not save to Git Credential Manager; listing will still work this session.'
            }
            try { $patBox.Password = $pat } catch { }
        }
        return $pat
    }

    function Invoke-LoadRepositories {
        $providerCombo.SelectedItem = 'Azure DevOps'
        Update-ProviderUi
        $optionalExpander.IsExpanded = $true
        Sync-ProviderFromUrl

        $provKind = Get-ProviderKind
        $pat = $null
        if ($provKind -eq 'AzureDevOps') {
            $pat = Resolve-AzureDevOpsPatForLoad
            if ([string]::IsNullOrWhiteSpace($pat)) {
                if (-not $statusText.Text) {
                    Set-Status -Text 'A personal access token is required to load repositories.'
                }
                return
            }
        } else {
            $pat = Get-EffectivePat
            if ([string]::IsNullOrWhiteSpace($pat)) {
                Set-Status -Text 'Enter a token (or set GITHUB_TOKEN).'
                return
            }
        }
        Start-AsyncRepoLoad -Append $false -PatOverride $pat
    }

    function Start-AsyncRepoLoad {
        param(
            [bool]$Append,
            [string]$PatOverride = $null
        )

        if (-not $Append) {
            $repoList.Clear()
            $repoCombo.Items.Clear()
            $pickerState.NextGitHubUri = $null
            $pickerState.NextAzToken = $null
        }

        $provKind = Get-ProviderKind
        $pat = if (-not [string]::IsNullOrWhiteSpace($PatOverride)) { $PatOverride } else { Get-EffectivePat }
        $org = $orgTextBox.Text.Trim()
        $apiBase = $apiBaseTextBox.Text.Trim()

        if ($provKind -eq 'AzureDevOps') {
            if (-not $org) {
                Set-Status -Text 'Enter your Azure DevOps organization.'
                return
            }
            if ([string]::IsNullOrWhiteSpace($pat)) {
                $pat = Resolve-AzureDevOpsPatForLoad
                if ([string]::IsNullOrWhiteSpace($pat)) { return }
            }
        } elseif ([string]::IsNullOrWhiteSpace($pat)) {
            Set-Status -Text 'Enter a token (or set GITHUB_TOKEN).'
            return
        }

        $gen = ++$pickerState.LoadGeneration
        $loadReposTopButton.IsEnabled = $false
        $loadMoreButton.IsEnabled = $false
        Set-Status -Text 'Loading repositories...'

        $nextGh = $pickerState.NextGitHubUri
        $nextAz = $pickerState.NextAzToken

        $task = [System.Threading.Tasks.Task]::Run({
                Get-InitGitRepoListPage -Provider $provKind -Pat $pat -ApiBase $apiBase -Organization $org `
                    -NextGitHubUri $nextGh -NextAzToken $nextAz
            })

        $null = $task.ContinueWith({
                param($t)
                $page = $null
                if ($t.IsFaulted) {
                    $err = $t.Exception.InnerException
                    if (-not $err) { $err = $t.Exception }
                    $page = @{ Ok = $false; Error = $err.Message; Repos = @() }
                } else {
                    $page = $t.Result
                }
                $window.Dispatcher.BeginInvoke([action]{
                        if ($pickerState.LoadGeneration -ne $gen) { return }

                        $loadReposTopButton.IsEnabled = $true

                        if (-not $page.Ok) {
                            Set-Status -Text $page.Error
                            $loadMoreButton.IsEnabled = $false
                            return
                        }

                        foreach ($r in $page.Repos) {
                            $repoList.Add($r) | Out-Null
                            [void]$repoCombo.Items.Add($r)
                        }
                        $pickerState.NextGitHubUri = $page.NextGitHubUri
                        $pickerState.NextAzToken = $page.NextAzToken
                        $hasMore = (-not [string]::IsNullOrWhiteSpace($pickerState.NextGitHubUri)) -or (-not [string]::IsNullOrWhiteSpace($pickerState.NextAzToken))
                        $loadMoreButton.IsEnabled = $hasMore
                        $count = @($page.Repos).Count
                        $suffix = if ($hasMore) { ' Click Load more for the next page.' } else { '' }
                        Set-Status -Text ("Loaded $count repositories.$suffix")
                    }) | Out-Null
            })
    }

    $loadReposTopButton.Add_Click({ Invoke-LoadRepositories })

    $loadMoreButton.Add_Click({
            $pat = $null
            if ((Get-ProviderKind) -eq 'AzureDevOps') {
                $pat = Resolve-AzureDevOpsPatForLoad
                if ([string]::IsNullOrWhiteSpace($pat)) { return }
            }
            Start-AsyncRepoLoad -Append $true -PatOverride $pat
        })

    $okButton.Add_Click({
            if ([string]::IsNullOrWhiteSpace($urlTextBox.Text)) {
                Set-Status -Text 'Enter a clone URL, or open Optional and pick from your account.'
                return
            }
            $window.DialogResult = $true
        })
    $cancelButton.Add_Click({ $window.DialogResult = $false })

    Refresh-SavedProfileCombo
    Update-EnvPatHint
    Sync-ProviderFromUrl
    Update-ProviderUi
    Set-Status -Text ''

    $null = $window.ShowDialog()
    if ($window.DialogResult -eq $true) {
        return $urlTextBox.Text.Trim()
    }
    return $null
}

function Show-InitGitYesNoMessage {
    <#
    .SYNOPSIS
        Use instead of Read-Host when scripts run without a console (e.g. Explorer context menu).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Title = 'InitGit'
    )
    Add-Type -AssemblyName PresentationFramework
    $r = [System.Windows.MessageBox]::Show($Message, $Title, 'YesNo', 'Question', 'Yes')
    return ($r -eq 'Yes')
}

# Back-compat alias
function Get-RepositoryUrlFromDialog {
    param(
        [string]$DefaultUrl = '',
        [string]$DialogTitle = 'Repository URL'
    )
    if ([string]::IsNullOrWhiteSpace($DefaultUrl)) {
        $DefaultUrl = Get-InitGitDefaultRepositoryUrl
    }
    return Show-InitGitRepositoryUrlDialog -DefaultUrl $DefaultUrl -DialogTitle $DialogTitle
}
