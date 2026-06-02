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

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    # Ignore if unsupported in older PowerShell versions
}

$rawBaseUrl = "https://raw.githubusercontent.com/$Repository/$Branch"
$githubRawUrl = "https://github.com/$Repository/raw/$Branch"
$scripts = @(
    'setup-oobe.ps1',
    'decrap.ps1'
)

function Download-ScriptFromWeb {
    param (
        [string]$ScriptName,
        [string]$DestinationPath
    )

    $urls = @(
        "$rawBaseUrl/$ScriptName",
        "$githubRawUrl/$ScriptName"
    )

    foreach ($url in $urls) {
        Write-Host "Attempting download of $ScriptName from $url..." -ForegroundColor Cyan
        try {
            Invoke-WebRequest -Uri $url -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
            Write-Host "Downloaded $ScriptName from $url" -ForegroundColor Green
            return
        }
        catch {
            Write-Warning "Failed to download $ScriptName from $url: $_"
        }
    }

    throw "Unable to download $ScriptName from any known URL."
}

try {
    $tempFolder = Join-Path -Path $env:TEMP -ChildPath "Windows-OOBE-Automator-$(Get-Random)"
    New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null

    foreach ($script in $scripts) {
        $destination = Join-Path -Path $tempFolder -ChildPath $script
        Download-ScriptFromWeb -ScriptName $script -DestinationPath $destination
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
