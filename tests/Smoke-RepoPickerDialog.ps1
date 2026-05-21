#Requires -Version 5.1
<#
.SYNOPSIS
    Opens the InitGit repository URL picker for manual smoke testing (Load Repositories, PAT, repo list).
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Smoke-RepoPickerDialog.ps1
#>
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'src\CloneAndInitLib.ps1')
. (Join-Path $repoRoot 'src\RepoPickerLib.ps1')

Write-Host 'InitGit repo picker smoke test' -ForegroundColor Cyan
Write-Host '1. Click Load Repositories (top right)' -ForegroundColor Gray
Write-Host '2. Enter PAT if prompted; confirm list loads without error' -ForegroundColor Gray
Write-Host '3. Pick a repo or edit URL, then Continue' -ForegroundColor Gray
Write-Host ''

$url = Show-InitGitRepositoryUrlDialog -DialogTitle 'Smoke test - Repository URL'
if ($url) {
    Write-Host "Selected URL: $url" -ForegroundColor Green
    exit 0
}
Write-Host 'Dialog cancelled.' -ForegroundColor Yellow
exit 1
