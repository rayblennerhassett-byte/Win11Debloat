#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Post-install bootstrap for Fresh Start. Single-paste into elevated PowerShell.
    Run AFTER fresh Windows install on NVMe.
.DESCRIPTION
    Phase 1:  Win11Debloat (silent)
    Phase 1b: Lean & Mean Windows hardening
    Phase 2:  Directory structures on all drives
    Phase 3:  App installation via winget
    Phase 4:  WSL2 setup
    Phase 5:  Environment variable redirects (caches to E:)
    Phase 6:  Git configuration
    Phase 7:  Claude Code installation
    Phase 8:  Accessibility settings
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\FreshStartConfig.json",
    [switch]$SkipDebloat,
    [switch]$SkipWinget,
    [switch]$SkipWSL,
    [switch]$SkipAccessibility
)

$ErrorActionPreference = "Continue"
$transcriptPath = "$env:USERPROFILE\Desktop\FreshStart-Bootstrap-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $transcriptPath

# Load config
if (Test-Path $ConfigPath) {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    Write-Host "[CONFIG] Loaded from $ConfigPath" -ForegroundColor Green
} else {
    Write-Host "[CONFIG] Not found at $ConfigPath, using defaults" -ForegroundColor Yellow
    $config = @{
        DriveLayout = @{ System = 'C:'; Workspace = 'D:'; Cache = 'E:'; Archive = 'F:'; ColdStorage = 'H:' }
        Accessibility = @{ DarkMode = $true; DisableAnimations = $true; DisableTransparency = $true; DisableStickyKeys = $true }
        WingetApps = @('Git.Git','Microsoft.VisualStudioCode','Python.Python.3.12','OpenJS.NodeJS.LTS',
            'Docker.DockerDesktop','Ollama.Ollama','Microsoft.WindowsTerminal','7zip.7zip','VideoLAN.VLC',
            'Valve.Steam','Notepad++.Notepad++','Microsoft.PowerToys','Nvidia.GeForceExperience',
            'Guru3D.MSIAfterburner','FanControl.FanControl')
    }
}

$WorkDrive = $config.DriveLayout.Workspace
$CacheDrive = $config.DriveLayout.Cache
$ArchiveDrive = $config.DriveLayout.Archive
$ColdDrive = $config.DriveLayout.ColdStorage

# ========== PHASE 1: WIN11DEBLOAT ==========
if (-not $SkipDebloat) {
    Write-Host "`n=== PHASE 1: WIN11DEBLOAT ===" -ForegroundColor Cyan

    $debloatScript = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "Win11Debloat.ps1"

    if (Test-Path $debloatScript) {
        Write-Host "  Running Win11Debloat from: $debloatScript" -ForegroundColor Gray
        & $debloatScript `
            -Silent `
            -CreateRestorePoint `
            -RemoveApps `
            -RemoveCommApps `
            -RemoveW11Outlook `
            -DisableTelemetry `
            -DisableSuggestions `
            -DisableEdgeAds `
            -DisableLockscreenTips `
            -DisableBing `
            -DisableCopilot `
            -DisableRecall `
            -DisableClickToDo `
            -DisableEdgeAI `
            -DisablePaintAI `
            -DisableNotepadAI `
            -DisableWidgets `
            -DisableDesktopSpotlight `
            -DisableSettings365Ads `
            -DisableSettingsHome `
            -DisableFastStartup `
            -DisableModernStandbyNetworking `
            -DisableDVR `
            -EnableDarkMode `
            -DisableTransparency `
            -DisableAnimations `
            -DisableStickyKeys `
            -RevertContextMenu `
            -ShowKnownFileExt `
            -ShowHiddenFolders `
            -ExplorerToThisPC `
            -AddFoldersToThisPC `
            -HideHome `
            -HideGallery `
            -HideDupliDrive `
            -HideSearchTb `
            -HideTaskview `
            -TaskbarAlignLeft `
            -CombineTaskbarNever `
            -CombineMMTaskbarNever `
            -EnableEndTask `
            -EnableLastActiveClick `
            -ClearStartAllUsers `
            -DisableStartPhoneLink `
            -NoRestartExplorer
        Write-Host "  Win11Debloat complete" -ForegroundColor Green
    } else {
        Write-Host "  Win11Debloat.ps1 not found locally, downloading..." -ForegroundColor Yellow
        & ([scriptblock]::Create((irm "https://raw.githubusercontent.com/Raphire/Win11Debloat/master/Get.ps1"))) -RunDefaults -Silent
    }

    # ========== PHASE 1b: LEAN & MEAN HARDENING ==========
    Write-Host "`n=== PHASE 1b: LEAN & MEAN ===" -ForegroundColor Cyan

    # Ultimate Performance power plan
    Write-Host "  Enabling Ultimate Performance power plan..." -ForegroundColor Gray
    $ultPerf = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
    if ($ultPerf -match '([a-f0-9-]{36})') {
        powercfg -setactive $Matches[1]
        Write-Host "  Ultimate Performance activated" -ForegroundColor Green
    } else {
        powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  # High Performance fallback
        Write-Host "  High Performance activated (Ultimate not available)" -ForegroundColor Yellow
    }

    # Disable background apps
    $bgAppsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
    if (-not (Test-Path $bgAppsPath)) { New-Item -Path $bgAppsPath -Force | Out-Null }
    Set-ItemProperty -Path $bgAppsPath -Name "GlobalUserDisabled" -Value 1 -Type DWord
    Write-Host "  Background apps disabled" -ForegroundColor Gray

    # Disable startup delay
    $serializePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
    if (-not (Test-Path $serializePath)) { New-Item -Path $serializePath -Force | Out-Null }
    Set-ItemProperty -Path $serializePath -Name "StartupDelayInMSec" -Value 0 -Type DWord
    Write-Host "  Startup delay removed" -ForegroundColor Gray

    # Disable Windows Search indexing (SSD = fast enough without it)
    Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
    Set-Service -Name "WSearch" -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host "  Windows Search indexing disabled" -ForegroundColor Gray

    # Disable SysMain (Superfetch) — unnecessary on all-SSD
    Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
    Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host "  SysMain/Superfetch disabled" -ForegroundColor Gray

    # Disable hibernation (frees ~16GB on C:)
    powercfg -h off
    Write-Host "  Hibernation disabled (freed ~16GB)" -ForegroundColor Gray

    # Disable delivery optimization (P2P updates)
    $doPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
    if (-not (Test-Path $doPath)) { New-Item -Path $doPath -Force | Out-Null }
    Set-ItemProperty -Path $doPath -Name "DODownloadMode" -Value 0 -Type DWord
    Write-Host "  Delivery optimization (P2P) disabled" -ForegroundColor Gray

    # Disable Game DVR background recording
    $gameDvrPath = "HKCU:\System\GameConfigStore"
    if (Test-Path $gameDvrPath) {
        Set-ItemProperty -Path $gameDvrPath -Name "GameDVR_Enabled" -Value 0 -Type DWord
    }
    $gameDvrPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if (-not (Test-Path $gameDvrPolicy)) { New-Item -Path $gameDvrPolicy -Force | Out-Null }
    Set-ItemProperty -Path $gameDvrPolicy -Name "AllowGameDVR" -Value 0 -Type DWord
    Write-Host "  Game DVR background recording disabled" -ForegroundColor Gray

    # Disable Xbox Game Monitoring
    $xboxMonSvc = Get-Service -Name "xbgm" -ErrorAction SilentlyContinue
    if ($xboxMonSvc) {
        Stop-Service -Name "xbgm" -Force -ErrorAction SilentlyContinue
        Set-Service -Name "xbgm" -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "  Xbox Game Monitoring disabled" -ForegroundColor Gray
    }

    # Visual effects: best performance (keep font smoothing)
    $visualFxPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    if (-not (Test-Path $visualFxPath)) { New-Item -Path $visualFxPath -Force | Out-Null }
    Set-ItemProperty -Path $visualFxPath -Name "VisualFXSetting" -Value 2 -Type DWord
    # Re-enable font smoothing
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "FontSmoothing" -Value "2" -Type String
    Write-Host "  Visual effects: best performance (font smoothing kept)" -ForegroundColor Gray

    # Disable activity history
    $actHistPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $actHistPath)) { New-Item -Path $actHistPath -Force | Out-Null }
    Set-ItemProperty -Path $actHistPath -Name "EnableActivityFeed" -Value 0 -Type DWord
    Set-ItemProperty -Path $actHistPath -Name "PublishUserActivities" -Value 0 -Type DWord
    Set-ItemProperty -Path $actHistPath -Name "UploadUserActivities" -Value 0 -Type DWord
    Write-Host "  Activity history disabled" -ForegroundColor Gray

    # Disable clipboard history cloud sync
    $clipPath = "HKCU:\Software\Microsoft\Clipboard"
    if (-not (Test-Path $clipPath)) { New-Item -Path $clipPath -Force | Out-Null }
    Set-ItemProperty -Path $clipPath -Name "EnableClipboardHistory" -Value 0 -Type DWord
    Set-ItemProperty -Path $clipPath -Name "CloudClipboardAutomaticUpload" -Value 0 -Type DWord
    Write-Host "  Clipboard cloud sync disabled" -ForegroundColor Gray

    Write-Host "  Lean & Mean hardening complete" -ForegroundColor Green
}

# ========== PHASE 2: DIRECTORY STRUCTURES ==========
Write-Host "`n=== PHASE 2: DIRECTORY STRUCTURES ===" -ForegroundColor Cyan

$directories = @(
    "C:\Dev\tools",
    "$WorkDrive\Games\Steam", "$WorkDrive\Games\GamePass", "$WorkDrive\Games\Epic", "$WorkDrive\Games\GOG", "$WorkDrive\Games\Mods",
    "$WorkDrive\Dev\projects", "$WorkDrive\Dev\repos",
    "$WorkDrive\Dev\llm-workspace\models", "$WorkDrive\Dev\llm-workspace\datasets", "$WorkDrive\Dev\llm-workspace\outputs",
    "$WorkDrive\VMs", "$WorkDrive\Scratch",
    "$CacheDrive\ShaderCache\NVIDIA", "$CacheDrive\ShaderCache\NVIDIA-GL", "$CacheDrive\ShaderCache\D3DS",
    "$CacheDrive\BrowserCache", "$CacheDrive\WindowsTemp", "$CacheDrive\DownloadStaging",
    "$CacheDrive\BuildCache\npm", "$CacheDrive\BuildCache\pip", "$CacheDrive\BuildCache\docker",
    "$ArchiveDrive\Personal\Photos", "$ArchiveDrive\Personal\Drone\Raw", "$ArchiveDrive\Personal\Drone\Edited",
    "$ArchiveDrive\Personal\Documents\Letters", "$ArchiveDrive\Personal\Documents\Financial",
    "$ArchiveDrive\Personal\Documents\Medical", "$ArchiveDrive\Personal\Documents\Legal",
    "$ArchiveDrive\Personal\Family\Photos", "$ArchiveDrive\Personal\Family\Videos", "$ArchiveDrive\Personal\Family\Scans",
    "$ArchiveDrive\Personal\Projects",
    "$ArchiveDrive\Backups\SystemImages", "$ArchiveDrive\Backups\ConfigExports\FreshStart-Reports",
    "$ArchiveDrive\Media\Music", "$ArchiveDrive\Media\Video",
    "$ColdDrive\ISOs", "$ColdDrive\Datasets", "$ColdDrive\Downloads-Archive", "$ColdDrive\Overflow"
)

$created = 0; $skipped = 0
foreach ($dir in $directories) {
    $driveLetter = $dir.Substring(0, 2)
    if (-not (Test-Path "${driveLetter}\")) {
        $skipped++; continue
    }
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $created++
    } else { $skipped++ }
}
Write-Host "  Created $created directories, $skipped already existed or drive not connected" -ForegroundColor Green

# ========== PHASE 3: WINGET APPS ==========
if (-not $SkipWinget) {
    Write-Host "`n=== PHASE 3: APP INSTALLATION ===" -ForegroundColor Cyan

    # Wait for winget
    $wingetReady = $false
    for ($i = 0; $i -lt 15; $i++) {
        if (Get-Command winget -ErrorAction SilentlyContinue) { $wingetReady = $true; break }
        Write-Host "  Waiting for winget..." -ForegroundColor Gray
        Start-Sleep -Seconds 2
    }

    if (-not $wingetReady) {
        Write-Host "  Winget not available, attempting App Installer install..." -ForegroundColor Yellow
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        $wingetReady = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    }

    if ($wingetReady) {
        $apps = $config.WingetApps
        if (-not $apps) {
            $apps = @('Git.Git','Microsoft.VisualStudioCode','Python.Python.3.12','OpenJS.NodeJS.LTS',
                'Microsoft.WindowsTerminal','7zip.7zip','Valve.Steam','Microsoft.PowerToys')
        }

        foreach ($appId in $apps) {
            Write-Host "  Installing $appId..." -ForegroundColor Gray -NoNewline
            $result = winget install --id $appId --accept-source-agreements --accept-package-agreements --disable-interactivity --silent 2>&1
            if ($LASTEXITCODE -eq 0 -or "$result" -match 'already installed') {
                Write-Host " OK" -ForegroundColor Green
            } else {
                Write-Host " FAILED" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "  [SKIP] Winget not available. Install apps manually." -ForegroundColor Red
    }
}

# ========== PHASE 4: WSL2 ==========
if (-not $SkipWSL) {
    Write-Host "`n=== PHASE 4: WSL2 ===" -ForegroundColor Cyan

    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
    $needsReboot = $false

    if ($wslFeature.State -ne 'Enabled') {
        Write-Host "  Enabling WSL and Virtual Machine Platform..." -ForegroundColor Gray
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart -ErrorAction SilentlyContinue
        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart -ErrorAction SilentlyContinue
        $needsReboot = $true
        Write-Host "  WSL features enabled. REBOOT REQUIRED before Ubuntu install." -ForegroundColor Yellow
    }

    if (-not $needsReboot) {
        Write-Host "  Installing Ubuntu 24.04..." -ForegroundColor Gray
        wsl --install -d Ubuntu-24.04 --no-launch 2>$null
        Write-Host "  Ubuntu 24.04 installed. Launch from Start to complete setup." -ForegroundColor Green
    }
}

# ========== PHASE 5: ENVIRONMENT VARIABLES ==========
Write-Host "`n=== PHASE 5: ENVIRONMENT VARIABLES ===" -ForegroundColor Cyan

if (Test-Path "${CacheDrive}\") {
    [Environment]::SetEnvironmentVariable("TEMP", "${CacheDrive}\WindowsTemp", "User")
    [Environment]::SetEnvironmentVariable("TMP", "${CacheDrive}\WindowsTemp", "User")
    Write-Host "  TEMP/TMP -> ${CacheDrive}\WindowsTemp" -ForegroundColor Gray

    [Environment]::SetEnvironmentVariable("PIP_CACHE_DIR", "${CacheDrive}\BuildCache\pip", "User")
    Write-Host "  PIP_CACHE_DIR -> ${CacheDrive}\BuildCache\pip" -ForegroundColor Gray

    # npm cache (if npm available)
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        npm config set cache "${CacheDrive}\BuildCache\npm" 2>$null
        Write-Host "  npm cache -> ${CacheDrive}\BuildCache\npm" -ForegroundColor Gray
    }
} else {
    Write-Host "  [SKIP] Cache drive ${CacheDrive} not connected" -ForegroundColor Yellow
}

# Ollama models to workspace drive
if (Test-Path "${WorkDrive}\") {
    [Environment]::SetEnvironmentVariable("OLLAMA_MODELS", "${WorkDrive}\Dev\llm-workspace\models", "User")
    Write-Host "  OLLAMA_MODELS -> ${WorkDrive}\Dev\llm-workspace\models" -ForegroundColor Gray
}

# ========== PHASE 6: GIT CONFIG ==========
Write-Host "`n=== PHASE 6: GIT ===" -ForegroundColor Cyan

if (Get-Command git -ErrorAction SilentlyContinue) {
    if ($config.GitUserName) { git config --global user.name $config.GitUserName }
    if ($config.GitUserEmail) { git config --global user.email $config.GitUserEmail }
    git config --global init.defaultBranch main
    git config --global core.autocrlf true
    git config --global core.editor "code --wait"
    git config --global pull.rebase false
    git config --global push.autoSetupRemote true
    git config --global feature.manyFiles true
    git config --global core.fsmonitor true
    Write-Host "  Git configured" -ForegroundColor Green
} else {
    Write-Host "  [SKIP] Git not in PATH yet. Restart terminal and re-run with -SkipDebloat -SkipWinget" -ForegroundColor Yellow
}

# ========== PHASE 7: CLAUDE CODE ==========
Write-Host "`n=== PHASE 7: CLAUDE CODE ===" -ForegroundColor Cyan

if (Get-Command npm -ErrorAction SilentlyContinue) {
    Write-Host "  Installing Claude Code..." -ForegroundColor Gray
    npm install -g @anthropic-ai/claude-code 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Claude Code installed" -ForegroundColor Green
    } else {
        Write-Host "  Install failed. Try: npm install -g @anthropic-ai/claude-code" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [SKIP] npm not in PATH. Restart terminal first." -ForegroundColor Yellow
}

# ========== PHASE 8: ACCESSIBILITY ==========
if (-not $SkipAccessibility) {
    Write-Host "`n=== PHASE 8: ACCESSIBILITY ===" -ForegroundColor Cyan
    $accessScript = Join-Path $PSScriptRoot "04-Accessibility-BakeIn.ps1"
    if (Test-Path $accessScript) {
        & $accessScript -ConfigPath $ConfigPath
    } else {
        Write-Host "  [SKIP] 04-Accessibility-BakeIn.ps1 not found at $accessScript" -ForegroundColor Yellow
    }
}

# ========== DONE ==========
Write-Host "`n============================================" -ForegroundColor Green
Write-Host "  BOOTSTRAP COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "`n  Next steps:" -ForegroundColor White
Write-Host "  1. Restart your computer (required for WSL, services, registry changes)" -ForegroundColor White
Write-Host "  2. Run 05-GameDrive-Setup.ps1 after NVIDIA driver installs" -ForegroundColor White
Write-Host "  3. Fill in FreshStartConfig.json with your git name/email, re-run with -SkipDebloat" -ForegroundColor White
Write-Host "`n  Log saved: $transcriptPath" -ForegroundColor Gray

# Restart Explorer
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process explorer.exe

Stop-Transcript
