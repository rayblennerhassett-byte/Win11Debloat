#Requires -RunAsAdministrator
<#
.SYNOPSIS
    File deduplication scanner. Single-paste into elevated PowerShell.
    READ-ONLY — scans and reports only, deletes nothing.
.DESCRIPTION
    Scans all drives for personal files, identifies duplicates by SHA256 hash,
    generates CSV report with keep/delete suggestions.
#>
[CmdletBinding()]
param(
    [string[]]$ScanPaths = @("$env:USERPROFILE","D:\","E:\","F:\","G:\","H:\"),
    [string]$ReportPath = "$env:USERPROFILE\Desktop"
)

$ErrorActionPreference = "Continue"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$FileExtensions = @(
    '*.jpg','*.jpeg','*.png','*.gif','*.bmp','*.tiff','*.tif','*.webp','*.heic',
    '*.raw','*.cr2','*.nef','*.arw','*.dng',
    '*.mp4','*.avi','*.mkv','*.mov','*.wmv','*.flv','*.webm','*.m4v','*.mpg','*.mpeg',
    '*.pdf','*.doc','*.docx','*.xls','*.xlsx','*.ppt','*.pptx','*.odt','*.txt','*.rtf',
    '*.mp3','*.flac','*.wav','*.aac','*.ogg','*.wma','*.m4a'
)

$ExcludePatterns = '\\(\$Recycle\.Bin|System Volume Information|Windows|Program Files|Program Files \(x86\)|node_modules|\.git)\\'

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  FILE DEDUPLICATION SCANNER" -ForegroundColor Cyan
Write-Host "  READ-ONLY — nothing will be deleted" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan

# ========== PHASE 1: FILE DISCOVERY ==========
Write-Host "`n[Phase 1/3] Discovering personal files..." -ForegroundColor Cyan

$allFiles = [System.Collections.ArrayList]::new()
foreach ($scanPath in $ScanPaths) {
    if (-not (Test-Path $scanPath)) {
        Write-Host "  Skipping $scanPath (not found)" -ForegroundColor DarkGray
        continue
    }
    Write-Host "  Scanning $scanPath..." -ForegroundColor Gray -NoNewline
    $files = Get-ChildItem -Path $scanPath -Recurse -File -Include $FileExtensions -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $ExcludePatterns }
    $files | ForEach-Object { $allFiles.Add($_) | Out-Null }
    Write-Host " $($files.Count) files" -ForegroundColor White
}

$totalSizeGB = [math]::Round(($allFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
Write-Host "`n  Total: $($allFiles.Count) files, ${totalSizeGB} GB" -ForegroundColor White

# ========== PHASE 2: SIZE GROUPING + HASHING ==========
Write-Host "`n[Phase 2/3] Identifying duplicates..." -ForegroundColor Cyan
Write-Host "  Grouping by file size (fast pre-filter)..." -ForegroundColor Gray

$sizeGroups = $allFiles | Group-Object Length | Where-Object { $_.Count -gt 1 }
$filesToHash = ($sizeGroups | ForEach-Object { $_.Group }).Count
Write-Host "  $filesToHash files share sizes with at least one other file" -ForegroundColor Gray

if ($filesToHash -eq 0) {
    Write-Host "`n  No duplicates found. All files have unique sizes." -ForegroundColor Green
    Write-Host "  Report: No dedup needed." -ForegroundColor Green
    exit 0
}

Write-Host "  Hashing (SHA256) — this may take a while for large video files..." -ForegroundColor Gray

$hashTable = @{}
$hashed = 0
$sha256 = [System.Security.Cryptography.SHA256]::Create()

foreach ($group in $sizeGroups) {
    foreach ($file in $group.Group) {
        $hashed++
        if ($hashed % 100 -eq 0) {
            Write-Progress -Activity "Hashing files" -Status "$hashed / $filesToHash" -PercentComplete (($hashed / $filesToHash) * 100)
        }
        try {
            $stream = [System.IO.File]::OpenRead($file.FullName)
            $hashBytes = $sha256.ComputeHash($stream)
            $stream.Close()
            $stream.Dispose()
            $hashString = [BitConverter]::ToString($hashBytes) -replace '-', ''

            if (-not $hashTable.ContainsKey($hashString)) {
                $hashTable[$hashString] = [System.Collections.ArrayList]::new()
            }
            $hashTable[$hashString].Add($file) | Out-Null
        } catch {
            # File locked or access denied — skip
        }
    }
}
Write-Progress -Activity "Hashing files" -Completed

# ========== PHASE 3: REPORT GENERATION ==========
Write-Host "`n[Phase 3/3] Generating report..." -ForegroundColor Cyan

$duplicates = $hashTable.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
$dupCount = ($duplicates | Measure-Object).Count
$dupFiles = ($duplicates | ForEach-Object { $_.Value } | Measure-Object).Count
$reclaimableBytes = 0

$report = [System.Collections.ArrayList]::new()
foreach ($dup in $duplicates) {
    $files = $dup.Value | Sort-Object LastWriteTime -Descending
    for ($i = 0; $i -lt $files.Count; $i++) {
        $action = if ($i -eq 0) { 'KEEP (newest)' } else { 'DUPLICATE' }
        if ($i -gt 0) { $reclaimableBytes += $files[$i].Length }
        $report.Add([PSCustomObject]@{
            Hash        = $dup.Key.Substring(0, 12)
            Action      = $action
            SizeMB      = [math]::Round($files[$i].Length / 1MB, 2)
            FileName    = $files[$i].Name
            FullPath    = $files[$i].FullName
            Modified    = $files[$i].LastWriteTime.ToString("yyyy-MM-dd HH:mm")
            Drive       = $files[$i].FullName.Substring(0, 2)
        }) | Out-Null
    }
}

# Export CSV
$csvPath = Join-Path $ReportPath "FreshStart-DedupReport-$Timestamp.csv"
$report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

# Summary
$reclaimableGB = [math]::Round($reclaimableBytes / 1GB, 2)
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  DEDUP SUMMARY" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Total personal files scanned: $($allFiles.Count)" -ForegroundColor White
Write-Host "  Total size:                   ${totalSizeGB} GB" -ForegroundColor White
Write-Host "  Duplicate groups found:       $dupCount" -ForegroundColor $(if ($dupCount -gt 0) { "Yellow" } else { "Green" })
Write-Host "  Duplicate files:              $dupFiles" -ForegroundColor $(if ($dupFiles -gt 0) { "Yellow" } else { "Green" })
Write-Host "  Space recoverable:            ${reclaimableGB} GB" -ForegroundColor $(if ($reclaimableGB -gt 1) { "Yellow" } else { "Green" })
Write-Host "`n  Report saved: $csvPath" -ForegroundColor Green
Write-Host "  Open the CSV, review DUPLICATE entries, delete what you don't need." -ForegroundColor White
Write-Host "  The KEEP suggestion is the newest copy — override as needed." -ForegroundColor White

# Copy to F: if available
if (Test-Path "F:\Backups") {
    $archiveCsv = "F:\Backups\ConfigExports\FreshStart-Reports\DedupReport-$Timestamp.csv"
    New-Item -ItemType Directory -Path (Split-Path $archiveCsv) -Force -ErrorAction SilentlyContinue | Out-Null
    Copy-Item $csvPath $archiveCsv -ErrorAction SilentlyContinue
    Write-Host "  Also saved to: $archiveCsv" -ForegroundColor Green
}
