<#
.SYNOPSIS
Downloads and runs the Windows OOBE setup scripts from the GitHub repo.

.DESCRIPTION
This script downloads the raw versions of setup-oobe.ps1 and decrap.ps1 from GitHub
into a temporary folder, then executes setup-oobe.ps1. The setup script will then invoke
local decrap.ps1 from the same folder.

USAGE
Paste this into an elevated PowerShell prompt and run it.
#>

param (
    [string]$Repository = 'CatFlowers28g/Windows-OOBE-Automator',
    [string]$Branch = 'main'
)

$baseUrl = "https://raw.githubusercontent.com/$Repository/$Branch"
$scripts = @(
    'setup-oobe.ps1',
    'decrap.ps1'
)

try {
    $tempFolder = Join-Path -Path $env:TEMP -ChildPath "Windows-OOBE-Automator-$(Get-Random)"
    New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null

    foreach ($script in $scripts) {
        $url = "$baseUrl/$script"
        $destination = Join-Path -Path $tempFolder -ChildPath $script

        Write-Host "Downloading $script from $url..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing -ErrorAction Stop
    }

    Write-Host "Downloaded scripts to $tempFolder" -ForegroundColor Green
    Write-Host "Running setup-oobe.ps1..." -ForegroundColor Green

    $setupScript = Join-Path -Path $tempFolder -ChildPath 'setup-oobe.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript
}
catch {
    Write-Error "Failed to download or run scripts: $_"
}
finally {
    if ($tempFolder -and (Test-Path $tempFolder)) {
        Write-Host "Cleaning up temporary folder..." -ForegroundColor Yellow
        Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}
