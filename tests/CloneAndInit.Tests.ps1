#Requires -Version 5.1
# Pester tests for CloneAndInit (Get-RepoNameFromUrl). Compatible with Pester 3 and 5.

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path -Path $repoRoot -ChildPath 'CloneAndInitLib.ps1')

Describe 'Get-RepoNameFromUrl' {
    It 'Returns repo name from HTTPS URL with .git' {
        (Get-RepoNameFromUrl -Url 'https://github.com/user/my-repo.git') | Should Be 'my-repo'
    }

    It 'Returns repo name from HTTPS URL without .git' {
        (Get-RepoNameFromUrl -Url 'https://github.com/user/my-repo') | Should Be 'my-repo'
    }

    It 'Returns repo name from Azure DevOps URL' {
        (Get-RepoNameFromUrl -Url 'https://dev.azure.com/org/project/_git/RepoName') | Should Be 'RepoName'
    }

    It 'Returns repo name when URL has trailing slash' {
        (Get-RepoNameFromUrl -Url 'https://github.com/user/MyRepo/') | Should Be 'MyRepo'
    }

    It 'Returns null for null URL' {
        Get-RepoNameFromUrl -Url $null | Should Be $null
    }

    It 'Returns null for empty string URL' {
        Get-RepoNameFromUrl -Url '' | Should Be $null
    }

    It 'Returns null for whitespace-only URL' {
        (Get-RepoNameFromUrl -Url '   ') | Should Be $null
    }

    It 'Strips query string and fragment from URL' {
        (Get-RepoNameFromUrl -Url 'https://github.com/user/repo.git?ref=main') | Should Be 'repo'
        (Get-RepoNameFromUrl -Url 'https://github.com/user/repo#readme') | Should Be 'repo'
    }

    It 'Handles single-segment URL' {
        (Get-RepoNameFromUrl -Url 'repo.git') | Should Be 'repo'
    }

    It 'Handles SSH-style URL' {
        (Get-RepoNameFromUrl -Url 'git@github.com:user/foo-bar.git') | Should Be 'foo-bar'
    }
}
