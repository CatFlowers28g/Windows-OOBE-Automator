# Onboarding Decrapifier - Per-User Finisher (technician double-click)
# v2.1 - Windows 11
#
# Run by the technician AS THE USER ACCOUNT being handed to the end user (do NOT run elevated as an admin -
# that would apply settings to the admin's profile, not the user's). Launched via Finish-Decrapifier.cmd.
#
# Execution policy: the .cmd launches this with -ExecutionPolicy Bypass (per-process). Nothing changes the
# machine policy, so there is no Set-ExecutionPolicy step to undo.
#
# Scope: the per-user pieces of the onboarding SOP (decrap.ps1 -appsonly -clearstart -onedrive [-tablet]) plus an
# optional cleanup set the tech can opt into. App removal already ran as SYSTEM. Idempotent - safe to re-run.
#
# Device toggle preselects the SOP options; optional cleanup is off by default. Tech can override anything.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch {}
try { [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch {}

$ScriptDir = Split-Path -Parent $PSCommandPath
$LogFile   = Join-Path $ScriptDir ("finish-{0}-{1:yyyyMMdd-HHmmss}.log" -f $env:USERNAME, (Get-Date))

# Device presets -> SOP option checkboxes.
$DevicePresets = @{
    "Desktop" = @{ ClearStart=$true; RemoveOD=$false; Tablet=$false }
    "Tablet"  = @{ ClearStart=$true; RemoveOD=$false; Tablet=$true  }
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$isAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

#--Theme--
$clBg     = [System.Drawing.Color]::FromArgb(245,247,250)
$clCard   = [System.Drawing.Color]::White
$clText   = [System.Drawing.Color]::FromArgb(32,38,45)
$clMuted  = [System.Drawing.Color]::FromArgb(110,120,130)
$clAccent = [System.Drawing.Color]::FromArgb(0,120,140)   # teal, matches SYAND branding
$clAccentT= [System.Drawing.Color]::White
$fRegular = New-Object System.Drawing.Font("Segoe UI",9.5)
$fBold    = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)
$fHead    = New-Object System.Drawing.Font("Segoe UI Semibold",13)
$fMono    = New-Object System.Drawing.Font("Consolas",9)

$tip = New-Object System.Windows.Forms.ToolTip
$tip.AutoPopDelay = 15000; $tip.InitialDelay = 350; $tip.ReshowDelay = 150

$form = New-Object System.Windows.Forms.Form
$form.Text = "Onboarding Finisher"
$form.ClientSize = New-Object System.Drawing.Size(620,700)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = $clBg
$form.Font = $fRegular

function Card($x,$y,$w,$h) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x,$y)
    $p.Size = New-Object System.Drawing.Size($w,$h)
    $p.BackColor = $clCard
    $form.Controls.Add($p); return $p
}
function SectionTitle($parent,$text,$x,$y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Font = $fBold; $l.ForeColor = $clAccent
    $l.Location = New-Object System.Drawing.Point($x,$y); $l.AutoSize = $true
    $parent.Controls.Add($l); return $l
}

#--Header--
$hd = New-Object System.Windows.Forms.Label
$hd.Text = "Onboarding Finisher"; $hd.Font = $fHead; $hd.ForeColor = $clText
$hd.Location = New-Object System.Drawing.Point(24,18); $hd.AutoSize = $true
$form.Controls.Add($hd)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = "Per-user finishing for the current account ($($env:USERNAME)). App removal already ran from RMM."
$sub.Font = $fRegular; $sub.ForeColor = $clMuted
$sub.Location = New-Object System.Drawing.Point(24,48); $sub.Size = New-Object System.Drawing.Size(575,20)
$form.Controls.Add($sub)

#--Device card--
$cardDev = Card 20 80 580 74
SectionTitle $cardDev "Device type" 18 12 | Out-Null
$rbDesktop = New-Object System.Windows.Forms.RadioButton
$rbDesktop.Text = "Desktop / Laptop"; $rbDesktop.Font = $fRegular; $rbDesktop.ForeColor = $clText
$rbDesktop.Location = New-Object System.Drawing.Point(20,40); $rbDesktop.Size = New-Object System.Drawing.Size(200,24); $rbDesktop.Checked = $true
$cardDev.Controls.Add($rbDesktop)
$tip.SetToolTip($rbDesktop, "Standard machine. Sensors/location restricted (equivalent to running without -tablet).")
$rbTablet = New-Object System.Windows.Forms.RadioButton
$rbTablet.Text = "Tablet / Touchscreen"; $rbTablet.Font = $fRegular; $rbTablet.ForeColor = $clText
$rbTablet.Location = New-Object System.Drawing.Point(260,40); $rbTablet.Size = New-Object System.Drawing.Size(240,24)
$cardDev.Controls.Add($rbTablet)
$tip.SetToolTip($rbTablet, "Touch device. Leaves location/sensors enabled (equivalent to -tablet).")

#--Onboarding (SOP) card--
$cardSop = Card 20 168 580 150
SectionTitle $cardSop "Onboarding (standard)" 18 12 | Out-Null
function SopChk($text,$y,$tiptext) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $text; $c.Font = $fRegular; $c.ForeColor = $clText
    $c.Location = New-Object System.Drawing.Point(20,$y); $c.Size = New-Object System.Drawing.Size(545,28)
    $cardSop.Controls.Add($c); $tip.SetToolTip($c,$tiptext); return $c
}
$chkClearStart = SopChk "Clear Start menu   (checked = empty this user's Start; unchecked = leave as-is)" 40 `
    "Checked: removes all pinned tiles from this user's Start, leaving the All apps list. Unchecked: leaves the current Start layout untouched."
$chkRemoveOD   = SopChk "Remove OneDrive   (checked = unpin + disable auto-start; unchecked = leave alone)" 74 `
    "Checked: unpins OneDrive from File Explorer and stops it auto-starting for THIS user (does not uninstall). Unchecked: leaves OneDrive as-is. SOP default is UNCHECKED."
$chkTablet     = SopChk "Tablet mode   (checked = leave location/sensors ENABLED; unchecked = restrict)" 108 `
    "Checked: leaves location/sensors enabled for touch devices (-tablet). Unchecked: restricts them. Set by the device type above."

$optMap = @{ ClearStart=$chkClearStart; RemoveOD=$chkRemoveOD; Tablet=$chkTablet }
function ApplyPreset($dev) { $p = $DevicePresets[$dev]; foreach ($k in $p.Keys) { $optMap[$k].Checked = $p[$k] } }
$rbDesktop.Add_CheckedChanged({ if ($rbDesktop.Checked) { ApplyPreset "Desktop" } })
$rbTablet.Add_CheckedChanged({ if ($rbTablet.Checked) { ApplyPreset "Tablet" } })
ApplyPreset "Desktop"

#--Optional cleanup card--
$cardOpt = Card 20 332 580 196
SectionTitle $cardOpt "Optional cleanup (off by default)" 18 12 | Out-Null
function OptChk($text,$x,$y,$tiptext) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $text; $c.Font = $fRegular; $c.ForeColor = $clText
    $c.Location = New-Object System.Drawing.Point($x,$y); $c.Size = New-Object System.Drawing.Size(275,26)
    $cardOpt.Controls.Add($c); $tip.SetToolTip($c,$tiptext); return $c
}
$chkContent = OptChk "Suggested content / ads off" 20 42 `
    "Turns off Start/Settings suggestions, Spotlight lock-screen ads, silently-installed 'recommended' apps, and File Explorer sync-provider ads."
$chkPrivacy = OptChk "Privacy & personalization" 300 42 `
    "Disables advertising ID, tailored experiences from diagnostic data, feedback prompts, shared experiences, and implicit inking/typing data collection."
$chkTaskbar = OptChk "Taskbar / Copilot cleanup" 20 74 `
    "Removes the Widgets, Chat, and Copilot taskbar buttons, sets search to icon-only, and disables Autoplay."
$chkSearch  = OptChk "Web / Copilot search off" 300 74 `
    "Turns off Bing/web results and Copilot suggestions in the Start search box. Local file/app search still works."
$chkPerms   = OptChk "App permissions restricted" 20 106 `
    "Sets camera, mic, contacts, calendar, email, call history, messaging, and file-library access to Deny by default, and disables background apps."
$chkGameDVR = OptChk "Game DVR off" 300 106 `
    "Disables Game Bar background recording (Game DVR) for this user."

#--Output--
$out = New-Object System.Windows.Forms.TextBox
$out.Multiline = $true; $out.ScrollBars = "Vertical"; $out.ReadOnly = $true
$out.Location = New-Object System.Drawing.Point(20,542); $out.Size = New-Object System.Drawing.Size(580,110)
$out.Font = $fMono; $out.BackColor = [System.Drawing.Color]::FromArgb(250,251,252); $out.BorderStyle = "FixedSingle"
$form.Controls.Add($out)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Apply"; $btnRun.Font = $fBold
$btnRun.Location = New-Object System.Drawing.Point(20,662); $btnRun.Size = New-Object System.Drawing.Size(130,30)
$btnRun.FlatStyle = "Flat"; $btnRun.FlatAppearance.BorderSize = 0
$btnRun.BackColor = $clAccent; $btnRun.ForeColor = $clAccentT
$form.Controls.Add($btnRun)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"; $btnClose.Font = $fRegular
$btnClose.Location = New-Object System.Drawing.Point(470,662); $btnClose.Size = New-Object System.Drawing.Size(130,30)
$btnClose.FlatStyle = "Flat"; $btnClose.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200,206,212)
$btnClose.BackColor = $clCard; $btnClose.ForeColor = $clText
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

function Log([string]$m) {
    $out.AppendText($m + "`r`n"); $out.SelectionStart = $out.Text.Length; $out.ScrollToCaret()
    try { Add-Content -Path $LogFile -Value $m -ErrorAction SilentlyContinue } catch {}
    [System.Windows.Forms.Application]::DoEvents()
}
function RegW($Path,$Type,$Name,$Data) { Reg Add "$Path" /T $Type /V "$Name" /D $Data /F | Out-Null }

if ($isAdmin) { Log "WARNING: running elevated - changes apply to THIS account ($($env:USERNAME)). If that isn't the end-user account, close and re-run as the correct user (not elevated)."; Log "" }

$btnRun.Add_Click({
    $btnRun.Enabled = $false
    $dev = if ($rbTablet.Checked) { "Tablet" } else { "Desktop" }
    Log "=== Applying | device: $dev | user: $($env:USERNAME) ==="
    $r = "HKCU"

    # -- SOP options --
    if ($chkClearStart.Checked) {
        $shell = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Shell"
        if (-not (Test-Path $shell)) { New-Item -ItemType Directory -Path $shell -Force | Out-Null }
        Set-Content -Path (Join-Path $shell "LayoutModification.json") -Value '{ "pinnedList": [] }' -Encoding UTF8 -Force

        # LayoutModification.json is only read the FIRST time Start initializes for a profile.
        # Once a profile has signed in, pinned tiles live in a cached binary database
        # (start2.bin, under the StartMenuExperienceHost package). Overwriting the json alone
        # is a no-op at that point, so clear the cache and restart Explorer/Start to force a reseed.
        try {
            Get-Process -Name StartMenuExperienceHost,ShellExperienceHost -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            $smehState = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState"
            if (Test-Path $smehState) {
                Get-ChildItem -Path $smehState -Filter "start2*.bin" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            }
            Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            Start-Process explorer.exe
            Log "Clear Start menu: DONE (Start cache reset - pinned tiles cleared immediately)"
        } catch {
            Log "Clear Start menu: layout written, but cache reset failed ($_) - sign out/in to apply"
        }
    } else { Log "Clear Start menu: skipped" }

    if ($chkRemoveOD.Checked) {
        RegW "$r\SOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" REG_DWORD "System.IsPinnedToNameSpaceTree" 0
        Reg Delete "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /V "OneDrive" /F 2>$null | Out-Null
        Log "Remove OneDrive: DONE (per-user)"
    } else { Log "Remove OneDrive: skipped (left alone)" }

    if ($chkTablet.Checked) {
        Log "Tablet mode: location/sensors left ENABLED"
    } else {
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" REG_SZ "Value" "Deny"
        RegW "$r\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Permissions\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" REG_DWORD "SensorPermissionState" 0
        Log "Tablet mode: location/sensors RESTRICTED"
    }

    # -- Optional cleanup --
    if ($chkContent.Checked) {
        foreach ($v in "SystemPaneSuggestionsEnabled","SubscribedContent-338393Enabled","SubscribedContent-353694Enabled","SubscribedContent-338388Enabled","SoftLandingEnabled","RotatingLockScreenEnabled","RotatingLockScreenOverlayEnabled","PreInstalledAppsEnabled","PreInstalledAppsEverEnabled","OEMPreInstalledAppsEnabled","SilentInstalledAppsEnabled","ContentDeliveryAllowed","SubscribedContentEnabled","SubscribedContent-310093Enabled","SubscribedContent-338389Enabled") {
            RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" REG_DWORD $v 0
        }
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" REG_DWORD "ShowSyncProviderNotifications" 0
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" REG_DWORD "Start_IrisRecommendations" 0
        Log "Suggested content / ads: off"
    }
    if ($chkPrivacy.Checked) {
        RegW "$r\SOFTWARE\Microsoft\Siuf\Rules" REG_DWORD "NumberOfSIUFInPeriod" 0
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" REG_DWORD "Enabled" 0
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" REG_DWORD "TailoredExperiencesWithDiagnosticDataEnabled" 0
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\CDP" REG_DWORD "RomeSdkChannelUserAuthzPolicy" 0
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\CDP" REG_DWORD "CdpSessionUserAuthzPolicy" 0
        RegW "$r\SOFTWARE\Microsoft\InputPersonalization" REG_DWORD "RestrictImplicitTextCollection" 1
        RegW "$r\SOFTWARE\Microsoft\InputPersonalization" REG_DWORD "RestrictImplicitInkCollection" 1
        RegW "$r\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" REG_DWORD "HarvestContacts" 0
        RegW "$r\SOFTWARE\Microsoft\Input\TIPC" REG_DWORD "Enabled" 0
        Log "Privacy / personalization: restricted"
    }
    if ($chkTaskbar.Checked) {
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" REG_DWORD "TaskbarDa" 0
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" REG_DWORD "TaskbarMn" 0
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" REG_DWORD "ShowCopilotButton" 0
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" REG_DWORD "DisableAutoplay" 1
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" REG_DWORD "SearchboxTaskbarMode" 1
        Log "Taskbar / Copilot: cleaned"
    }
    if ($chkSearch.Checked) {
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" REG_DWORD "BingSearchEnabled" 0
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" REG_DWORD "CortanaConsent" 0
        RegW "$r\SOFTWARE\Policies\Microsoft\Windows\Explorer" REG_DWORD "DisableSearchBoxSuggestions" 1
        Log "Web/Copilot search: off"
    }
    if ($chkPerms.Checked) {
        $cs = "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore"
        foreach ($k in "webcam","microphone","userAccountInformation","contacts","appointments","phoneCallHistory","email","userDataTasks","chat","cellularData","documentsLibrary","picturesLibrary","videosLibrary","broadFileSystemAccess") {
            RegW "$cs\$k" REG_SZ "Value" "Deny"
        }
        RegW "$r\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" REG_DWORD "GlobalUserDisabled" 1
        Log "App permissions: restricted"
    }
    if ($chkGameDVR.Checked) {
        RegW "$r\System\GameConfigStore" REG_DWORD "GameDVR_Enabled" 0
        Log "Game DVR: off"
    }

    Log ""
    Log "=== Done. Sign out/in (or restart Explorer) for taskbar/Start changes to show. ==="
    $btnRun.Enabled = $true
})

[void]$form.ShowDialog()
