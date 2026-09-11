# 🛡️ Hardware Sentinel

> **Zero-dependency Windows hardware diagnostics and 0–100% PC Health Score utility.**  
> Built for IT technicians, MSP engineers, and everyday users who need an instant, honest health assessment of any Windows PC or laptop.

[![GitHub release](https://img.shields.io/github/v/release/CG-Technology/HardwareSentinel?color=00D26A&label=Release)](https://github.com/CG-Technology/HardwareSentinel/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%2F%2011%20%2F%20Server-0078D4.svg)](https://microsoft.com/windows)
[![Dependencies](https://img.shields.io/badge/Dependencies-Zero%20(Pure%20PowerShell%20%2B%20WPF)-green.svg)](#features)

---

## ⚡ Key Highlights

- **🎯 0–100% PC Health Score & Trend Tracking**: An intelligent composite score weighted across Drive Health & Space (35%), Stability & Blue Screens (25%), Battery & Power (20%), and CPU/RAM Load (20%). Automatically saves scan history to `%LOCALAPPDATA%\HardwareSentinel\history.json` and tracks performance deltas over time (e.g. `+5% vs prior scan`).
- **🚀 One-Click System Utilities Toolbar**: Direct shortcuts to native Windows diagnostic and maintenance tools:
  - **Stability Timeline**: One-click launcher for Windows Reliability Monitor (`perfmon /rel`).
  - **Storage Cleanup**: Instant access to Windows Storage Sense (`ms-settings:storagesense`) and Disk Cleanup (`cleanmgr.exe`).
  - **Resource Monitor & Task Manager**: Direct shortcuts to `resmon.exe` and `taskmgr.exe`.
- **🧠 Hardware Specs & Upgrade Intelligence**:
  - **RAM Upgradability**: Inspects physical memory modules and motherboard slots (e.g. `2 of 4 slots used @ 3200 MHz`), helping users determine whether they can easily upgrade their RAM.
  - **GPU & Display Adapter**: Surfaces dedicated/integrated graphics model, VRAM in GB, and flags outdated drivers (>12 months).
  - **Drive Media Types**: Clear badging for high-speed **NVMe SSD**, standard **SATA SSD**, and mechanical **HDD**.
- **🛡️ Security & Windows Baseline Audit**:
  - **BitLocker Drive Encryption**: Reports whether the system drive is Encrypted (Protected) or Unencrypted.
  - **Pending Reboot Detection**: Detects if Windows updates or servicing operations are awaiting a restart.
  - **TPM 2.0 & Secure Boot**: Inspects hardware security module and UEFI Secure Boot readiness.
- **🌲 Interactive Disk Space Visualizer**: Click into the Storage section to launch an interactive, hierarchical disk visualizer with folder tree search/filtering, size percentage bars, a **Largest Files Finder** (files >= 50MB), and a native **"Move to Recycle Bin"** action (with standard Windows confirmation modal).
- **🔋 Intelligent Power & Battery Diagnostics**: Queries full OEM battery reports using native Windows telemetry (`powercfg.exe /batteryreport /xml`). Calculates design vs. full capacity degradation wear %, lifetime cycle count, and estimates remaining battery health. *Gracefully detects desktop PCs on wall power without score penalties.*
- **💥 Crash & BlueScreen History**: Reads minidumps (`C:\Windows\Minidump`) and Windows Event Log system events (BugCheck 1001 and Kernel-Power 41). Automatically translates cryptic NTSTATUS / HEX stop codes into plain English explanations (e.g. `CRITICAL_PROCESS_DIED`, `PAGE_FAULT_IN_NONPAGED_AREA`).
- **🖥️ Dual Mode (GUI + CLI)**:
  - **Modern Dark WPF Dashboard**: Sleek, slate-dark UI (`#0B0F19`) featuring circular gauge animations, status chips, real-time scanning progress, and instant copy/save actions.
  - **Headless CLI / Scriptable Engine**: Return clean PowerShell objects (`[PSCustomObject]`) or JSON directly to stdout for RMM scripts, automation, and scheduled checks.
- **📄 Standalone HTML Report**: Generate a branded, self-contained HTML report with CSS styling that can be emailed to clients or attached to support tickets.
- **📦 Zero External Dependencies**: 100% native PowerShell 5.1+ and .NET Framework 4.8. No Python, node, or third-party DLLs required.

---

## 🚀 Getting Started

### Option 1: Run the Modern Dashboard (GUI)
Simply double-click or run from PowerShell:
```powershell
.\Run-Sentinel.ps1
```
Or launch the GUI script directly:
```powershell
powershell -ExecutionPolicy Bypass -File .\src\Run-SentinelGUI.ps1
```

### Option 2: Command-Line Usage (CLI & Automation)
Dot-source or run `src/HardwareSentinel.ps1` in any terminal:

```powershell
# Run full diagnostic scan and display in console
.\src\HardwareSentinel.ps1

# Generate a standalone HTML report
.\src\HardwareSentinel.ps1 -ExportHtml -HtmlPath ".\PC-Health-Report.html"

# Silent scan outputting pure JSON (ideal for RMM or CI/CD pipelines)
.\src\HardwareSentinel.ps1 -Quiet -AsJson | Out-File ".\health.json"

# In your own automation scripts:
$Report = .\src\HardwareSentinel.ps1 -Quiet
Write-Host "PC Health Score: $($Report.HealthScore)%" -ForegroundColor Green
```

---

## 📊 Health Score Breakdown

| Weight | Diagnostic Module | What It Checks |
| :--- | :--- | :--- |
| **35%** | **Storage & Free Space** | SMART physical drive health, media type, and remaining system drive capacity. |
| **25%** | **System Stability & Crashes** | Windows minidumps and unexpected shutdowns in the last 30 days. |
| **20%** | **Power & Battery Health** | Battery wear level, charge cycles, or desktop AC power continuity. |
| **20%** | **CPU & Memory Load** | Processor load, RAM utilization, and system uptime. |

### Grading Scale
- 🟢 **85 – 100%**: Excellent (Healthy PC, no immediate concerns)
- 🟡 **70 – 84%**: Good / Monitor (Minor issues such as high RAM usage or modest battery wear)
- 🔴 **Below 70%**: Action Needed (Storage drive warnings, critically low disk space, or recent crash loops)

---

## 🛠️ System Requirements

- **Operating System**: Windows 10, Windows 11, or Windows Server 2016+
- **PowerShell**: Windows PowerShell 5.1 or PowerShell 7+
- **Permissions**: Administrator privileges are recommended to inspect SMART drive health and Minidump directories. If run as non-admin, Hardware Sentinel continues running with graceful user-mode fallbacks.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Developed with ❤️ by **[CG Technology](https://github.com/CG-Technology)**.

