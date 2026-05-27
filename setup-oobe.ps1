# Requires administrative privileges
# Run from an elevated PowerShell prompt instead of double-clicking the .ps1 file.
# Example: powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\setup-oobe.ps1"
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

# Allow this script to run without changing the system-wide execution policy
Set-ExecutionPolicy Bypass -Scope Process -Force

# Configure timezone and synchronize time
Set-TimeZone -Name "Central Standard Time"
w32tm /resync



# Disable standby on AC and DC power
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0

# Run Decrapifier from the same folder as this script
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$decrapScript = Join-Path $scriptDirectory 'decrap.ps1'
if (Test-Path $decrapScript) {
    Write-Host "Running Decrapifier..."
    Push-Location $scriptDirectory
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        . $decrapScript -AppsOnly -ClearStart -OneDrive
    } finally {
        Pop-Location
    }
} else {
    Write-Warning "Could not find decrap.ps1 in $scriptDirectory. Skipping decrapifier step."
}

# Install applications using winget
$packages = @(
    'Google.Chrome',
    'Mozilla.Firefox',
    'Adobe.Acrobat.Reader.64-bit',
    'Microsoft.Office',
    'Microsoft.Teams',
    'Zoom.Zoom'
)

foreach ($package in $packages) {
    Write-Host "Installing $package..."
    winget install --id $package -e --silent --accept-package-agreements --accept-source-agreements
}

# Trigger Windows System Updates
Write-Host "Checking for and installing Windows System Updates..."
$usoCmd = Get-Command UsoClient.exe -ErrorAction SilentlyContinue
if ($usoCmd) {
    $usoClient = $usoCmd.Source
} else {
    $usoClient = Join-Path $env:WINDIR 'System32\UsoClient.exe'
}
if (Test-Path $usoClient) {
    Start-Process -FilePath $usoClient -ArgumentList "StartScan" -NoNewWindow -Wait
    Start-Process -FilePath $usoClient -ArgumentList "StartDownload" -NoNewWindow -Wait
    Start-Process -FilePath $usoClient -ArgumentList "StartInstall" -NoNewWindow -Wait
} else {
    Write-Warning "UsoClient.exe not found; skipping Windows Update commands."
}

# Notes:
# - The computer will restart after Rename-Computer. If you want the script to continue installing apps before restart,
#   move Rename-Computer to the end and remove -Restart from the Rename-Computer call.
# - "decrap" operations are not defined in this script. Add cleanup commands here if needed.
# - A restart is already triggered by Rename-Computer above.
