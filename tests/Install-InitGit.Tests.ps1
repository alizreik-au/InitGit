#Requires -Version 5.1
# Pester tests for Install-InitGit.ps1 (install layout and generated content). Compatible with Pester 3 and 5.

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$installScript = Join-Path -Path $repoRoot -ChildPath 'install\Install-InitGit.ps1'

Describe 'Install-InitGit script structure' {
    It 'Install script exists' {
        Test-Path -LiteralPath $installScript -PathType Leaf | Should Be $true
    }

    It 'Script defines expected CopyMap entries' {
        $content = Get-Content -LiteralPath $installScript -Raw
        $content | Should Match "initGit\.ps1"
        $content | Should Match "cloneAndInit\.ps1"
        $content | Should Match "CloneAndInitLib\.ps1"
    }

    It 'Script defines InstallDir under LOCALAPPDATA' {
        $content = Get-Content -LiteralPath $installScript -Raw
        $content | Should Match '\$env:LOCALAPPDATA.*InitGit'
    }

    It 'Reg content template uses double backslashes for path' {
        $content = Get-Content -LiteralPath $installScript -Raw
        $content | Should Match '\\\\RunCloneAndInit\.bat'
        $content | Should Match '\\\\RunReInitRepo\.bat'
    }

    It 'Reg content contains Folder and Directory\Background shell keys' {
        $content = Get-Content -LiteralPath $installScript -Raw
        $content | Should Match 'Folder\\shell\\InitGit_CloneAndInit'
        $content | Should Match 'Directory\\Background\\shell\\InitGit_CloneAndInit'
        $content | Should Match 'Folder\\shell\\InitGit_ReInitRepo'
        $content | Should Match 'Directory\\Background\\shell\\InitGit_ReInitRepo'
    }
}

Describe 'Install-InitGit execution' {
    It 'Installs to temp dir and creates expected files when run with mocked LOCALAPPDATA' {
        $testLocalAppData = Join-Path -Path $TestDrive -ChildPath 'LocalAppData'
        New-Item -Path $testLocalAppData -ItemType Directory -Force | Out-Null

        $originalLocalAppData = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = $testLocalAppData
            Mock Read-Host { return 'n' }

            & $installScript
        } finally {
            $env:LOCALAPPDATA = $originalLocalAppData
        }

        $installDir = Join-Path -Path $testLocalAppData -ChildPath 'InitGit'
        Test-Path -LiteralPath $installDir -PathType Container | Should Be $true

        Test-Path -LiteralPath (Join-Path $installDir 'cloneAndInit.ps1') -PathType Leaf | Should Be $true
        Test-Path -LiteralPath (Join-Path $installDir 'CloneAndInitLib.ps1') -PathType Leaf | Should Be $true
        Test-Path -LiteralPath (Join-Path $installDir 'RunCloneAndInit.bat') -PathType Leaf | Should Be $true
        Test-Path -LiteralPath (Join-Path $installDir 'RunReInitRepo.bat') -PathType Leaf | Should Be $true
        Test-Path -LiteralPath (Join-Path $installDir 'Add_InitGit_Context_Menu.reg') -PathType Leaf | Should Be $true
        Test-Path -LiteralPath (Join-Path $installDir 'scripts') -PathType Container | Should Be $true
        Test-Path -LiteralPath (Join-Path $installDir 'docs') -PathType Container | Should Be $true
    }

    It 'Generated .reg file contains install path and RunCloneAndInit.bat' {
        $testLocalAppData = Join-Path -Path $TestDrive -ChildPath 'LocalAppData2'
        New-Item -Path $testLocalAppData -ItemType Directory -Force | Out-Null

        $originalLocalAppData = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = $testLocalAppData
            Mock Read-Host { return 'n' }
            & $installScript
        } finally {
            $env:LOCALAPPDATA = $originalLocalAppData
        }

        $regPath = Join-Path -Path $testLocalAppData -ChildPath 'InitGit\Add_InitGit_Context_Menu.reg'
        $regContent = Get-Content -LiteralPath $regPath -Raw
        $expectedPath = $testLocalAppData -replace '\\', '\\\\'
        $regContent | Should Match ([regex]::Escape($expectedPath))
        $regContent | Should Match 'RunCloneAndInit\.bat'
        $regContent | Should Match 'RunReInitRepo\.bat'
        $regContent | Should Match 'InitGit_CloneAndInit'
        $regContent | Should Match 'InitGit_ReInitRepo'
    }
}
