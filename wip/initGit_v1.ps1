# Enable error handling
$ErrorActionPreference = "Stop"

Write-Host "Script started."
pause

function Get-RepositoryUrl {
    param (
        [string]$DefaultUrl = ""
    )
    
    Add-Type -AssemblyName Microsoft.VisualBasic
    $userInput = [Microsoft.VisualBasic.Interaction]::InputBox('Please enter the repository URL:', 'Repository URL', $DefaultUrl)
    
    return $userInput
}

# Get repository URL from command line argument or prompt user
$userInput = if ($args[0]) {
    $args[0]
} else {
    do {
        $url = Get-RepositoryUrl
        if ([string]::IsNullOrEmpty($url)) {
            $response = Read-Host "No repository URL provided. Do you want to try again? (Y/N)"
            if ($response -eq 'N') {
                Write-Host "Exiting script."
                pause
                exit 1
            }
        }
    } while ([string]::IsNullOrEmpty($url))
    $url
}

Write-Host "Repository URL: '$userInput'"
pause

Write-Host "Initializing Git repository..."
git init

Write-Host "Adding Git remote..."
git remote add origin $userInput

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

# Create .gitignore file
$gitignoreContent = @"
Binaries
DerivedDataCache
Intermediate
Saved
.vscode
.vs
*.VC.db
*.opensdf
*.opendb
*.sdf
*.sln
*.suo
*.xcodeproj
*.xcworkspace
"@

Set-Content -Path ".gitignore" -Value $gitignoreContent

if (Test-Path ".gitignore") {
    Write-Host ".gitignore file has been created successfully."
} else {
    Write-Host "Failed to create .gitignore file."
}

Write-Host "Script completed."
pause
