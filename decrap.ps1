#Windows 11 Onboarding Decrapifier - SYSTEM component (Datto RMM)
#v1.0 - Windows 11
#
#Runs as SYSTEM from a Datto RMM component. Does everything that is correct in machine context:
#  - Removes pre-installed UWP apps (Appx + provisioned), keeping a safe list
#  - Seeds the DEFAULT user profile hive (privacy + Start) so NEW profiles inherit clean settings
#  - Leaves OneDrive alone (onboarding SOP)
#  - Stages the per-user finisher into C:\Users\Public\Documents for the technician to double-click
#
#Per-user (HKCU) settings for the CURRENT onboarding account are intentionally NOT done here - under SYSTEM,
#HKCU is SYSTEM's own hive. Those are applied by Finish-Decrapifier.cmd, run by the tech in the user's session,
#where the tech picks New/Redeploy mode and can override individual options.
#
#ATTACH to this component:  Finish-Decrapifier.ps1  and  Finish-Decrapifier.cmd
#
#COMPONENT VARIABLES: none. This component is purpose-built for onboarding and takes no input.

$ErrorActionPreference = "Stop"

#--Windows 11 guard (build 22000 = W11 21H2)--
$osBuild = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' CurrentBuildNumber -ErrorAction SilentlyContinue).CurrentBuildNumber
if ($osBuild -and $osBuild -lt 22000) {
    Write-Host "<-Start Result->"
    Write-Host "STATUS=ABORT: Windows 11 required (detected build $osBuild)."
    Write-Host "<-End Result->"
    exit 1
}

#--Force 64-bit (Datto agent is 32-bit; Appx + HKLM need native context)--
if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64" -and -not [Environment]::Is64BitProcess) {
    & "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe" -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

#------USER EDITABLE VARIABLES------
$GoodApps = "calculator|camera|store|windows.photos|soundrecorder|mspaint|microsoft.paint|windowsnotepad|screensketch|snippingtool|Dell|Lenovo|HP.|windowsterminal"

$StartLayoutJson = @'
{
  "pinnedList": []
}
'@

$StageDir = "$env:PUBLIC\Documents\Decrapifier"
#------End editable variables------

$script:reglocation = $null
$appRemoved = 0
$appFail    = 0
$staged     = $false

Function RemoveApps {
    $SafeApps = "AAD.brokerplugin|AccountsControl|apprep.chxapp|AssignedAccess|AsyncTextService|BioEnrollment|CapturePicker|CloudExperienceHost|ContentDeliveryManager|CrossDevice|DesktopAppInstaller|ECApp|Edge|Extension|GetStarted|ImmersiveControlPanel|LockApp|NarratorQuickStart|Native|NcsiUwpApp|OOBENetworkCaptivePortal|OOBENetworkConnectionFlow|ParentalControls|PeopleExperienceHost|PinningConfirmationDialog|PPIProjection|SecHealthUI|SecureAssessmentBrowser|ShellExperienceHost|StartExperiencesApp|StartMenuExperienceHost|UI.Xaml|VCLibs|Wallet|WebExperience|Win32WebViewHost|WindowsAppRuntime|Windows.CBSPreview|Update|XboxGameCallableUI|XGpuEject"
    $SafeApps = "$SafeApps|$GoodApps"
    $RemoveApps   = Get-AppxPackage -allusers | Where-Object { $_.name -notmatch $SafeApps }
    $RemovePrApps = Get-AppxProvisionedPackage -online | Where-Object {$_.displayname -notmatch $SafeApps}
    ForEach ($a in $RemoveApps) {
        try {
            # Skip packages installed under SystemApps or those marked as framework/system-signed
            $systemAppsPath = Join-Path $env:WINDIR 'SystemApps'
            if ($a.InstallLocation -and ($a.InstallLocation -like "$systemAppsPath*")) {
                Write-Host "Skipping system-protected app (InstallLocation): $($a.Name) at $($a.InstallLocation)"
                continue
            }
            if ($a.IsFramework) {
                Write-Host "Skipping framework package: $($a.Name)"
                continue
            }

            Write-Host "Removing app package: $($a.Name) (PackageFullName: $($a.PackageFullName))"
            Remove-AppxPackage -package $a.PackageFullName -allusers -ErrorAction Stop
            $script:appRemoved++
        } catch {
            $errorText = $_.ToString()
            if ($errorText -match '0x80070032') {
                Write-Warning "Unsupported per-user removal for package $($a.PackageFullName): $errorText"
                $fallbackRemoved = $false
                try {
                    Write-Host "Attempting local removal for $($a.PackageFullName)..."
                    Remove-AppxPackage -package $a.PackageFullName -ErrorAction Stop
                    Write-Host "Local removal succeeded for $($a.PackageFullName)."
                    $script:appRemoved++
                    $fallbackRemoved = $true
                } catch {
                    Write-Warning "Local removal failed for $($a.PackageFullName): $_"
                }

                if (-not $fallbackRemoved -and $a.PackageFamilyName) {
                    try {
                        Write-Host "Attempting provisioned package cleanup for family $($a.PackageFamilyName)..."
                        $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like "*$($a.PackageFamilyName)*" }
                        if ($prov) {
                            foreach ($entry in $prov) {
                                try {
                                    Remove-AppxProvisionedPackage -Online -PackageName $entry.PackageName -ErrorAction Stop
                                    Write-Host "Removed provisioned entry: $($entry.PackageName)"
                                    $script:appRemoved++
                                } catch {
                                    Write-Warning "Provisioned entry removal failed for $($entry.PackageName): $_"
                                }
                            }
                            if ($prov) { $fallbackRemoved = $true }
                        }
                    } catch {
                        Write-Warning "Provisioned cleanup failed for $($a.PackageFamilyName): $_"
                    }
                }

                # Only attempt DISM removal for non-system packages (some system apps are protected)
                if (-not $fallbackRemoved) {
                    $canAttemptDism = $true
                    if ($a.InstallLocation -and ($a.InstallLocation -like "$systemAppsPath*")) {
                        $canAttemptDism = $false
                        Write-Host "Skipping DISM fallback for system-protected package: $($a.PackageFullName)"
                    }
                    if ($canAttemptDism) {
                        try {
                            Write-Host "Attempting DISM removal for $($a.PackageFullName)..."
                            $dismOut = & dism /Online /Remove-ProvisionedAppxPackage /PackageName:$($a.PackageFullName) 2>&1
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "DISM removal succeeded for $($a.PackageFullName)."
                                $script:appRemoved++
                                $fallbackRemoved = $true
                            } else {
                                Write-Warning "DISM removal reported failure for $($a.PackageFullName): $dismOut"
                            }
                        } catch {
                            Write-Warning "DISM removal failed for $($a.PackageFullName): $_"
                        }
                    }
                }

                if (-not $fallbackRemoved) {
                    Write-Warning "Could not remove package $($a.PackageFullName)."
                    $script:appFail++
                }
            } else {
                Write-Warning "Failed to remove package $($a.PackageFullName): $errorText"
                $script:appFail++
            }
        }
    }
    ForEach ($p in $RemovePrApps) {
        $pkgName = $p.PackageName
        $display = $p.DisplayName
        Write-Host "Handling provisioned app: $display ($pkgName)"
        # Verify the provisioned package still exists before attempting removal
        $exists = Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -eq $pkgName }
        if (-not $exists) {
            Write-Host "Provisioned package not present or already removed: $pkgName. Skipping."
            continue
        }

        try {
            Remove-AppxProvisionedPackage -online -packagename $pkgName -ErrorAction Stop
            Write-Host "Removed provisioned package: $pkgName"
            $script:appRemoved++
        } catch {
            $err = $_.ToString()
            Write-Warning "Remove-AppxProvisionedPackage failed for $pkgName: $err"
            # Try DISM fallback for provisioned packages
            try {
                Write-Host "Attempting DISM fallback for provisioned package: $pkgName"
                $dismOut = & dism /Online /Remove-ProvisionedAppxPackage /PackageName:$pkgName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "DISM removal succeeded for provisioned package: $pkgName"
                    $script:appRemoved++
                } else {
                    Write-Warning "DISM removal failed for provisioned package $pkgName: $dismOut"
                    $script:appFail++
                }
            } catch {
                Write-Warning "DISM exception for $pkgName: $_"
                $script:appFail++
            }
        }
    }
}

Function LoadDefaultHive {
    $dp = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' Default).Default
    reg load "$reglocation" "$dp\ntuser.dat" | Out-Null
}

Function UnloadDefaultHive {
    [gc]::Collect(); [gc]::WaitForPendingFinalizers()
    $t = 0
    do { Start-Sleep -Milliseconds 500; reg unload "$reglocation" 2>$null; $t++ }
    until ($LASTEXITCODE -eq 0 -or $t -ge 6)
    if ($LASTEXITCODE -ne 0) { Write-Host "WARN: default hive failed to unload after $t tries" }
}

#Seed the DEFAULT profile hive so NEW profiles inherit clean privacy + suggestions off.
Function SeedDefaultHive {
    $script:reglocation = "HKLM\AllProfile"
    Write-Host "***Seeding default NTUSER.DAT for new profiles...***"
    LoadDefaultHive
    $r = $reglocation
    #Content delivery / suggestions
    Reg Add "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /T REG_DWORD /V "SystemPaneSuggestionsEnabled" /D 0 /F
    Reg Add "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /T REG_DWORD /V "SilentInstalledAppsEnabled" /D 0 /F
    Reg Add "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /T REG_DWORD /V "PreInstalledAppsEnabled" /D 0 /F
    Reg Add "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /T REG_DWORD /V "OEMPreInstalledAppsEnabled" /D 0 /F
    Reg Add "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /T REG_DWORD /V "SubscribedContentEnabled" /D 0 /F
    Reg Add "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /T REG_DWORD /V "RotatingLockScreenOverlayEnabled" /D 0 /F
    Reg Add "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /T REG_DWORD /V "Start_IrisRecommendations" /D 0 /F
    #Privacy
    Reg Add "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /T REG_DWORD /V "Enabled" /D 0 /F
    Reg Add "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" /T REG_DWORD /V "TailoredExperiencesWithDiagnosticDataEnabled" /D 0 /F
    Reg Add "$r\SOFTWARE\Microsoft\Siuf\Rules" /T REG_DWORD /V "NumberOfSIUFInPeriod" /D 0 /F
    #Taskbar
    Reg Add "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /T REG_DWORD /V "TaskbarDa" /D 0 /F
    Reg Add "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /T REG_DWORD /V "ShowCopilotButton" /D 0 /F
    UnloadDefaultHive
    $script:reglocation = $null
}

#Clean default Start layout for new profiles (W11 uses LayoutModification.json).
Function SeedDefaultStart {
    Write-Host "***Setting clean Start layout for new profiles...***"
    $dp = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' Default -ErrorAction SilentlyContinue).Default
    if (-not $dp) { $dp = "$env:SYSTEMDRIVE\Users\Default" }
    $shell = Join-Path $dp "AppData\Local\Microsoft\Windows\Shell"
    if (-not (Test-Path $shell)) { New-Item -ItemType Directory -Path $shell -Force | Out-Null }
    Set-Content -Path (Join-Path $shell "LayoutModification.json") -Value $StartLayoutJson -Encoding UTF8 -Force
}

#Stage the per-user finisher + record the mode for it to inherit.
Function StageFinisher {
    Write-Host "***Staging per-user finisher to $StageDir...***"
    if (-not (Test-Path $StageDir)) { New-Item -ItemType Directory -Path $StageDir -Force | Out-Null }

    $srcDir = (Get-Location).Path
    $files  = @("Finish-Decrapifier.ps1","Finish-Decrapifier.cmd")
    $missing = @()
    foreach ($f in $files) {
        $src = Join-Path $srcDir $f
        if (-not (Test-Path $src)) { $src = Join-Path $PSScriptRoot $f }
        if (Test-Path $src) { Copy-Item $src (Join-Path $StageDir $f) -Force }
        else { $missing += $f }
    }
    if ($missing.Count -gt 0) {
        Write-Host "WARN: missing attachment(s): $($missing -join ', '). Attach them to the component."
        return $false
    }

    #Folder ACL: users read+run, only admins/SYSTEM write.
    icacls "$StageDir" /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" "Users:(OI)(CI)RX" | Out-Null
    return $true
}

#---Run---
Write-Host "******Onboarding Decrapifier (SYSTEM)******"
RemoveApps
SeedDefaultHive
SeedDefaultStart
$staged = StageFinisher

$exit = 0
if ($appFail -gt 0 -or -not $staged) { $exit = 1 }

Write-Host "<-Start Result->"
Write-Host "STATUS=Apps removed: $appRemoved | App failures: $appFail | Finisher staged: $staged | Tech: run Finish-Decrapifier.cmd from Public Documents as the user account"
Write-Host "<-End Result->"
exit $exit