# Enable error handling
$ErrorActionPreference = "Stop"
try {
    if ($args.Length -gt 0) {
        Set-Location $args[0]
        Write-Host "Changed working directory to: $($args[0])"
    }
function Get-RepositoryUrl {
    param (
        [string]$DefaultUrl = ""
    )
    
    Add-Type -AssemblyName PresentationFramework
    
    $xaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="Repository URL" Height="200" Width="600" WindowStartupLocation="CenterScreen"
            Background="#F0F0F0" ResizeMode="CanResize">
        <Grid Margin="20">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock Text="Please enter the repository URL:" FontSize="16" Margin="0,0,0,10"/>
            <TextBox x:Name="UrlTextBox" Grid.Row="1" FontSize="14" Padding="5"/>
            <Button x:Name="OkButton" Content="OK" Grid.Row="2" HorizontalAlignment="Right" Margin="0,20,0,0" Padding="20,5" FontSize="14"/>
        </Grid>
    </Window>
"@
    
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)
    
    $urlTextBox = $window.FindName("UrlTextBox")
    $okButton = $window.FindName("OkButton")
    
    $urlTextBox.Text = $DefaultUrl
    
    $okButton.Add_Click({ $window.DialogResult = $true })
    
    $result = $window.ShowDialog()
    
    if ($result) {
        return $urlTextBox.Text
    } else {
        return $null
    }
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
$gitignorePath = Join-Path (Get-Location) ".gitignore"
Set-Content -Path $gitignorePath -Value $gitignoreContent

if (Test-Path $gitignorePath) {
        Write-Host ".gitignore file has been created successfully in $(Get-Location)."
    } else {
        Write-Host "Failed to create .gitignore file in $(Get-Location)."
    }

Write-Host "Repository URL: '$userInput'"

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
Start-Sleep -Seconds 3

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
