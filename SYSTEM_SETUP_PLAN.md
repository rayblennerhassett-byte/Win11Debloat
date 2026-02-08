# FRESH START: Complete System Setup Plan
**Date:** 2026-02-08
**Hardware:** Ryzen 7 5700X3D / RTX 4070 Ti SUPER / 6 Drives
**Goal:** SOTA 2026 Windows 11 setup — zero bloat, optimal drive layout, accessibility baked in, clean file organization

---

## PHASE 0: BEFORE YOU TOUCH ANYTHING

### 0.1 Identify Which "SSD" is Actually an HDD
One of D: or E: is a Seagate ST1000DM003 mechanical HDD mislabeled as "SSD."
Run this to find out which:
```powershell
Get-Partition | Get-Disk | Select Number, FriendlyName, @{N='GB';E={[math]::Round($_.Size/1GB)}} | ft -Auto
# Cross-reference disk numbers with drive letters:
Get-Volume | Where DriveLetter | Select DriveLetter, FileSystemLabel, @{N='DiskNum';E={(Get-Partition -DriveLetter $_.DriveLetter).DiskNumber}} | ft -Auto
```

### 0.2 Back Up Personal Files First
Before any reinstall, secure irreplaceable data:
```powershell
# Inventory what exists across all drives
$Drives = @("C:\Users","D:\","E:\","F:\","G:\","H:\")
foreach ($d in $Drives) {
    if (Test-Path $d) {
        Write-Host "`n=== $d ===" -ForegroundColor Cyan
        Get-ChildItem $d -Depth 1 -Directory -ErrorAction SilentlyContinue |
            Select FullName, @{N='SizeGB';E={
                [math]::Round(((Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum / 1GB), 2)
            }}
    }
}
```
Run this and save the output. It shows where your data lives and how big each folder is.

### 0.3 Back Up Accessibility Settings
Export your current settings so we can restore them after reinstall:
```powershell
reg export "HKCU\Software\Microsoft\Accessibility" "$env:USERPROFILE\Desktop\accessibility_backup.reg"
reg export "HKCU\Control Panel\Accessibility" "$env:USERPROFILE\Desktop\accessibility_cp_backup.reg"
reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "$env:USERPROFILE\Desktop\theme_backup.reg"
# Also screenshot: Settings > Accessibility (all pages) for reference
```

---

## PHASE 1: OPTIMAL DRIVE LAYOUT

### Current State (Problems)
- C: (238GB Intel SATA SSD) is the boot drive — too small, 47GB free, not your fastest disk
- CT1000P3SSD8 (1TB NVMe) is your fastest drive but is NOT the boot drive
- One of D:/E: is a mechanical HDD mislabeled as SSD
- G: (466GB ADATA) is nearly full with 15GB free — old drive, candidate for retirement
- Data scattered across 6 drives with no clear organization

### Target State

| Drive | Physical Disk | Role | Why |
|:---|:---|:---|:---|
| **C:** | CT1000P3SSD8 (1TB NVMe) | **SYSTEM** — Windows, apps, dev tools | Fastest drive = boot drive. 1TB is plenty for OS + tools |
| **D:** | CT4000MX500SSD1 (4TB SATA SSD) | **WORKSPACE** — Games, LLM projects, active development | Largest SSD. Games + dev need space + decent speed |
| **E:** | INTEL SSDSC2KW256G8 (238GB SATA SSD) | **CACHE/TEMP** — Shader cache, browser cache, temp files, swap overflow | Keeps junk off the NVMe. Small but fast enough for cache |
| **F:** | WD Elements SE (2TB external HDD) | **ARCHIVE** — Personal files, drone footage, photos, documents, family | Portable, removable, for organized long-term storage |
| **G:** | — | **RETIRE** | Back up remaining 451GB to F: or H:, then repurpose or shelve |
| **H:** | ST1000DM003 (1TB HDD) | **COLD STORAGE / OVERFLOW** — Large downloads, ISOs, datasets, rarely-accessed files | Slow HDD. Don't put anything that needs speed here |

> **Note:** If you want to keep the Seagate HDD in the system at all. It's from ~2012 and may be approaching end-of-life. Run `Get-PhysicalDisk | Get-StorageReliabilityCounter` to check its health. Same for the ADATA.

### Migration Steps
1. Back up everything valuable (Phase 0)
2. Create Win11 USB installer (see Phase 2)
3. Disconnect all drives EXCEPT the NVMe (CT1000P3SSD8)
4. Install Windows fresh on the NVMe — it becomes C:
5. Reconnect other drives one at a time
6. Reassign drive letters in Disk Management to match the table above
7. Format the old Intel 238GB SSD as E: (cache/temp)
8. Move data to correct locations per the directory structures below

---

## PHASE 2: ZERO-BLOAT WINDOWS INSTALL

### 2.1 Create Unattended Install Media
Use an `autounattend.xml` to skip the OOBE bloat and disable telemetry from first boot.

Key settings for the autounattend.xml:
- Skip Microsoft account requirement (use local account)
- Disable Copilot, Cortana, widgets
- Disable telemetry and diagnostic data
- Skip "Let's customize your experience" screens
- Disable suggested/promoted apps
- Set region/language/keyboard automatically

Tool: Use [Schneegans Unattend Generator](https://schneegans.de/windows/unattend-generator/) — web-based, generates the XML. Or craft manually.

### 2.2 Post-Install: Win11Debloat
After first boot, run Win11Debloat (this repo) to catch everything the autounattend didn't:
```powershell
# From elevated PowerShell:
irm "https://raw.githubusercontent.com/Raphire/Win11Debloat/master/Get.ps1" | iex
```
Or clone and run locally with custom config for reproducibility (preferred for repeated reinstalls).

### 2.3 Create a Win11Debloat Config for Your Setup
Save a custom config so every future reinstall is identical:
```
# Win11Debloat custom config — save as CustomConfig.json alongside the script
# Include: Remove bloatware apps, disable telemetry, disable Copilot,
# disable widgets, disable suggestions, restore classic context menu,
# disable Bing in Start, disable tips/tricks notifications
```

---

## PHASE 3: DIRECTORY STRUCTURES

### C: (1TB NVMe) — SYSTEM
```
C:\
├── Windows\
├── Program Files\          # System apps, dev tools (VS Code, Git, Python, Node)
├── Program Files (x86)\
├── Users\YourName\
│   ├── .claude\            # Claude Code config
│   ├── .ssh\               # SSH keys
│   └── Desktop\            # Keep clean — shortcuts only
├── Dev\                    # Small/active projects only (overflow to D:\Dev)
│   └── tools\              # CLI tools, SDKs
└── Temp\                   # Redirect TEMP/TMP here (off user profile)
```

### D: (4TB SATA SSD) — WORKSPACE
```
D:\
├── Games\
│   ├── Steam\              # Steam library folder
│   ├── GamePass\           # Xbox/Game Pass install location
│   └── Epic\               # Epic Games library
├── Dev\
│   ├── projects\           # All active code projects
│   ├── llm-workspace\     # LLM/AI development
│   │   ├── models\         # Local model weights (Ollama, LM Studio)
│   │   ├── datasets\       # Training/eval data
│   │   └── outputs\        # Generation outputs
│   └── repos\              # Cloned repositories
├── VMs\                    # Virtual machines, WSL distros
└── Scratch\                # Temporary working space (not backed up)
```

### E: (238GB SATA SSD) — CACHE/TEMP
```
E:\
├── ShaderCache\            # GPU shader cache (symlink from default location)
├── BrowserCache\           # Chrome/Firefox cache redirect
├── WindowsTemp\            # Redirect %TEMP% here
├── DownloadStaging\        # Downloads land here first, then sort to D: or F:
└── BuildCache\             # npm cache, pip cache, Docker layers
```
Set environment variables to redirect caches here:
```powershell
# Add to post-install script:
[Environment]::SetEnvironmentVariable("TEMP", "E:\WindowsTemp", "User")
[Environment]::SetEnvironmentVariable("TMP", "E:\WindowsTemp", "User")
# npm cache:
npm config set cache E:\BuildCache\npm
# pip cache:
[Environment]::SetEnvironmentVariable("PIP_CACHE_DIR", "E:\BuildCache\pip", "User")
```

### F: (2TB External HDD) — ARCHIVE
```
F:\
├── Personal\
│   ├── Photos\
│   │   ├── 2020\
│   │   ├── 2021\
│   │   ├── ...
│   │   └── 2026\
│   ├── Drone\
│   │   ├── Raw\            # Original footage
│   │   └── Edited\         # Final cuts
│   ├── Documents\
│   │   ├── Letters\
│   │   ├── Financial\
│   │   ├── Medical\
│   │   └── Legal\
│   ├── Family\
│   │   ├── Photos\
│   │   ├── Videos\
│   │   └── Scans\          # Scanned physical documents
│   └── Projects\           # Completed/archived project exports
├── Backups\
│   ├── SystemImages\       # Periodic C: drive images
│   └── ConfigExports\      # Exported settings, reg files, app configs
└── Media\
    ├── Music\
    └── Video\
```

### H: (1TB HDD) — COLD STORAGE
```
H:\
├── ISOs\                   # Windows ISOs, Linux distros, tool installers
├── Datasets\               # Large datasets not actively used
├── Downloads-Archive\      # Old downloads worth keeping but not needing speed
└── Overflow\               # Anything that doesn't fit elsewhere
```

---

## PHASE 4: PERSONAL FILE DEDUPLICATION & ORGANIZATION

### 4.1 Dedup Strategy
Before organizing, remove duplicates. Your files are spread across drives with "a lot of duplication."

**Tool: AllDup (Windows, free)** — best for this job. Handles large file sets, previews before deleting.
Alternatively: dupeGuru (cross-platform), or via WSL: `fdupes -r -d /mnt/`.

**Process:**
1. Stage all personal files to a single temporary location on H: (it has 1.9TB free)
2. Run AllDup/dupeGuru across the staged folder
3. Review duplicates — keep highest quality version (largest file, best resolution)
4. For drone footage: keep RAW originals, delete re-encoded duplicates
5. For photos: keep originals, delete thumbnails/previews/duplicates
6. Move deduplicated, organized files to F: in the archive structure above

### 4.2 Naming Convention
```
# Photos: YYYY-MM-DD_description_NNN.ext
2024-07-15_beach_sunset_001.jpg

# Drone footage: YYYY-MM-DD_location_flight-N.ext
2025-03-22_coastal_cliffs_flight-2.mp4

# Documents: YYYY-MM-DD_type_description.ext
2024-01-15_letter_council_planning.pdf
```

### 4.3 Size Estimation
After dedup, typical reduction is 20-40% for media-heavy collections.
If you have ~1.3TB of personal files (F: has 1.3TB used + scattered elsewhere), expect ~800GB-1TB post-dedup. Fits comfortably on the 2TB WD Elements with room to grow.

---

## PHASE 5: ACCESSIBILITY (BAKED IN)

**[NEEDS YOUR INPUT]** — Tell me which accessibility features you use and I'll create:
1. A PowerShell script that applies all settings automatically post-install
2. Registry exports for settings that need reg keys
3. Group Policy preferences if applicable

Common options to consider:
- Display scaling / custom DPI
- Color filters / high contrast
- Mouse pointer size and color
- Cursor thickness
- Sticky Keys / Filter Keys / Toggle Keys
- Narrator / screen reader settings
- Text size in specific UI elements
- Reduce motion / transparency effects
- Dark mode (system + apps)
- Custom font rendering (ClearType tuning)

---

## PHASE 6: DEV ENVIRONMENT BOOTSTRAP

### One-Script Setup (Post-Install)
Create a `bootstrap.ps1` that installs everything via winget:

```powershell
# Dev essentials
winget install Git.Git
winget install Microsoft.VisualStudioCode
winget install Python.Python.3.12
winget install OpenJS.NodeJS.LTS
winget install Docker.DockerDesktop

# LLM tooling
winget install Ollama.Ollama
# or LM Studio if preferred

# Terminal
winget install Microsoft.WindowsTerminal

# Utilities
winget install 7zip.7zip
winget install VideoLAN.VLC

# Claude Code (via npm, after Node installs)
npm install -g @anthropic-ai/claude-code
```

### WSL2 Setup
```powershell
wsl --install -d Ubuntu-24.04
# Then inside WSL:
# sudo apt update && sudo apt install build-essential python3-pip
```

### Git Config
```powershell
git config --global user.name "YourName"
git config --global user.email "your@email.com"
git config --global init.defaultBranch main
git config --global core.autocrlf true
```

---

## PHASE 7: GAME DRIVE OPTIMIZATION

### D:\Games Setup
```powershell
# Set Steam library folder: Steam > Settings > Storage > Add D:\Games\Steam
# Set Xbox app install location: Settings > General > Default install location > D:\Games\GamePass
# Epic: Settings > Install Location > D:\Games\Epic

# DirectStorage is automatic on Windows 11 with NVMe — games on D: (SATA SSD)
# still benefit from GPU decompression but NVMe C: would be faster for load times.
# For your most-played games, consider keeping them on C: if space allows.
```

### Shader Cache Redirect
```powershell
# Move NVIDIA shader cache to E: (cache drive)
# NVIDIA Control Panel > Manage 3D Settings > Shader Cache Size > 10GB
# Then symlink the cache directory:
mklink /D "C:\Users\YourName\AppData\Local\NVIDIA\DXCache" "E:\ShaderCache\NVIDIA"
```

---

## PHASE 8: REINSTALL CHECKLIST

Save this as a checklist for every future reinstall:

- [ ] Back up C:\Users\YourName\.ssh, .claude, .gitconfig
- [ ] Export browser bookmarks + extensions list
- [ ] Note installed winget packages: `winget list > packages.txt`
- [ ] Save this plan + bootstrap.ps1 + accessibility script to F:\Backups\ConfigExports
- [ ] Disconnect all drives except NVMe
- [ ] Install Windows from USB with autounattend.xml
- [ ] Run Win11Debloat
- [ ] Run bootstrap.ps1
- [ ] Run accessibility script
- [ ] Reconnect drives, assign letters
- [ ] Verify F: archive intact

---

## HARDWARE HEALTH CHECK (Do This First)

Two of your drives are old — run this before trusting them with anything:

```powershell
# SMART health status
Get-PhysicalDisk | ForEach-Object {
    $disk = $_
    $health = $_ | Get-StorageReliabilityCounter
    [PSCustomObject]@{
        Name = $disk.FriendlyName
        MediaType = $disk.MediaType
        Health = $disk.HealthStatus
        Temp = $health.Temperature
        ReadErrors = $health.ReadErrorsTotal
        WearLevel = $health.Wear
        PowerOnHours = $health.PowerOnHours
    }
} | ft -Auto
```

**Drives at risk:**
- **ST1000DM003** (Seagate 1TB HDD, ~2012-era): Check power-on hours. If >40,000 hours, plan to replace.
- **ADATA SH14** (466GB, old portable): Nearly full, old model. Back up immediately.

---

## EXECUTION ORDER

1. **Phase 0** — Back up everything, export settings, run health check
2. **Phase 4.1** — Dedup personal files (before reinstall, while system is running)
3. **Phase 1** — Migrate OS to NVMe (requires Windows reinstall)
4. **Phase 2** — Zero-bloat install with autounattend + Win11Debloat
5. **Phase 3** — Create directory structures on all drives
6. **Phase 5** — Apply accessibility settings
7. **Phase 6** — Run dev bootstrap script
8. **Phase 7** — Configure game libraries
9. **Phase 4.2-4.3** — Organize deduplicated files into F: archive structure
10. **Phase 8** — Save all scripts/configs to F: for future reinstalls
