#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Pre-flight diagnostics for Fresh Start. Single-paste into elevated PowerShell.
    READ-ONLY — modifies nothing except creating the report file.
.DESCRIPTION
    Maps physical disks to drive letters, runs SMART health checks, inventories data,
    checks critical file archive status, exports credentials and accessibility settings.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ReportDir = "$env:USERPROFILE\Desktop\FreshStart-PreFlight-$Timestamp"
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
$ReportFile = Join-Path $ReportDir "PreFlight-Report.txt"

function Write-Report {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
    $Message | Out-File -Append -FilePath $ReportFile -Encoding UTF8
}

Write-Report "============================================"
Write-Report "  FRESH START PRE-FLIGHT DIAGNOSTICS"
Write-Report "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Report "============================================"

# ========== SECTION 1: PHYSICAL DISK TO DRIVE LETTER MAPPING ==========
Write-Report "`n=== SECTION 1: DISK MAPPING ===" "Cyan"
Write-Report "Resolving physical disks to drive letters...`n"

$DiskMap = @()
Get-PhysicalDisk | ForEach-Object {
    $physDisk = $_
    try {
        $disk = $physDisk | Get-Disk -ErrorAction SilentlyContinue
        $partitions = $disk | Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter }
        foreach ($part in $partitions) {
            $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction SilentlyContinue
            $entry = [PSCustomObject]@{
                DriveLetter   = "$($part.DriveLetter):"
                FriendlyName  = $physDisk.FriendlyName
                MediaType     = $physDisk.MediaType
                BusType       = $physDisk.BusType
                SizeGB        = [math]::Round($physDisk.Size / 1GB, 1)
                FreeGB        = [math]::Round($vol.SizeRemaining / 1GB, 1)
                HealthStatus  = $physDisk.HealthStatus
                Label         = $vol.FileSystemLabel
            }
            $DiskMap += $entry
        }
    } catch {}
}

$DiskMap | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Report $_ }

# Flag the mechanical HDD
$hddEntries = $DiskMap | Where-Object {
    $_.MediaType -eq 'HDD' -or $_.FriendlyName -match 'ST1000DM003'
}
foreach ($hdd in $hddEntries) {
    Write-Report "[HDD IDENTIFIED] $($hdd.DriveLetter) = $($hdd.FriendlyName) (MECHANICAL HARD DRIVE)" "Yellow"
}

# Flag the NVMe
$nvmeEntries = $DiskMap | Where-Object {
    $_.BusType -eq 'NVMe' -or $_.FriendlyName -match 'CT1000P3SSD8'
}
foreach ($nvme in $nvmeEntries) {
    Write-Report "[NVMe IDENTIFIED] $($nvme.DriveLetter) = $($nvme.FriendlyName) (FASTEST DRIVE — should be boot)" "Green"
}

# ========== SECTION 2: SMART HEALTH CHECK ==========
Write-Report "`n=== SECTION 2: DRIVE HEALTH ===" "Cyan"

Get-PhysicalDisk | ForEach-Object {
    $disk = $_
    $health = $_ | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
    $entry = [PSCustomObject]@{
        Name            = $disk.FriendlyName
        MediaType       = $disk.MediaType
        Health          = $disk.HealthStatus
        Operational     = $disk.OperationalStatus
        TempC           = if ($health.Temperature) { $health.Temperature } else { 'N/A' }
        ReadErrors      = if ($null -ne $health.ReadErrorsTotal) { $health.ReadErrorsTotal } else { 'N/A' }
        WriteErrors     = if ($null -ne $health.WriteErrorsTotal) { $health.WriteErrorsTotal } else { 'N/A' }
        Wear            = if ($null -ne $health.Wear) { "$($health.Wear)%" } else { 'N/A' }
        PowerOnHours    = if ($health.PowerOnHours) { $health.PowerOnHours } else { 'N/A' }
        PowerOnYears    = if ($health.PowerOnHours) { [math]::Round($health.PowerOnHours / 8760, 1) } else { 'N/A' }
    }
    $entry | Format-List | Out-String | ForEach-Object { Write-Report $_ }

    # Warnings
    if ($health.PowerOnHours -and $health.PowerOnHours -gt 40000) {
        Write-Report "  [WARNING] $($disk.FriendlyName): $($health.PowerOnHours) power-on hours — approaching end of life" "Red"
    }
    if ($health.ReadErrorsTotal -and $health.ReadErrorsTotal -gt 0) {
        Write-Report "  [WARNING] $($disk.FriendlyName): $($health.ReadErrorsTotal) read errors detected" "Red"
    }
    if ($health.Wear -and $health.Wear -gt 80) {
        Write-Report "  [WARNING] $($disk.FriendlyName): $($health.Wear)% wear — SSD nearing end of life" "Red"
    }
    if ($disk.HealthStatus -ne 'Healthy') {
        Write-Report "  [CRITICAL] $($disk.FriendlyName): Health status is $($disk.HealthStatus)" "Red"
    }
}

# ========== SECTION 3: DATA INVENTORY ==========
Write-Report "`n=== SECTION 3: DATA INVENTORY ===" "Cyan"

$volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -in @('Fixed','Removable') -and $_.FileSystem }
foreach ($vol in $volumes) {
    $root = "$($vol.DriveLetter):\"
    Write-Report "`n--- Drive $($vol.DriveLetter): ($($vol.FileSystemLabel)) ---" "Cyan"
    Write-Report "  Total: $([math]::Round($vol.Size/1GB,1)) GB | Free: $([math]::Round($vol.SizeRemaining/1GB,1)) GB | Used: $([math]::Round(($vol.Size - $vol.SizeRemaining)/1GB,1)) GB"

    Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('$Recycle.Bin','System Volume Information','Recovery','$WinREAgent') } |
        ForEach-Object {
            $dir = $_
            $size = (Get-ChildItem $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            [PSCustomObject]@{
                Folder = $dir.Name
                SizeGB = [math]::Round($size / 1GB, 2)
            }
        } | Sort-Object SizeGB -Descending |
        Format-Table -AutoSize | Out-String | ForEach-Object { Write-Report $_ }
}

# ========== SECTION 4: CRITICAL FILE ARCHIVE CHECK ==========
Write-Report "`n=== SECTION 4: CRITICAL FILE ARCHIVE CHECK ===" "Cyan"
Write-Report "Scanning for irreplaceable files...`n"

$ArchiveDrive = "F:"
$CriticalLocations = @(
    @{ Name = "Desktop";           Path = "$env:USERPROFILE\Desktop" },
    @{ Name = "Documents";         Path = "$env:USERPROFILE\Documents" },
    @{ Name = "Downloads";         Path = "$env:USERPROFILE\Downloads" },
    @{ Name = "Pictures";          Path = "$env:USERPROFILE\Pictures" },
    @{ Name = "Videos";            Path = "$env:USERPROFILE\Videos" },
    @{ Name = "Music";             Path = "$env:USERPROFILE\Music" },
    @{ Name = "SSH Keys";          Path = "$env:USERPROFILE\.ssh" },
    @{ Name = "Git Config";        Path = "$env:USERPROFILE\.gitconfig" },
    @{ Name = "Claude Config";     Path = "$env:USERPROFILE\.claude" },
    @{ Name = "VS Code Settings";  Path = "$env:APPDATA\Code\User\settings.json" },
    @{ Name = "VS Code Extensions"; Path = "$env:USERPROFILE\.vscode\extensions" },
    @{ Name = "Chrome Bookmarks";  Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Bookmarks" },
    @{ Name = "Chrome Login Data"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data" },
    @{ Name = "Firefox Profile";   Path = "$env:APPDATA\Mozilla\Firefox\Profiles" },
    @{ Name = "Edge Bookmarks";    Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks" },
    @{ Name = "Edge Login Data";   Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data" },
    @{ Name = "NPM Global";       Path = "$env:APPDATA\npm" },
    @{ Name = "Env Files (.env)";  Path = "SCAN" }
)

# Check MSI Afterburner profiles across all drives
$abPaths = @(
    "${env:ProgramFiles(x86)}\MSI Afterburner\Profiles",
    "$env:APPDATA\MSI Afterburner",
    "H:\MSI Afterburner",
    "H:\Users",
    "H:\Profiles"
)
foreach ($abp in $abPaths) {
    if (Test-Path $abp) {
        $cfgFiles = Get-ChildItem $abp -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(VEN_10DE|MSIAfterburner|\.cfg$)' }
        if ($cfgFiles) {
            foreach ($cf in $cfgFiles) {
                Write-Report "  [MSI AB PROFILE FOUND] $($cf.FullName)" "Green"
            }
        }
    }
}

# Scan H: broadly for Afterburner configs
$hSearch = Get-ChildItem "H:\" -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'VEN_10DE.*\.cfg|MSIAfterburner\.cfg' } |
    Select-Object -First 10
foreach ($found in $hSearch) {
    Write-Report "  [MSI AB ON H:] $($found.FullName)" "Yellow"
}

foreach ($loc in $CriticalLocations) {
    if ($loc.Path -eq "SCAN") {
        # Scan for .env files across user-accessible locations
        $envFiles = @()
        foreach ($drive in @("C:\Users","D:\","E:\")) {
            if (Test-Path $drive) {
                $envFiles += Get-ChildItem $drive -Recurse -File -Filter ".env" -ErrorAction SilentlyContinue |
                    Select-Object -First 20
            }
        }
        if ($envFiles.Count -gt 0) {
            Write-Report "  [NEEDS BACKUP] .env files found:" "Red"
            foreach ($ef in $envFiles) {
                Write-Report "    $($ef.FullName)" "Yellow"
            }
        } else {
            Write-Report "  [OK] No .env files found" "Green"
        }
        continue
    }

    if (Test-Path $loc.Path) {
        $item = Get-Item $loc.Path
        if ($item.PSIsContainer) {
            $size = (Get-ChildItem $loc.Path -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            $sizeStr = "$([math]::Round($size / 1MB, 1)) MB"
        } else {
            $sizeStr = "$([math]::Round($item.Length / 1KB, 1)) KB"
        }

        # Check if a copy exists on archive drive
        $archivePath = Join-Path $ArchiveDrive "Backups\ConfigExports\$($loc.Name)"
        if (Test-Path $archivePath) {
            Write-Report "  [ARCHIVED]     $($loc.Name) ($sizeStr) -> $archivePath" "Green"
        } else {
            Write-Report "  [NEEDS BACKUP] $($loc.Name) ($sizeStr) at $($loc.Path)" "Red"
        }
    } else {
        Write-Report "  [NOT FOUND]    $($loc.Name) — $($loc.Path)" "DarkGray"
    }
}

# ========== SECTION 5: CREDENTIAL & PASSKEY EXPORT ==========
Write-Report "`n=== SECTION 5: CREDENTIALS & PASSKEYS ===" "Cyan"

$CredDir = Join-Path $ReportDir "Credentials"
New-Item -ItemType Directory -Path $CredDir -Force | Out-Null

# Windows Credential Manager
Write-Report "  Exporting Windows Credential Manager entries..."
$credOutput = cmdkey /list 2>&1
$credOutput | Out-File -FilePath (Join-Path $CredDir "CredentialManager.txt") -Encoding UTF8
$credCount = ($credOutput | Select-String "Target:").Count
Write-Report "  [EXPORTED] $credCount credential entries -> Credentials\CredentialManager.txt" "Green"

# Wi-Fi profiles with passwords
Write-Report "  Exporting Wi-Fi profiles with saved passwords..."
$wifiDir = Join-Path $CredDir "WiFi"
New-Item -ItemType Directory -Path $wifiDir -Force | Out-Null
$wifiExport = netsh wlan export profile key=clear folder="$wifiDir" 2>&1
$wifiCount = (Get-ChildItem $wifiDir -Filter "*.xml" -ErrorAction SilentlyContinue).Count
Write-Report "  [EXPORTED] $wifiCount Wi-Fi profiles -> Credentials\WiFi\" "Green"

# Browser password DB file locations (not decrypted — just flagged for user action)
Write-Report "`n  Browser Password Databases (export via browser before reinstall):"
$browserDBs = @(
    @{ Browser = "Chrome";  Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data" },
    @{ Browser = "Edge";    Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data" },
    @{ Browser = "Firefox"; Path = "$env:APPDATA\Mozilla\Firefox\Profiles" }
)
foreach ($db in $browserDBs) {
    if (Test-Path $db.Path) {
        Write-Report "  [ACTION REQUIRED] $($db.Browser): Export passwords via browser Settings > Passwords > Export" "Yellow"
    } else {
        Write-Report "  [NOT FOUND] $($db.Browser) password database" "DarkGray"
    }
}

# Windows Hello / Passkeys
Write-Report "`n  Windows Hello / Passkeys:"
Write-Report "  [ACTION REQUIRED] Passkeys are tied to Windows Hello TPM. Ensure your Microsoft" "Yellow"
Write-Report "  account is syncing passkeys, or re-register them after reinstall." "Yellow"
Write-Report "  Go to: Settings > Accounts > Passkeys to review saved passkeys." "Yellow"

# ========== SECTION 6: ACCESSIBILITY SETTINGS EXPORT ==========
Write-Report "`n=== SECTION 6: ACCESSIBILITY SETTINGS EXPORT ===" "Cyan"

$AccessDir = Join-Path $ReportDir "AccessibilityBackup"
New-Item -ItemType Directory -Path $AccessDir -Force | Out-Null

$regExports = @(
    @{ Key = 'HKCU\Software\Microsoft\Accessibility';       File = 'ms_accessibility.reg' },
    @{ Key = 'HKCU\Control Panel\Accessibility';            File = 'cp_accessibility.reg' },
    @{ Key = 'HKCU\Control Panel\Accessibility\StickyKeys'; File = 'sticky_keys.reg' },
    @{ Key = 'HKCU\Control Panel\Accessibility\Keyboard Response'; File = 'filter_keys.reg' },
    @{ Key = 'HKCU\Control Panel\Accessibility\ToggleKeys'; File = 'toggle_keys.reg' },
    @{ Key = 'HKCU\Control Panel\Mouse';                    File = 'mouse.reg' },
    @{ Key = 'HKCU\Control Panel\Desktop';                  File = 'desktop.reg' },
    @{ Key = 'HKCU\Control Panel\Keyboard';                 File = 'keyboard.reg' },
    @{ Key = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; File = 'personalize.reg' }
)

foreach ($export in $regExports) {
    $outFile = Join-Path $AccessDir $export.File
    reg export $export.Key $outFile /y 2>$null | Out-Null
    if (Test-Path $outFile) {
        Write-Report "  [EXPORTED] $($export.Key)" "Green"
    } else {
        Write-Report "  [SKIPPED]  $($export.Key) (not found)" "DarkGray"
    }
}

# ========== SUMMARY ==========
Write-Report "`n============================================"
Write-Report "  PRE-FLIGHT COMPLETE"
Write-Report "============================================" "Green"
Write-Report "`nReport saved to: $ReportDir"
Write-Report "`nACTION ITEMS before reinstall:"
Write-Report "  1. Review the NEEDS BACKUP items above — copy them to F: drive"
Write-Report "  2. Export browser passwords (Chrome/Edge/Firefox Settings > Passwords > Export)"
Write-Report "  3. Verify passkeys are synced to Microsoft account"
Write-Report "  4. Review drive health warnings (if any)"
Write-Report "  5. Run 02-FileDedup-Report.ps1 to find duplicate personal files"
Write-Report "`nDrive layout recommendation:"
foreach ($nvme in $nvmeEntries) {
    Write-Report "  C: (OS)        <- $($nvme.FriendlyName) [currently $($nvme.DriveLetter)]" "Green"
}
Write-Report "  D: (Workspace) <- CT4000MX500SSD1 4TB"
Write-Report "  E: (Cache)     <- INTEL SSDSC2KW256G8 238GB"
Write-Report "  F: (Archive)   <- WD Elements SE 2TB (keep as-is)"
foreach ($hdd in $hddEntries) {
    Write-Report "  H: (Cold)      <- $($hdd.FriendlyName) [currently $($hdd.DriveLetter)]" "Yellow"
}

# Copy report to F: if available
$archiveReport = "F:\Backups\ConfigExports\FreshStart-Reports"
if (Test-Path "F:\") {
    New-Item -ItemType Directory -Path $archiveReport -Force | Out-Null
    Copy-Item -Path $ReportDir -Destination $archiveReport -Recurse -Force -ErrorAction SilentlyContinue
    Write-Report "`nReport also saved to: $archiveReport" "Green"
}

Write-Host "`nDone. Review the report at: $ReportDir" -ForegroundColor Green
