<#
.SYNOPSIS
    Hardware Sentinel - Launcher
.DESCRIPTION
    Launches the Hardware Sentinel GUI with execution policy bypass.
.COMPANY
    CG Technology (https://github.com/CG-Technology)
#>

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$GuiScript = Join-Path $ScriptDir "src\Run-SentinelGUI.ps1"

if (Test-Path $GuiScript) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$GuiScript`""
} else {
    Write-Error "Could not find Sentinel GUI script at $GuiScript"
    Pause
}
