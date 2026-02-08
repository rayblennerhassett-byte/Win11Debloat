#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Game drive setup and GPU config. Single-paste into elevated PowerShell.
    Run after NVIDIA driver is installed.
.DESCRIPTION
    Creates game library folders, redirects shader caches to E: via symlinks,
    enables HW GPU scheduling, sets Ultimate Performance power plan,
    restores MSI Afterburner undervolt profile from H: if found.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\FreshStartConfig.json"
)

$ErrorActionPreference = "Continue"

# Load config
if (Test-Path $ConfigPath) {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $WorkDrive = $config.DriveLayout.Workspace
    $CacheDrive = $config.DriveLayout.Cache
} else {
    $WorkDrive = "D:"
    $CacheDrive = "E:"
}

Write-Host "=== GAME DRIVE SETUP ===" -ForegroundColor Cyan

# ========== GAME DIRECTORIES ==========
Write-Host "`n[1/5] Game directories on $WorkDrive" -ForegroundColor Cyan

$gameDirs = @(
    "$WorkDrive\Games\Steam", "$WorkDrive\Games\Steam\steamapps",
    "$WorkDrive\Games\GamePass", "$WorkDrive\Games\Epic",
    "$WorkDrive\Games\GOG", "$WorkDrive\Games\Mods"
)
foreach ($dir in $gameDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "  Created: $dir" -ForegroundColor Gray
    }
}
Write-Host "  Game directories ready" -ForegroundColor Green

# ========== SHADER CACHE SYMLINKS ==========
Write-Host "`n[2/5] Shader cache redirect to $CacheDrive" -ForegroundColor Cyan

function New-CacheSymlink {
    param([string]$Source, [string]$Target, [string]$Label)

    if (-not (Test-Path (Split-Path $Target))) {
        New-Item -ItemType Directory -Path (Split-Path $Target) -Force | Out-Null
    }
    if (-not (Test-Path $Target)) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
    }

    if (Test-Path $Source) {
        $item = Get-Item $Source -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Write-Host "  $Label already symlinked" -ForegroundColor DarkGray
            return
        }
        # Move existing data, create symlink
        $backup = "${Source}_backup_$(Get-Date -Format 'yyyyMMdd')"
        Move-Item $Source $backup -Force -ErrorAction SilentlyContinue
        cmd /c "mklink /D `"$Source`" `"$Target`"" 2>$null | Out-Null
        # Move old data into target
        if (Test-Path $backup) {
            Get-ChildItem $backup -ErrorAction SilentlyContinue | Move-Item -Destination $Target -Force -ErrorAction SilentlyContinue
            Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "  $Label -> $Target" -ForegroundColor Gray
    } else {
        # Source doesn't exist yet — create parent and symlink
        $parent = Split-Path $Source
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        cmd /c "mklink /D `"$Source`" `"$Target`"" 2>$null | Out-Null
        Write-Host "  $Label -> $Target (pre-linked)" -ForegroundColor Gray
    }
}

if (Test-Path "${CacheDrive}\") {
    New-CacheSymlink `
        -Source "$env:LOCALAPPDATA\NVIDIA\DXCache" `
        -Target "${CacheDrive}\ShaderCache\NVIDIA" `
        -Label "NVIDIA DXCache"

    New-CacheSymlink `
        -Source "$env:LOCALAPPDATA\NVIDIA\GLCache" `
        -Target "${CacheDrive}\ShaderCache\NVIDIA-GL" `
        -Label "NVIDIA GLCache"

    New-CacheSymlink `
        -Source "$env:LOCALAPPDATA\D3DSCache" `
        -Target "${CacheDrive}\ShaderCache\D3DS" `
        -Label "D3DSCache"

    Write-Host "  Shader caches redirected" -ForegroundColor Green
} else {
    Write-Host "  [SKIP] Cache drive ${CacheDrive} not connected" -ForegroundColor Yellow
}

# ========== GPU SCHEDULING ==========
Write-Host "`n[3/5] GPU configuration" -ForegroundColor Cyan

# Enable Hardware-accelerated GPU Scheduling
$gpuSchedPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
Set-ItemProperty -Path $gpuSchedPath -Name "HwSchMode" -Value 2 -Type DWord
Write-Host "  HW-accelerated GPU scheduling enabled" -ForegroundColor Gray

Write-Host "`n  NVIDIA Control Panel (set manually after driver install):" -ForegroundColor Yellow
Write-Host "    Power management mode: Prefer Maximum Performance" -ForegroundColor White
Write-Host "    Low Latency Mode: On" -ForegroundColor White
Write-Host "    Shader Cache Size: 10 GB" -ForegroundColor White

# ========== POWER PLAN ==========
Write-Host "`n[4/5] Power plan" -ForegroundColor Cyan

$ultPerf = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
if ($ultPerf -match '([a-f0-9-]{36})') {
    powercfg -setactive $Matches[1]
    Write-Host "  Ultimate Performance power plan activated" -ForegroundColor Green
} else {
    # Check if already exists
    $existing = powercfg /list 2>$null | Select-String "Ultimate Performance"
    if ($existing -and $existing -match '([a-f0-9-]{36})') {
        powercfg -setactive $Matches[1]
        Write-Host "  Ultimate Performance already exists, activated" -ForegroundColor Green
    } else {
        powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
        Write-Host "  High Performance activated (Ultimate not available on this build)" -ForegroundColor Yellow
    }
}

# ========== MSI AFTERBURNER PROFILE ==========
Write-Host "`n[5/5] MSI Afterburner" -ForegroundColor Cyan

$abInstallPath = "${env:ProgramFiles(x86)}\MSI Afterburner\Profiles"
$abFound = $false

# Search H: for the old profile swept during Haiku purge
$searchPaths = @("H:\")
$abConfigs = @()
foreach ($sp in $searchPaths) {
    if (Test-Path $sp) {
        $found = Get-ChildItem $sp -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'VEN_10DE.*\.cfg$|MSIAfterburner\.cfg$' } |
            Select-Object -First 5
        $abConfigs += $found
    }
}

if ($abConfigs.Count -gt 0) {
    Write-Host "  Found Afterburner profile(s) on H:" -ForegroundColor Green
    foreach ($cfg in $abConfigs) {
        Write-Host "    $($cfg.FullName)" -ForegroundColor Gray
    }

    if (Test-Path $abInstallPath) {
        foreach ($cfg in $abConfigs) {
            Copy-Item $cfg.FullName $abInstallPath -Force -ErrorAction SilentlyContinue
            Write-Host "  Restored: $($cfg.Name) -> $abInstallPath" -ForegroundColor Green
        }
        $abFound = $true
    } else {
        Write-Host "  MSI Afterburner not installed yet. Profiles found at:" -ForegroundColor Yellow
        foreach ($cfg in $abConfigs) {
            Write-Host "    $($cfg.FullName)" -ForegroundColor White
        }
        Write-Host "  Copy these to MSI Afterburner Profiles folder after install." -ForegroundColor Yellow
    }
} else {
    Write-Host "  No Afterburner profiles found on H:" -ForegroundColor Yellow
    Write-Host "  After installing MSI Afterburner, create undervolt profile manually:" -ForegroundColor White
    Write-Host "    1. Open Afterburner -> Ctrl+F (voltage/frequency curve)" -ForegroundColor White
    Write-Host "    2. Find your target voltage (e.g., 900mV)" -ForegroundColor White
    Write-Host "    3. Set desired clock at that voltage, flatten curve above it" -ForegroundColor White
    Write-Host "    4. Save as Profile 1, enable 'Start with Windows'" -ForegroundColor White
}

# FanControl: installed via winget, config deferred
Write-Host "`n  FanControl: installed, configure fan curves via the app after testing" -ForegroundColor DarkGray

# ========== GAME PLATFORM INSTRUCTIONS ==========
Write-Host "`n=== GAME PLATFORM LIBRARY PATHS ===" -ForegroundColor Cyan
Write-Host "  Steam:    Settings > Storage > Add folder: $WorkDrive\Games\Steam" -ForegroundColor White
Write-Host "  Xbox:     Settings > General > Default install: $WorkDrive\Games\GamePass" -ForegroundColor White
Write-Host "  Epic:     Settings > Install Location: $WorkDrive\Games\Epic" -ForegroundColor White
Write-Host "  GOG:      Settings > Installing > Folder: $WorkDrive\Games\GOG" -ForegroundColor White

Write-Host "`n  Game drive setup complete." -ForegroundColor Green
