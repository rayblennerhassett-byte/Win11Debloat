#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Motor accessibility settings. Single-paste into elevated PowerShell.
    Safe to re-run anytime. Called by 03-PostInstall-Bootstrap or standalone.
.DESCRIPTION
    Applies dark mode, no animations, no transparency, pointer/cursor customization,
    keyboard accommodation, power settings for motor accessibility.
    Exports all settings to archive drive for future reinstalls.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\FreshStartConfig.json"
)

$ErrorActionPreference = "Continue"

# Load config
if (Test-Path $ConfigPath) {
    $config = (Get-Content $ConfigPath -Raw | ConvertFrom-Json).Accessibility
} else {
    $config = @{
        DarkMode = $true; DisableAnimations = $true; DisableTransparency = $true
        DisableStickyKeys = $true; DisableMouseAcceleration = $false
        PointerSize = 3; PointerColor = 'white'; CursorThickness = 3
        TextScaleFactor = 100; DisableFilterKeys = $true; DisableToggleKeys = $true
        ScrollLines = 5; KeyboardDelay = 2; KeyboardSpeed = 20
        ScreenTimeoutMinutes = 30; NeverSleepOnAC = $true
    }
}

Write-Host "=== ACCESSIBILITY SETTINGS ===" -ForegroundColor Cyan

# --- Apply Win11Debloat .reg files where available ---
$regFilesPath = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "Regfiles"

if (Test-Path $regFilesPath) {
    $regFiles = @()
    if ($config.DarkMode)            { $regFiles += @{ File = 'Enable_Dark_Mode.reg';                  Desc = 'Dark mode' } }
    if ($config.DisableAnimations)   { $regFiles += @{ File = 'Disable_Animations.reg';                Desc = 'Disable animations' } }
    if ($config.DisableTransparency) { $regFiles += @{ File = 'Disable_Transparency.reg';              Desc = 'Disable transparency' } }
    if ($config.DisableStickyKeys)   { $regFiles += @{ File = 'Disable_Sticky_Keys_Shortcut.reg';      Desc = 'Disable sticky keys shortcut' } }

    foreach ($rf in $regFiles) {
        $path = Join-Path $regFilesPath $rf.File
        if (Test-Path $path) {
            reg import $path 2>$null
            Write-Host "  $($rf.Desc)" -ForegroundColor Gray
        }
    }

    # Mouse acceleration: commented toggle — uncomment the next 3 lines to enable
    # $mouseAccelReg = Join-Path $regFilesPath 'Disable_Enhance_Pointer_Precision.reg'
    # if (Test-Path $mouseAccelReg) { reg import $mouseAccelReg 2>$null }
    # Write-Host "  Mouse acceleration disabled" -ForegroundColor Gray
    if ($config.DisableMouseAcceleration) {
        $mouseAccelReg = Join-Path $regFilesPath 'Disable_Enhance_Pointer_Precision.reg'
        if (Test-Path $mouseAccelReg) {
            reg import $mouseAccelReg 2>$null
            Write-Host "  Mouse acceleration disabled" -ForegroundColor Gray
        }
    } else {
        Write-Host "  Mouse acceleration: left at system default (toggle in config)" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  [NOTE] Win11Debloat Regfiles not found, applying via registry directly" -ForegroundColor Yellow
    if ($config.DarkMode) {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0 -Type DWord
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0 -Type DWord
    }
}

# --- Cursor thickness ---
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "CaretWidth" -Value $config.CursorThickness -Type DWord
Write-Host "  Cursor thickness: $($config.CursorThickness)px" -ForegroundColor Gray

# --- Text scale factor ---
$accessPath = "HKCU:\Software\Microsoft\Accessibility"
if (-not (Test-Path $accessPath)) { New-Item -Path $accessPath -Force | Out-Null }
Set-ItemProperty -Path $accessPath -Name "TextScaleFactor" -Value $config.TextScaleFactor -Type DWord
Write-Host "  Text scale: $($config.TextScaleFactor)%" -ForegroundColor Gray

# --- Pointer size ---
Set-ItemProperty -Path $accessPath -Name "CursorSize" -Value $config.PointerSize -Type DWord
Write-Host "  Pointer size: $($config.PointerSize)/15" -ForegroundColor Gray

# --- Pointer color ---
$colorMap = @{ 'white' = 0; 'black' = 1; 'inverted' = 2 }
$cursorType = if ($colorMap.ContainsKey($config.PointerColor)) { $colorMap[$config.PointerColor] } else { 0 }
Set-ItemProperty -Path $accessPath -Name "CursorType" -Value $cursorType -Type DWord
Write-Host "  Pointer color: $($config.PointerColor)" -ForegroundColor Gray

# --- Disable Filter Keys shortcut ---
if ($config.DisableFilterKeys) {
    $fkPath = "HKCU:\Control Panel\Accessibility\Keyboard Response"
    if (-not (Test-Path $fkPath)) { New-Item -Path $fkPath -Force | Out-Null }
    Set-ItemProperty -Path $fkPath -Name "Flags" -Value "122" -Type String
    Write-Host "  Filter Keys shortcut disabled" -ForegroundColor Gray
}

# --- Disable Toggle Keys shortcut ---
if ($config.DisableToggleKeys) {
    $tkPath = "HKCU:\Control Panel\Accessibility\ToggleKeys"
    if (-not (Test-Path $tkPath)) { New-Item -Path $tkPath -Force | Out-Null }
    Set-ItemProperty -Path $tkPath -Name "Flags" -Value "58" -Type String
    Write-Host "  Toggle Keys shortcut disabled" -ForegroundColor Gray
}

# --- Scroll lines (more per tick = less scrolling effort) ---
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WheelScrollLines" -Value "$($config.ScrollLines)" -Type String
Write-Host "  Scroll lines per tick: $($config.ScrollLines)" -ForegroundColor Gray

# --- Keyboard repeat rate ---
Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value "$($config.KeyboardDelay)" -Type String
Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value "$($config.KeyboardSpeed)" -Type String
Write-Host "  Keyboard delay: $($config.KeyboardDelay), speed: $($config.KeyboardSpeed)" -ForegroundColor Gray

# --- Power settings for motor accessibility ---
if ($config.ScreenTimeoutMinutes) {
    powercfg /change monitor-timeout-ac $config.ScreenTimeoutMinutes
    Write-Host "  Screen timeout: $($config.ScreenTimeoutMinutes) minutes" -ForegroundColor Gray
}
if ($config.NeverSleepOnAC) {
    powercfg /change standby-timeout-ac 0
    Write-Host "  Sleep on AC: never" -ForegroundColor Gray
}

# Disable USB selective suspend (keeps peripherals connected)
powercfg /SETACVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
powercfg /SETACTIVE SCHEME_CURRENT 2>$null
Write-Host "  USB selective suspend disabled" -ForegroundColor Gray

# --- Export settings to archive ---
$archiveDrive = if ($PSScriptRoot -match '^[A-Z]:') {
    (Get-Content $ConfigPath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json).DriveLayout.Archive
} else { "F:" }

$exportDir = "${archiveDrive}\Backups\ConfigExports\Accessibility-$(Get-Date -Format 'yyyy-MM-dd')"
if (Test-Path "${archiveDrive}\") {
    New-Item -ItemType Directory -Path $exportDir -Force | Out-Null

    $regExports = @(
        'HKCU\Software\Microsoft\Accessibility',
        'HKCU\Control Panel\Accessibility',
        'HKCU\Control Panel\Mouse',
        'HKCU\Control Panel\Desktop',
        'HKCU\Control Panel\Keyboard',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    )
    foreach ($key in $regExports) {
        $fileName = ($key -replace '[:\\]', '_') + '.reg'
        reg export $key (Join-Path $exportDir $fileName) /y 2>$null | Out-Null
    }

    if (Test-Path $ConfigPath) {
        Copy-Item $ConfigPath (Join-Path $exportDir "FreshStartConfig.json") -ErrorAction SilentlyContinue
    }
    Write-Host "`n  Settings exported to: $exportDir" -ForegroundColor Green
} else {
    Write-Host "`n  Archive drive not connected — settings not exported" -ForegroundColor Yellow
}

Write-Host "`n  Accessibility settings applied. Reboot recommended." -ForegroundColor Green
