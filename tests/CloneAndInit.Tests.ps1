#Requires -Version 5.1
# Pester tests for CloneAndInit (Get-RepoNameFromUrl). Compatible with Pester 3 and 5.

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path -Path $repoRoot -ChildPath 'src\CloneAndInitLib.ps1')

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

Describe 'ConvertTo-RemoteBranchInfo' {
    It 'Parses and sorts branch details by commit date descending' {
        $lines = @(
            'origin/release|2026-05-01 08:00:00 +10:00|Casey|Release prep',
            'origin/main|2026-05-08 09:15:00 +10:00|Ali|Fix branch picker',
            'origin/dev|2026-05-07 18:30:00 +10:00|Morgan|Refactor clone flow'
        )

        $result = ConvertTo-RemoteBranchInfo -Lines $lines

        $result.Count | Should Be 3
        $result[0].BranchName | Should Be 'main'
        $result[1].BranchName | Should Be 'dev'
        $result[2].BranchName | Should Be 'release'
        $result[0].AuthorName | Should Be 'Ali'
        $result[0].Subject | Should Be 'Fix branch picker'
    }

    It 'Skips invalid lines' {
        $lines = @(
            '',
            'invalid',
            'origin/main|not-a-date|Ali|Bad row',
            'origin/good|2026-05-08 09:15:00 +10:00|Ali|Good row'
        )

        $result = ConvertTo-RemoteBranchInfo -Lines $lines

        $result.Count | Should Be 1
        $result[0].BranchName | Should Be 'good'
    }
}
