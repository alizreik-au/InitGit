#Requires -Version 5.1
<#
.SYNOPSIS
    Probes Git, Git LFS, and Git Credential Manager; writes JSON to -ResultPath (atomic rename from .draft).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'

$draft = "$ResultPath.draft"
$state = [ordered]@{
    GitPresent = $false
    LfsPresent = $false
    GcmPresent   = $false
    GitVersion   = ''
    Messages     = @()
    WingetIds    = [ordered]@{
        Git = 'Git.Git'
        Lfs = 'GitHub.git-lfs'
        Gcm = 'Microsoft.GitCredentialManagerCore'
    }
}

function Add-Note {
    param([string]$Text)
    $state.Messages = @($state.Messages) + @($Text)
}

try {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        Add-Note 'Git is not on PATH.'
    } else {
        $state.GitPresent = $true
        try {
            $state.GitVersion = (& git --version 2>$null | Select-Object -First 1)
        } catch { }
    }

    if ($state.GitPresent) {
        try {
            $null = & git lfs version 2>$null
            if ($LASTEXITCODE -eq 0) {
                $state.LfsPresent = $true
            } else {
                Add-Note 'Git LFS is not available (git lfs version failed).'
            }
        } catch {
            Add-Note 'Git LFS is not available.'
        }

        $gcmOk = $false
        try {
            $null = & git credential-manager --version 2>$null
            if ($LASTEXITCODE -eq 0) { $gcmOk = $true }
        } catch { }
        if (-not $gcmOk) {
            try {
                $null = & git credential-manager-core --version 2>$null
                if ($LASTEXITCODE -eq 0) { $gcmOk = $true }
            } catch { }
        }
        if (-not $gcmOk) {
            $helpers = & git config --show-origin --get-all credential.helper 2>$null
            foreach ($h in $helpers) {
                if ($h -match 'manager') {
                    $gcmOk = $true
                    break
                }
            }
        }
        if ($gcmOk) {
            $state.GcmPresent = $true
        } else {
            Add-Note 'Git Credential Manager not detected (install Git for Windows or GCM).'
        }
    } else {
        Add-Note 'Skipping LFS and GCM checks until Git is installed.'
    }
} catch {
    Add-Note $_.Exception.Message
}

$json = $state | ConvertTo-Json -Depth 6
Set-Content -LiteralPath $draft -Value $json -Encoding UTF8
if (Test-Path -LiteralPath $ResultPath) {
    Remove-Item -LiteralPath $ResultPath -Force
}
Move-Item -LiteralPath $draft -Destination $ResultPath -Force
exit 0
