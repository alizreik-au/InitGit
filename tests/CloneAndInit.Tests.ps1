#Requires -Version 5.1
# Pester tests for CloneAndInit (Get-RepoNameFromUrl). Compatible with Pester 3 and 5.

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path -Path $repoRoot -ChildPath 'src\CloneAndInitLib.ps1')
. (Join-Path -Path $repoRoot -ChildPath 'src\RepoPickerLib.ps1')

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

Describe 'Get-InitGitRepoProviderType' {
    It 'Detects Azure DevOps from dev.azure.com' {
        (Get-InitGitRepoProviderType -UrlOrEmpty 'https://dev.azure.com/org/proj/_git/x') | Should Be 'AzureDevOps'
    }

    It 'Detects GitHub from github.com' {
        (Get-InitGitRepoProviderType -UrlOrEmpty 'https://github.com/a/b.git') | Should Be 'GitHub'
    }

    It 'Respects explicit provider' {
        (Get-InitGitRepoProviderType -UrlOrEmpty '' -Explicit 'GitHub') | Should Be 'GitHub'
    }
}

Describe 'ConvertFrom-GitHubLinkHeaderNextUri' {
    It 'Parses rel=next from Link header' {
        $h = '<https://api.github.com/user/repos?page=2>; rel="next", <https://api.github.com/user/repos?page=5>; rel="last"'
        (ConvertFrom-GitHubLinkHeaderNextUri -LinkHeader $h) | Should Be 'https://api.github.com/user/repos?page=2'
    }

    It 'Returns null when no next' {
        (ConvertFrom-GitHubLinkHeaderNextUri -LinkHeader '<https://api.github.com/user/repos?page=1>; rel="last"') | Should Be $null
    }
}

Describe 'Get-InitGitGitHubOwnerRepoFromUrl' {
    It 'Parses https github URL' {
        $o, $r = Get-InitGitGitHubOwnerRepoFromUrl -Url 'https://github.com/acme/widget.git'
        $o | Should Be 'acme'
        $r | Should Be 'widget'
    }

    It 'Parses SSH github URL' {
        $o, $r = Get-InitGitGitHubOwnerRepoFromUrl -Url 'git@github.com:acme/widget.git'
        $o | Should Be 'acme'
        $r | Should Be 'widget'
    }
}

Describe 'Merge-InitGitProfileLists' {
    It 'Merges saved and env without duplicate env id' {
        $envP = [pscustomobject]@{ Id = 'env:GITHUB_TOKEN'; DisplayName = 'GH'; Provider = 'GitHub'; Org = ''; ApiBase = ''; FromEnv = $true }
        $saved = [pscustomobject]@{ Id = '1'; DisplayName = 'S'; Provider = 'GitHub'; Org = ''; ApiBase = ''; FromEnv = $false }
        $m = Merge-InitGitProfileLists -Saved @($saved) -EnvProfiles @($envP) -CmdkeyHints @()
        $m.Count | Should Be 2
    }
}

Describe 'Prerequisite JSON contract' {
    It 'Parses sample prerequisite output shape' {
        $json = '{"GitPresent":true,"LfsPresent":false,"GcmPresent":true,"GitVersion":"git 2.0","Messages":["x"],"WingetIds":{"Git":"Git.Git"}}'
        $o = $json | ConvertFrom-Json
        $o.GitPresent | Should Be $true
        $o.LfsPresent | Should Be $false
        $o.WingetIds.Git | Should Be 'Git.Git'
    }
}

