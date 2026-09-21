# Requires administrative privileges
# Run from an elevated PowerShell prompt instead of double-clicking the .ps1 file.
# Example: powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\setup-oobe.ps1"
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}


# Allow this script to run without changing the system-wide execution policy
Write-Host "=== Starting Windows OOBE automation ===" -ForegroundColor Green
Write-Host "Current directory: $($MyInvocation.MyCommand.Path)"
Set-ExecutionPolicy Bypass -Scope Process -Force

# Start a transcript so the entire script output is captured to a file for later review.
try {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not (Test-Path $desktop)) { $desktop = Join-Path $env:PUBLIC 'Desktop' }
    $Script:TranscriptPath = Join-Path $desktop ("setup-oobe_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt")
    Start-Transcript -Path $Script:TranscriptPath -Force -ErrorAction SilentlyContinue
    Write-Host "Transcript started: $Script:TranscriptPath"
} catch {
    Write-Warning "Failed to start transcript: $_"
}


# Configure winget settings to bypass certificate pinning
Write-Host "`nConfiguring winget settings..." -ForegroundColor Cyan
winget settings --enable BypassCertificatePinningForMicrosoftStore



# Attempt to join the Wi-Fi network as the very first action
Write-Host "`n[0/3] Joining Wi‑Fi network 'Syand Service'..." -ForegroundColor Cyan
try {
    # If an active Ethernet connection is present, skip trying to join Wi‑Fi.
    $hasEthernet = $false
    try {
        $physicalAdapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue
        if ($physicalAdapters) {
            foreach ($ad in $physicalAdapters | Where-Object { $_.Status -eq 'Up' }) {
                if ($ad.InterfaceDescription -match 'Ethernet' -or $ad.Name -match 'Ethernet' -or ($ad.MediaType -eq '802.3' -or ($null -ne $ad.LinkSpeed -and $ad.LinkSpeed -gt 0))) {
                    $hasEthernet = $true
                    break
                }
            }
        }
    } catch {
        # If detection fails, conservatively assume no ethernet so Wi‑Fi attempt can proceed.
        $hasEthernet = $false
    }

    if ($hasEthernet) {
        Write-Host "Ethernet connection detected; skipping Wi‑Fi join step." -ForegroundColor Cyan
    } else {
        $ssid = "Syand Service"
        $password = "ilovefiber!"
        # Optional timeout (seconds). If not set or set to 0, wait indefinitely until connected.
        $timeout = 0
        if ($env:WIFI_JOIN_TIMEOUT) {
            [int]$timeout = [int]$env:WIFI_JOIN_TIMEOUT
        }

        $profileXml = @"
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$ssid</name>
    <SSIDConfig>
        <SSID>
            <name>$ssid</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$password</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@
        $tempProfile = Join-Path $env:TEMP "wifi_profile.xml"
        $profileXml | Out-File -FilePath $tempProfile -Encoding ascii
        netsh wlan add profile filename="$tempProfile" user=current | Out-Null
        netsh wlan connect name="$ssid" ssid="$ssid" | Out-Null

        # Wait until connected to the specified SSID before continuing.
        $start = Get-Date
        Write-Host "Waiting for connection to '$ssid'..."
        while ($true) {
            try {
                $iface = netsh wlan show interfaces 2>$null | Out-String
                $isConnected = $false
                if ($iface -match "State\s*:\s*(?<state>\w+)") { $state = $Matches['state'] } else { $state = "" }
                if ($iface -match "SSID\s*:\s*(?<ssid>.+)") { $currentSsid = $Matches['ssid'].Trim() } else { $currentSsid = "" }
                if ($state -ieq "connected" -and $currentSsid -eq $ssid) { $isConnected = $true }
                if ($isConnected) { Write-Host "Connected to $ssid"; break }
            } catch {
                Write-Warning "Error checking Wi‑Fi state: $_"
            }

            if ($timeout -gt 0) {
                $elapsed = (Get-Date) - $start
                if ($elapsed.TotalSeconds -ge $timeout) {
                    Write-Warning "Timeout ($timeout s) reached waiting for Wi‑Fi connection to $ssid. Exiting to avoid continuing without network."
                    exit 1
                }
            }

            Write-Host "Still waiting for $ssid..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }

        # Clean up profile file
        Remove-Item -Path $tempProfile -ErrorAction SilentlyContinue
    }
} catch {
    Write-Warning "Wi-Fi join warning: $_"
    exit 1
}




# Configure timezone and synchronize time
Write-Host "`n[1/3] Configuring timezone and synchronizing time..." -ForegroundColor Cyan
try {
    $currentTZ = (Get-TimeZone).DisplayName
    Write-Host "Current timezone: $currentTZ"
    Set-TimeZone -Name "Central Standard Time" -ErrorAction Stop
    Write-Host "Timezone set to Central Standard Time"
    
    # Ensure Windows Time service is running before attempting resync
    Write-Host "Checking Windows Time service..."
    $timeService = Get-Service -Name "W32Time" -ErrorAction SilentlyContinue
    if ($timeService) {
        if ($timeService.Status -ne "Running") {
            Write-Host "Starting Windows Time service..."
            Start-Service -Name "W32Time" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        Write-Host "Running w32tm resync..."
        w32tm /resync
        Write-Host "Time synced successfully"
    } else {
        Write-Warning "Windows Time service not found; skipping time sync"
    }
} catch {
    Write-Warning "Timezone/time sync warning: $_"
}




# Disable standby on AC and DC power
Write-Host "`n[2/3] Disabling standby and display timeout on AC and DC power..." -ForegroundColor Cyan
try {
    Write-Host "Disabling AC standby (plugged in)..."
    powercfg /change standby-timeout-ac 0
    Write-Host "Disabling DC standby (on battery)..."
    powercfg /change standby-timeout-dc 0
    
    Write-Host "Disabling AC display timeout (plugged in)..."
    powercfg /change monitor-timeout-ac 0
    Write-Host "Disabling DC display timeout (on battery)..."
    powercfg /change monitor-timeout-dc 0
    
    Write-Host "Power settings configured: Never sleep, never turn off display"
} catch {
    Write-Warning "Power configuration warning: $_"
}




Write-Host "`n[3/3] Preparing to run Decrapifier..." -ForegroundColor Cyan

# Run Decrapifier from the same folder as this script in the current PowerShell session
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$decrapScript = Join-Path $scriptDirectory 'decrap.ps1'
if (Test-Path $decrapScript) {
    Write-Host "Running Decrapifier..."
    Push-Location $scriptDirectory
    try {
        Write-Host "Invoking decrap.ps1 in the same PowerShell session..."
        & $decrapScript -AppsOnly -ClearStart -OneDrive
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Decrapifier exited with code $LASTEXITCODE."
        }
    } catch {
        Write-Warning "Failed to run decrap.ps1: $_"
    } finally {
        Pop-Location
    }
} else {
    Write-Warning "Could not find decrap.ps1 in $scriptDirectory. Skipping decrapifier step."
}
# Remove Lenovo Vantage (main culprit for rewards prompts)
Get-AppxPackage *LenovoVantage* | Remove-AppxPackage -ErrorAction SilentlyContinue

# Remove Lenovo Welcome / Experience apps (varies by model)
Get-AppxPackage *Lenovo* | Where-Object {
    $_.Name -match "Welcome|Experience|Companion"
} | Remove-AppxPackage -ErrorAction SilentlyContinue

# Remove provisioned versions (prevents reappearing for new users)
Get-AppxProvisionedPackage -Online | Where-Object {
    $_.DisplayName -match "Lenovo"
} | ForEach-Object {
    Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue
}



# Install applications using winget
$packages = @(
    'Google.Chrome',
    'Mozilla.Firefox',
    'Adobe.Acrobat.Reader.64-bit',
    'Microsoft.Teams',
    'Zoom.Zoom',
    'Google.GoogleDrive',
    'Microsoft.Office'

)

foreach ($package in $packages) {
    Write-Host "Installing $package for all users..."
    winget install --id $package -e --silent --scope machine --accept-package-agreements --accept-source-agreements
}

# Stop the transcript and report location
try {
    Stop-Transcript -ErrorAction SilentlyContinue
    if ($Script:TranscriptPath) { Write-Host "Full run log saved to: $Script:TranscriptPath" }
} catch {
    Write-Warning "Failed to stop transcript: $_"
}


