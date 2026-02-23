#Requires -Version 5.1
<#
.SYNOPSIS
    Helper functions for cloneAndInit.ps1 (shared for testing).
.DESCRIPTION
    Get-RepoNameFromUrl returns the repository name (safe for folder names) from a Git URL.
#>

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
