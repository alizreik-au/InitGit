#Requires -Version 5.1
$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath 'CloneAndInitLib.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'RepoPickerLib.ps1')

try {
    $currentDir = if ($args.Length -gt 0) {
        $args[0]
    } else {
        (Get-Location).Path
    }

    Set-Location $currentDir
    Write-Host "Working directory: $currentDir"

    do {
        $url = Get-RepositoryUrlFromDialog -DefaultUrl '' -DialogTitle 'InitGit - Repository URL'
        if ([string]::IsNullOrEmpty($url)) {
            if (-not (Show-InitGitYesNoMessage -Message 'No repository URL was entered. Try again?' -Title 'InitGit')) {
                Write-Host "Exiting script."
                pause
                exit 1
            }
        }
    } while ([string]::IsNullOrEmpty($url))

    $userInput = $url.Trim()

    Write-Host "Repository URL: '$userInput'"

    Write-Host "Initializing Git repository..."
    git init

    Write-Host "Adding Git remote..."
    & git remote add origin -- $userInput

    Write-Host "Configuring Git for HTTP/1.1..."
    git config --local http.version HTTP/1.1

    Write-Host "Installing Git LFS..."
    git lfs install

    Write-Host "Tracking files with Git LFS..."
    git lfs track "content/**"
    git lfs track "import/**"
    git lfs track "plugin/**"
    git lfs track "*.fbx"

    Write-Host "Initializing Git LFS..."
    git lfs init

    Write-Host "Configuring LFS lock verification..."
    git config "lfs.$userInput.git/info/lfs.locksverify" "true"

    $gitignorePath = Join-Path $currentDir ".gitignore"
    Set-Content -Path $gitignorePath -Value $GitignoreContent -Encoding UTF8

    if (Test-Path $gitignorePath) {
        Write-Host ".gitignore file has been created successfully in $currentDir."
    } else {
        Write-Host "Failed to create .gitignore file in $currentDir."
    }

    Write-Host "Script completed."
    pause
}
catch {
    Write-Host "An error occurred:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    Write-Host "Contact Ali for help!"
    Write-Host "Press any key to end..."
    pause
    exit 1
}
