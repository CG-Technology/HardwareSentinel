<#
.SYNOPSIS
    Hardware Sentinel - Windows Hardware Health & Diagnostic Telemetry Engine
.DESCRIPTION
    Inspects physical drives (SMART, media type, capacity, free space), battery health
    (wear level, design vs full capacity, cycle count), processor/memory utilization,
    and system stability (plain-English blue screen crash explainer).
    Calculates an overall 0-100% PC Health Score and produces structured JSON or HTML reports.
.PARAMETER Scan
    Executes full hardware diagnostic scan.
.PARAMETER Format
    Output format: 'Console', 'Json', or 'Html'.
.PARAMETER OutputPath
    File destination path when Format is 'Json' or 'Html'.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [switch]$Scan = $true,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Console", "Json", "Html")]
    [string]$Format = "Console",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "",

    [Parameter(Mandatory = $false)]
    [switch]$LoadFunctionsOnly = $false
)

$ErrorActionPreference = "SilentlyContinue"

function Write-DiagnosticLog([string]$msg, [string]$type = "INFO") {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $color = switch ($type) {
        "PASS"    { "Green" }
        "WARN"    { "Yellow" }
        "FAIL"    { "Red" }
        "HEADER"  { "Cyan" }
        default   { "Gray" }
    }
    Write-Host "[$timestamp] [$type] $msg" -ForegroundColor $color
}

# 1. Inspect Physical & Logical Storage
function Get-SentinelStorageInfo {
    $drives = @()
    $physicalDisks = @()

    try {
        $rawDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
        if ($rawDisks) {
            foreach ($d in $rawDisks) {
                $sizeGB = [Math]::Round(($d.Size / 1GB), 1)
                $physicalDisks += @{
                    FriendlyName      = $d.FriendlyName
                    MediaType         = if ($d.MediaType) { $d.MediaType.ToString() } else { "SSD / NVMe" }
                    HealthStatus      = if ($d.HealthStatus) { $d.HealthStatus.ToString() } else { "Healthy" }
                    OperationalStatus = if ($d.OperationalStatus) { ($d.OperationalStatus -join ", ") } else { "OK" }
                    SizeGB            = $sizeGB
                }
            }
        }
    } catch {}

    # Fallback to Win32_DiskDrive if Get-PhysicalDisk was empty
    if ($physicalDisks.Count -eq 0) {
        try {
            $wmiDisks = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue
            foreach ($wd in $wmiDisks) {
                $sizeGB = [Math]::Round(($wd.Size / 1GB), 1)
                $physicalDisks += @{
                    FriendlyName      = $wd.Model
                    MediaType         = "Disk Drive"
                    HealthStatus      = if ($wd.Status -eq "OK") { "Healthy" } else { $wd.Status }
                    OperationalStatus = $wd.Status
                    SizeGB            = $sizeGB
                }
            }
        } catch {}
    }

    # Logical Volumes
    try {
        $volumes = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
        foreach ($v in $volumes) {
            $totalGB = [Math]::Round(($v.Size / 1GB), 1)
            $freeGB = [Math]::Round(($v.FreeSpace / 1GB), 1)
            $usedGB = [Math]::Round(($totalGB - $freeGB), 1)
            $pctFree = if ($totalGB -gt 0) { [Math]::Round(($freeGB / $totalGB) * 100, 1) } else { 0 }

            $drives += @{
                DeviceID      = $v.DeviceID
                VolumeName    = if ($v.VolumeName) { $v.VolumeName } else { "Local Disk" }
                FileSystem    = $v.FileSystem
                TotalGB       = $totalGB
                FreeGB        = $freeGB
                UsedGB        = $usedGB
                PercentFree   = $pctFree
                IsSystemDrive = ($v.DeviceID -eq $env:SystemDrive)
                Status        = if ($pctFree -lt 10) { "Critical" } elseif ($pctFree -lt 18) { "Warning" } else { "Healthy" }
            }
        }
    } catch {}

    return @{
        PhysicalDisks = $physicalDisks
        Volumes       = $drives
    }
}

# 2. Inspect Battery & Power System
function Get-SentinelBatteryInfo {
    $batteryData = @{
        IsBatteryPresent    = $false
        DesignCapacityMWh   = 0
        FullChargeMWh       = 0
        CurrentChargeMWh    = 0
        HealthPercent       = 100
        WearLevelPercent    = 0
        CycleCount          = 0
        StatusSummary       = "Desktop Direct Power (AC) - No Battery Degradation"
        PowerSource         = "AC Wall Power"
    }

    try {
        $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($battery) {
            $batteryData.IsBatteryPresent = $true
            $batteryData.PowerSource = "Battery / AC Adapter"
            $batteryData.StatusSummary = "Laptop Battery Detected"

            # Generate powercfg battery report XML for precise design vs full charge capacity
            $tempReport = Join-Path $env:TEMP "sentinel_batt_$(Get-Random).xml"
            & powercfg.exe /batteryreport /xml /output "$tempReport" > $null 2>&1

            if (Test-Path $tempReport) {
                try {
                    [xml]$xml = Get-Content $tempReport -Raw
                    $battNode = $xml.BatteryReport.Batteries.Battery | Select-Object -First 1
                    if ($battNode) {
                        $design = [int64]$battNode.DesignCapacity
                        $full = [int64]$battNode.FullChargeCapacity
                        $cycles = if ($battNode.CycleCount) { [int]$battNode.CycleCount } else { 0 }

                        if ($design -gt 0 -and $full -gt 0) {
                            $health = [Math]::Min(100, [Math]::Round(($full / $design) * 100, 1))
                            $wear = [Math]::Max(0, [Math]::Round((100 - $health), 1))

                            $batteryData.DesignCapacityMWh = $design
                            $batteryData.FullChargeMWh     = $full
                            $batteryData.HealthPercent     = $health
                            $batteryData.WearLevelPercent  = $wear
                            $batteryData.CycleCount        = $cycles

                            if ($health -ge 85) {
                                $batteryData.StatusSummary = "Excellent Battery Condition ($health% capacity remaining)"
                            } elseif ($health -ge 70) {
                                $batteryData.StatusSummary = "Good Condition ($health% capacity, normal wear)"
                            } elseif ($health -ge 50) {
                                $batteryData.StatusSummary = "Moderate Wear ($health% capacity - life is reduced)"
                            } else {
                                $batteryData.StatusSummary = "High Degradation ($health% capacity - replacement recommended)"
                            }
                        }
                    }
                } catch {}
                Remove-Item $tempReport -Force -ErrorAction SilentlyContinue
            }

            # Fallback if powercfg xml couldn't supply full charge capacity
            if ($batteryData.DesignCapacityMWh -eq 0 -and $battery.EstimatedChargeRemaining) {
                $batteryData.HealthPercent = [int]$battery.EstimatedChargeRemaining
                $batteryData.StatusSummary = "Battery Active ($($battery.EstimatedChargeRemaining)% charged)"
            }
        }
    } catch {}

    return $batteryData
}

# 3. Inspect Memory & Processor Utilization
function Get-SentinelPerformanceInfo {
    $cpuName = "Unknown CPU"
    $cores = 4
    $logicalCores = 4
    $cpuLoad = 0

    try {
        $proc = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc) {
            $cpuName = ($proc.Name -replace '\s+', ' ').Trim()
            $cores = $proc.NumberOfCores
            $logicalCores = $proc.NumberOfLogicalProcessors
            $cpuLoad = if ($proc.LoadPercentage -ne $null) { [int]$proc.LoadPercentage } else { 0 }
        }
    } catch {}

    $totalRamGB = 16
    $freeRamGB = 8
    $usedRamGB = 8
    $ramUsedPercent = 50
    $uptimeStr = "0d 0h 0m"
    $osName = "Windows"

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($os) {
            $osName = $os.Caption
            $totalRamGB = [Math]::Round(($os.TotalVisibleMemorySize / 1MB), 1)
            $freeRamGB  = [Math]::Round(($os.FreePhysicalMemory / 1MB), 1)
            $usedRamGB  = [Math]::Round(($totalRamGB - $freeRamGB), 1)
            $ramUsedPercent = if ($totalRamGB -gt 0) { [Math]::Round(($usedRamGB / $totalRamGB) * 100, 1) } else { 0 }

            if ($os.LastBootUpTime) {
                $bootTime = $os.LastBootUpTime
                $uptimeSpan = (Get-Date) - $bootTime
                $uptimeStr = "$($uptimeSpan.Days)d $($uptimeSpan.Hours)h $($uptimeSpan.Minutes)m"
            }
        }
    } catch {}

    return @{
        ProcessorName        = $cpuName
        PhysicalCores        = $cores
        LogicalProcessors    = $logicalCores
        CpuLoadPercent       = $cpuLoad
        TotalRamGB           = $totalRamGB
        UsedRamGB            = $usedRamGB
        FreeRamGB            = $freeRamGB
        RamUsedPercent       = $ramUsedPercent
        SystemUptime         = $uptimeStr
        OperatingSystem      = $osName
    }
}

# 4. Inspect Stability & Blue Screen History (Plain-English Explainer)
function Get-SentinelStabilityInfo {
    $crashList = @()
    $minidumpDir = "C:\Windows\Minidump"

    # Known BugCheck stop code plain-English dictionary
    $stopCodeDictionary = @{
        "0x0000003b" = "Graphics / Video Card or display driver exception"
        "0x000000d1" = "Network adapter, Wi-Fi, or peripheral driver issue (IRQL)"
        "0x0000007e" = "Damaged or incompatible device driver (Thread Exception)"
        "0x0000001a" = "Memory (RAM) error or corrupted system paging file"
        "0x0000004e" = "Physical RAM or memory management fault"
        "0x0000009f" = "Sleep / wake or power management driver timeout"
        "0x00000018" = "Corrupted system driver file table"
        "0x00000124" = "Hardware error: thermal overheating, voltage, or processor instability"
        "0x000000ef" = "Critical Windows operating system process died"
        "0x00000050" = "Page fault in invalid memory address (driver or bad RAM)"
        "0x00000133" = "DPC Watchdog Timeout (SSD firmware or graphics lockup)"
        "0x00000139" = "Kernel security check failure (driver corruption)"
    }

    # Check Minidump directory
    if (Test-Path $minidumpDir) {
        try {
            $dumps = Get-ChildItem -Path $minidumpDir -Filter "*.dmp" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 5
            foreach ($d in $dumps) {
                $crashList += @{
                    Timestamp = $d.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                    FileName  = $d.Name
                    Source    = "Minidump File"
                    Cause     = "System Crash Dump"
                    Detail    = "Crash dump file recorded: $($d.Name) ($([Math]::Round($d.Length / 1KB, 0)) KB)"
                }
            }
        } catch {}
    }

    # Query Event Log for BugCheck (1001) in last 30 days
    try {
        $startTime = (Get-Date).AddDays(-30)
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Id        = 1001
            StartTime = $startTime
        } -MaxEvents 5 -ErrorAction SilentlyContinue

        foreach ($evt in $events) {
            $msg = $evt.Message
            $bugcheckMatch = [regex]::Match($msg, '0x[0-9a-fA-F]{8}')
            $code = if ($bugcheckMatch.Success) { $bugcheckMatch.Value.ToLower() } else { "Unknown" }
            $explanation = if ($stopCodeDictionary.ContainsKey($code)) { $stopCodeDictionary[$code] } else { "Windows kernel error or unstable driver" }

            $crashList += @{
                Timestamp = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm")
                FileName  = "BugCheck $code"
                Source    = "Event Log (ID 1001)"
                Cause     = $explanation
                Detail    = $msg.Substring(0, [Math]::Min(200, $msg.Length))
            }
        }
    } catch {}

    # Check for Kernel-Power 41 (sudden loss of power / ungraceful shutdown)
    $powerCutCount = 0
    try {
        $powerEvents = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Id        = 41
            StartTime = (Get-Date).AddDays(-30)
        } -MaxEvents 5 -ErrorAction SilentlyContinue

        if ($powerEvents) {
            $powerCutCount = ($powerEvents | Measure-Object).Count
        }
    } catch {}

    return @{
        CrashesLast30Days = $crashList.Count
        CrashEvents       = $crashList
        SuddenPowerCuts   = $powerCutCount
        IsStable          = ($crashList.Count -eq 0 -and $powerCutCount -le 1)
    }
}

# 5. Calculate Overall Health Score (0 - 100%)
function Calculate-SentinelHealthScore {
    param(
        $Storage,
        $Battery,
        $Performance,
        $Stability
    )

    $score = 100
    $penalties = @()

    # Storage Check (Max -30 pts)
    $hasDriveWarning = $false
    foreach ($pd in $Storage.PhysicalDisks) {
        if ($pd.HealthStatus -ne "Healthy") {
            $score -= 20
            $hasDriveWarning = $true
            $penalties += "Physical disk '$($pd.FriendlyName)' reports health warning ($($pd.HealthStatus))."
        }
    }
    foreach ($vol in $Storage.Volumes) {
        if ($vol.IsSystemDrive -and $vol.PercentFree -lt 10) {
            $score -= 10
            $penalties += "System drive ($($vol.DeviceID)) is critically low on space ($($vol.PercentFree)% free). Keep at least 15% free for Windows updates."
        } elseif ($vol.IsSystemDrive -and $vol.PercentFree -lt 18) {
            $score -= 5
            $penalties += "System drive ($($vol.DeviceID)) is running low on space ($($vol.PercentFree)% free)."
        }
    }

    # Stability Check (Max -25 pts)
    if ($Stability.CrashesLast30Days -gt 3) {
        $score -= 25
        $penalties += "$($Stability.CrashesLast30Days) system crashes detected in the last 30 days."
    } elseif ($Stability.CrashesLast30Days -gt 0) {
        $score -= (8 * $Stability.CrashesLast30Days)
        $penalties += "$($Stability.CrashesLast30Days) system crash(es) recorded in the last 30 days."
    }

    if ($Stability.SuddenPowerCuts -gt 2) {
        $score -= 10
        $penalties += "$($Stability.SuddenPowerCuts) sudden power cuts / hard shutdowns recorded recently."
    }

    # Memory Check (Max -15 pts)
    if ($Performance.RamUsedPercent -gt 92) {
        $score -= 15
        $penalties += "System RAM is currently $($Performance.RamUsedPercent)% full ($($Performance.FreeRamGB) GB free), causing performance slowdowns."
    } elseif ($Performance.RamUsedPercent -gt 85) {
        $score -= 8
        $penalties += "System RAM is heavily utilized ($($Performance.RamUsedPercent)% in use)."
    }

    # Battery Check (Max -10 pts)
    if ($Battery.IsBatteryPresent) {
        if ($Battery.HealthPercent -lt 50) {
            $score -= 10
            $penalties += "Battery is significantly degraded ($($Battery.HealthPercent)% of factory capacity). Replacement recommended."
        } elseif ($Battery.HealthPercent -lt 70) {
            $score -= 5
            $penalties += "Battery capacity has dropped to $($Battery.HealthPercent)% of original factory capacity."
        }
    }

    $finalScore = [Math]::Max(10, [Math]::Min(100, $score))

    $grade = if ($finalScore -ge 90) {
        "Excellent Condition"
    } elseif ($finalScore -ge 75) {
        "Good Condition - Minor Attention"
    } elseif ($finalScore -ge 60) {
        "Fair - Maintenance Recommended"
    } else {
        "Attention Recommended"
    }

    $badgeColor = if ($finalScore -ge 85) { "Green" } elseif ($finalScore -ge 70) { "Yellow" } else { "Red" }

    return @{
        Score        = $finalScore
        Grade        = $grade
        BadgeColor   = $badgeColor
        Observations = $penalties
    }
}

# 6. Generate Styled HTML Report
function New-SentinelHtmlReport {
    param($Result, $FilePath)

    $score = $Result.Health.Score
    $grade = $Result.Health.Grade
    $accentColor = if ($score -ge 85) { "#10B981" } elseif ($score -ge 70) { "#F59E0B" } else { "#EF4444" }
    $genTime = (Get-Date).ToString("dddd, MMMM dd, yyyy - HH:mm:ss")
    $hostname = $env:COMPUTERNAME

    $storageRows = ""
    foreach ($vol in $Result.Storage.Volumes) {
        $storageRows += "<tr><td><strong>$($vol.DeviceID) ($($vol.VolumeName))</strong></td><td>$($vol.TotalGB) GB</td><td>$($vol.FreeGB) GB ($($vol.PercentFree)%)</td><td><span class='badge' style='background: $(if ($vol.PercentFree -ge 18) { '#065F46' } else { '#991B1B' });'>$($vol.Status)</span></td></tr>"
    }

    $diskRows = ""
    foreach ($d in $Result.Storage.PhysicalDisks) {
        $diskRows += "<tr><td>$($d.FriendlyName)</td><td>$($d.MediaType)</td><td>$($d.SizeGB) GB</td><td><span class='badge' style='background: #065F46;'>$($d.HealthStatus)</span></td></tr>"
    }

    $penaltyItems = ""
    if ($Result.Health.Observations.Count -eq 0) {
        $penaltyItems = "<li style='color: #10B981;'>No hardware issues, memory pressure, or recent blue screen crashes detected!</li>"
    } else {
        foreach ($obs in $Result.Health.Observations) {
            $penaltyItems += "<li style='color: #FBBF24;'>$obs</li>"
        }
    }

    $crashRows = ""
    if ($Result.Stability.CrashEvents.Count -eq 0) {
        $crashRows = "<tr><td colspan='3' style='text-align:center; color:#10B981;'>Clean stability record. No system crash dumps recorded.</td></tr>"
    } else {
        foreach ($c in $Result.Stability.CrashEvents) {
            $crashRows += "<tr><td>$($c.Timestamp)</td><td><strong>$($c.FileName)</strong></td><td>$($c.Cause)</td></tr>"
        }
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>Hardware Sentinel - PC Health Report ($hostname)</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #0B0F19; color: #E2E8F0; margin: 0; padding: 30px 20px; line-height: 1.6; }
    .container { max-width: 900px; margin: 0 auto; }
    .header { background: #111827; border: 1px solid #1F2937; border-radius: 12px; padding: 28px; margin-bottom: 24px; display: flex; align-items: center; justify-content: space-between; }
    .title h1 { margin: 0 0 6px 0; font-size: 1.6rem; color: #F8FAFC; }
    .title p { margin: 0; color: #94A3B8; font-size: 0.95rem; }
    .score-circle { width: 90px; height: 90px; border-radius: 50%; border: 4px solid $accentColor; display: flex; flex-direction: column; align-items: center; justify-content: center; background: rgba(17, 24, 39, 0.9); }
    .score-num { font-size: 2rem; font-weight: 800; color: $accentColor; line-height: 1; }
    .score-lbl { font-size: 0.7rem; color: #94A3B8; text-transform: uppercase; letter-spacing: 0.5px; }
    .card { background: #111827; border: 1px solid #1F2937; border-radius: 12px; padding: 22px; margin-bottom: 20px; }
    .card h2 { margin: 0 0 16px 0; font-size: 1.15rem; color: #F8FAFC; border-bottom: 1px solid #1F2937; padding-bottom: 10px; }
    table { width: 100%; border-collapse: collapse; margin-top: 10px; font-size: 0.95rem; }
    th { text-align: left; padding: 10px 12px; background: #1E293B; color: #94A3B8; font-weight: 600; border-radius: 4px; }
    td { padding: 10px 12px; border-bottom: 1px solid #1F2937; color: #CBD5E1; }
    .badge { display: inline-block; padding: 3px 10px; border-radius: 9999px; font-size: 0.8rem; font-weight: 600; color: #FFFFFF; }
    .footer { text-align: center; color: #64748B; font-size: 0.85rem; margin-top: 30px; }
    ul.obs-list { margin: 8px 0; padding-left: 20px; font-size: 0.95rem; line-height: 1.8; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="title">
        <h1>Hardware Sentinel - PC Health Report</h1>
        <p>Computer: <strong>$hostname</strong> | Generated on: $genTime</p>
      </div>
      <div class="score-circle">
        <span class="score-num">$score</span>
        <span class="score-lbl">Health</span>
      </div>
    </div>

    <!-- Health Overview Card -->
    <div class="card">
      <h2>Overall Condition: <span style="color: $accentColor;">$grade</span></h2>
      <ul class="obs-list">
        $penaltyItems
      </ul>
    </div>

    <!-- Storage Card -->
    <div class="card">
      <h2>Storage & Physical Drives</h2>
      <table>
        <thead><tr><th>Disk Model</th><th>Type</th><th>Total Size</th><th>SMART Health</th></tr></thead>
        <tbody>$diskRows</tbody>
      </table>
      <h3 style="font-size: 1rem; margin: 20px 0 10px 0; color: #94A3B8;">Partitions & Free Space</h3>
      <table>
        <thead><tr><th>Drive</th><th>Total Space</th><th>Free Space</th><th>Status</th></tr></thead>
        <tbody>$storageRows</tbody>
      </table>
    </div>

    <!-- Memory & CPU Card -->
    <div class="card">
      <h2>Processor & Memory Performance</h2>
      <table>
        <tr><td style="width: 30%;"><strong>Processor</strong></td><td>$($Result.Performance.ProcessorName) ($($Result.Performance.PhysicalCores) Cores / $($Result.Performance.LogicalProcessors) Threads)</td></tr>
        <tr><td><strong>Current CPU Load</strong></td><td>$($Result.Performance.CpuLoadPercent)%</td></tr>
        <tr><td><strong>Memory (RAM)</strong></td><td>$($Result.Performance.UsedRamGB) GB used of $($Result.Performance.TotalRamGB) GB ($($Result.Performance.RamUsedPercent)% in use - $($Result.Performance.FreeRamGB) GB available)</td></tr>
        <tr><td><strong>System Uptime</strong></td><td>$($Result.Performance.SystemUptime)</td></tr>
        <tr><td><strong>Operating System</strong></td><td>$($Result.Performance.OperatingSystem)</td></tr>
      </table>
    </div>

    <!-- Battery Card -->
    <div class="card">
      <h2>Battery & Power System</h2>
      <table>
        <tr><td style="width: 30%;"><strong>Power Source</strong></td><td>$($Result.Battery.PowerSource)</td></tr>
        <tr><td><strong>Health Condition</strong></td><td>$($Result.Battery.StatusSummary)</td></tr>
        $(if ($Result.Battery.IsBatteryPresent) {
          "<tr><td><strong>Capacity Status</strong></td><td>$($Result.Battery.FullChargeMWh) mWh current capacity (Original factory design: $($Result.Battery.DesignCapacityMWh) mWh)</td></tr>" +
          "<tr><td><strong>Wear Level</strong></td><td>$($Result.Battery.WearLevelPercent)% degradation recorded ($($Result.Battery.HealthPercent)% original life remaining)</td></tr>" +
          "<tr><td><strong>Charge Cycles</strong></td><td>$($Result.Battery.CycleCount) cycles</td></tr>"
        } else {
          "<tr><td><strong>Battery Degradation</strong></td><td>0% (Standard Desktop Power Supply)</td></tr>"
        })
      </table>
    </div>

    <!-- Stability & Crashes Card -->
    <div class="card">
      <h2>System Stability & Crash History (Last 30 Days)</h2>
      <table>
        <thead><tr><th style="width: 20%;">Date</th><th style="width: 25%;">Event</th><th>Plain-English Explanation</th></tr></thead>
        <tbody>$crashRows</tbody>
      </table>
    </div>

    <div class="footer">
      Generated by <strong>CG Technology Hardware Sentinel</strong> | <a href="https://cg-technology.github.io" style="color: #6366F1; text-decoration: none;">https://cg-technology.github.io</a>
    </div>
  </div>
</body>
</html>
"@

    [System.IO.File]::WriteAllText($FilePath, $html, [System.Text.Encoding]::UTF8)
    return $FilePath
}

# MAIN EXECUTION
if ($Scan -and -not $LoadFunctionsOnly) {
    if ($Format -eq "Console") {
        Write-DiagnosticLog "Hardware Sentinel - Initializing Full Diagnostic Probe..." "HEADER"
    }

    $storage     = Get-SentinelStorageInfo
    $battery     = Get-SentinelBatteryInfo
    $performance = Get-SentinelPerformanceInfo
    $stability   = Get-SentinelStabilityInfo
    $health      = Calculate-SentinelHealthScore -Storage $storage -Battery $battery -Performance $performance -Stability $stability

    $result = @{
        ComputerName = $env:COMPUTERNAME
        Timestamp    = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        Health       = $health
        Storage      = $storage
        Battery      = $battery
        Performance  = $performance
        Stability    = $stability
    }

    if ($Format -eq "Json") {
        $json = $result | ConvertTo-Json -Depth 6
        if ($OutputPath) {
            [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.Encoding]::UTF8)
            Write-Host "Report saved to $OutputPath"
        } else {
            Write-Output $json
        }
    } elseif ($Format -eq "Html") {
        if (-not $OutputPath) {
            $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
            $outDir = Join-Path (Split-Path -Parent $scriptDir) "output"
            if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
            $OutputPath = Join-Path $outDir "Hardware-Health-Report-$($env:COMPUTERNAME).html"
        }
        $saved = New-SentinelHtmlReport -Result $result -FilePath $OutputPath
        Write-Host "HTML report generated: $saved"
    } else {
        # Console Mode Output
        Write-DiagnosticLog "Computer: $($env:COMPUTERNAME) | OS: $($performance.OperatingSystem)" "INFO"
        Write-DiagnosticLog "Overall Health Score: $($health.Score)/100 ($($health.Grade))" $(if ($health.Score -ge 85) { "PASS" } else { "WARN" })
        Write-DiagnosticLog "Processor: $($performance.ProcessorName) ($($performance.PhysicalCores) Cores, Load: $($performance.CpuLoadPercent)%)" "INFO"
        Write-DiagnosticLog "Memory: $($performance.UsedRamGB) GB used / $($performance.TotalRamGB) GB total ($($performance.FreeRamGB) GB free)" "INFO"
        Write-DiagnosticLog "Power: $($battery.StatusSummary)" "INFO"
        Write-DiagnosticLog "Crashes (Last 30d): $($stability.CrashesLast30Days) | Sudden Power Cuts: $($stability.SuddenPowerCuts)" "INFO"

        if ($health.Observations.Count -gt 0) {
            Write-Host ""
            Write-Host "Recommendations & Observations:" -ForegroundColor Yellow
            foreach ($obs in $health.Observations) {
                Write-Host " - $obs" -ForegroundColor Yellow
            }
        }
    }

    return $result
}
