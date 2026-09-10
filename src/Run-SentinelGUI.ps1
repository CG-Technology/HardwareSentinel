<#
.SYNOPSIS
    Hardware Sentinel - Modern WPF Desktop Dashboard
.DESCRIPTION
    Launches the Hardware Sentinel desktop interface displaying the 0-100% PC Health Score,
    storage integrity, battery wear level, processor/memory utilization, and plain-English
    crash history.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$engineScript = Join-Path $scriptDir "HardwareSentinel.ps1"

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Hardware Sentinel - PC Health &amp; Diagnostics"
        Height="700" Width="900"
        MinHeight="600" MinWidth="800"
        WindowStartupLocation="CenterScreen"
        Background="#0B0F19"
        Foreground="#E2E8F0"
        FontFamily="Segoe UI, Inter, sans-serif">
    
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#E2E8F0"/>
        </Style>
        <Style x:Key="CardBorder" TargetType="Border">
            <Setter Property="Background" Value="#111827"/>
            <Setter Property="BorderBrush" Value="#1F2937"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="10"/>
            <Setter Property="Padding" Value="16"/>
        </Style>
        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="Foreground" Value="#F8FAFC"/>
            <Setter Property="BorderBrush" Value="#334155"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#334155"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#6366F1"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource ActionButton}">
            <Setter Property="Background" Value="#4F46E5"/>
            <Setter Property="BorderBrush" Value="#6366F1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#4338CA"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/> <!-- Header -->
            <RowDefinition Height="Auto"/> <!-- Score Hero Card -->
            <RowDefinition Height="*"/>    <!-- 4 Diagnostic Cards -->
            <RowDefinition Height="Auto"/> <!-- Footer status -->
        </Grid.RowDefinitions>

        <!-- Header -->
        <Grid Grid.Row="0" Margin="0,0,0,16">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <StackPanel Grid.Column="0">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Background="#1E1B4B" BorderBrush="#4F46E5" BorderThickness="1" CornerRadius="6" Width="32" Height="32" Margin="0,0,10,0">
                        <TextBlock Text="🛡️" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="Hardware Sentinel" FontSize="20" FontWeight="Bold" Foreground="#F8FAFC" VerticalAlignment="Center"/>
                    <Border Background="#065F46" CornerRadius="10" Padding="8,2" Margin="10,0,0,0" VerticalAlignment="Center">
                        <TextBlock Text="v1.0.0" FontSize="11" FontWeight="Bold" Foreground="#34D399"/>
                    </Border>
                </StackPanel>
                <TextBlock x:Name="TxtMachineSubtitle" Text="Computer: Checking... | OS: Windows" FontSize="12" Foreground="#94A3B8" Margin="42,4,0,0"/>
            </StackPanel>

            <!-- Top Action Buttons -->
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                <Button x:Name="BtnRefresh" Style="{StaticResource ActionButton}" Content="🔄 Rescan" Margin="0,0,8,0"/>
                <Button x:Name="BtnSaveReport" Style="{StaticResource PrimaryButton}" Content="📄 Save Report (.html)" Margin="0,0,8,0"/>
                <Button x:Name="BtnCopySummary" Style="{StaticResource ActionButton}" Content="📋 Copy Summary"/>
            </StackPanel>
        </Grid>

        <!-- Score Hero Card -->
        <Border Grid.Row="1" Style="{StaticResource CardBorder}" Margin="0,0,0,16">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="100"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Health Score Dial -->
                <Border x:Name="BorderScoreCircle" Grid.Column="0" Width="85" Height="85" CornerRadius="42.5" BorderThickness="4" BorderBrush="#10B981" Background="#0F172A">
                    <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                        <TextBlock x:Name="TxtScoreNumber" Text="--" FontSize="30" FontWeight="ExtraBold" Foreground="#10B981" HorizontalAlignment="Center" LineHeight="32"/>
                        <TextBlock Text="HEALTH" FontSize="9" FontWeight="Bold" Foreground="#94A3B8" HorizontalAlignment="Center" Margin="0,-2,0,0"/>
                    </StackPanel>
                </Border>

                <!-- Score Text & Observations -->
                <StackPanel Grid.Column="1" Margin="20,0,0,0" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock x:Name="TxtHealthGrade" Text="Analyzing PC Health..." FontSize="18" FontWeight="Bold" Foreground="#F8FAFC"/>
                        <Border x:Name="BadgeGrade" Background="#065F46" CornerRadius="12" Padding="8,2" Margin="10,0,0,0" VerticalAlignment="Center">
                            <TextBlock x:Name="TxtGradeBadge" Text="Scanning" FontSize="11" FontWeight="Bold" Foreground="#34D399"/>
                        </Border>
                    </StackPanel>
                    <TextBlock x:Name="TxtScoreSummary" Text="Inspecting drives, memory pressure, battery degradation, and crash history..." FontSize="13" Foreground="#94A3B8" Margin="0,4,0,6" TextWrapping="Wrap"/>
                    <TextBlock x:Name="TxtTopObservations" Text="" FontSize="12" Foreground="#FBBF24" TextWrapping="Wrap"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- 4 Diagnostic Cards Grid -->
        <Grid Grid.Row="2">
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Card 1: Storage & Drives -->
            <Border Grid.Row="0" Grid.Column="0" Style="{StaticResource CardBorder}" Margin="0,0,8,8">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
                        <TextBlock Text="💽" FontSize="16" Margin="0,0,6,0"/>
                        <TextBlock Text="Storage &amp; Drive Health" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC"/>
                    </StackPanel>
                    <StackPanel Grid.Row="1">
                        <TextBlock x:Name="TxtStorageSystemDrive" Text="C: Drive: Checking space..." FontSize="12" Foreground="#CBD5E1"/>
                        <ProgressBar x:Name="ProgressStorage" Height="8" Margin="0,6,0,8" Value="0" Maximum="100" Background="#1E293B" Foreground="#10B981" BorderThickness="0"/>
                        <TextBlock x:Name="TxtStorageDisks" Text="Physical Disks: Probing SMART..." FontSize="11" Foreground="#94A3B8" TextWrapping="Wrap"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Card 2: Battery & Power -->
            <Border Grid.Row="0" Grid.Column="1" Style="{StaticResource CardBorder}" Margin="8,0,0,8">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
                        <TextBlock Text="🔋" FontSize="16" Margin="0,0,6,0"/>
                        <TextBlock Text="Battery &amp; Power Health" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC"/>
                    </StackPanel>
                    <StackPanel Grid.Row="1">
                        <TextBlock x:Name="TxtBatteryCondition" Text="Power Source: Detecting..." FontSize="12" Foreground="#CBD5E1"/>
                        <ProgressBar x:Name="ProgressBattery" Height="8" Margin="0,6,0,8" Value="0" Maximum="100" Background="#1E293B" Foreground="#10B981" BorderThickness="0"/>
                        <TextBlock x:Name="TxtBatteryDetails" Text="Checking capacity and cycle counts..." FontSize="11" Foreground="#94A3B8" TextWrapping="Wrap"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Card 3: Processor & Memory -->
            <Border Grid.Row="1" Grid.Column="0" Style="{StaticResource CardBorder}" Margin="0,8,8,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
                        <TextBlock Text="🧠" FontSize="16" Margin="0,0,6,0"/>
                        <TextBlock Text="Processor &amp; Memory" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC"/>
                    </StackPanel>
                    <StackPanel Grid.Row="1">
                        <TextBlock x:Name="TxtProcessorName" Text="CPU: Detecting..." FontSize="12" Foreground="#CBD5E1"/>
                        <TextBlock x:Name="TxtMemoryUsage" Text="RAM: Probing utilization..." FontSize="12" Foreground="#CBD5E1" Margin="0,4,0,0"/>
                        <ProgressBar x:Name="ProgressMemory" Height="8" Margin="0,6,0,8" Value="0" Maximum="100" Background="#1E293B" Foreground="#6366F1" BorderThickness="0"/>
                        <TextBlock x:Name="TxtUptime" Text="Uptime: Calculating..." FontSize="11" Foreground="#94A3B8"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Card 4: Stability & Crashes -->
            <Border Grid.Row="1" Grid.Column="1" Style="{StaticResource CardBorder}" Margin="8,8,0,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
                        <TextBlock Text="💥" FontSize="16" Margin="0,0,6,0"/>
                        <TextBlock Text="Stability &amp; Crash History" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC"/>
                    </StackPanel>
                    <StackPanel Grid.Row="1">
                        <TextBlock x:Name="TxtCrashSummary" Text="Checking for blue screens in the last 30 days..." FontSize="12" Foreground="#CBD5E1"/>
                        <TextBlock x:Name="TxtCrashDetails" Text="No crashes recorded." FontSize="11" Foreground="#94A3B8" Margin="0,6,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </Grid>
            </Border>
        </Grid>

        <!-- Footer -->
        <Grid Grid.Row="3" Margin="0,16,0,0">
            <TextBlock x:Name="TxtStatusFooter" Text="Ready. Click Rescan to refresh hardware telemetry." FontSize="11" Foreground="#64748B"/>
            <TextBlock Text="CG Technology | https://cg-technology.github.io" FontSize="11" Foreground="#475569" HorizontalAlignment="Right"/>
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Element References
$txtMachineSubtitle = $window.FindName("TxtMachineSubtitle")
$borderScoreCircle  = $window.FindName("BorderScoreCircle")
$txtScoreNumber     = $window.FindName("TxtScoreNumber")
$txtHealthGrade     = $window.FindName("TxtHealthGrade")
$badgeGrade         = $window.FindName("BadgeGrade")
$txtGradeBadge      = $window.FindName("TxtGradeBadge")
$txtScoreSummary    = $window.FindName("TxtScoreSummary")
$txtTopObservations = $window.FindName("TxtTopObservations")

$txtStorageSystemDrive = $window.FindName("TxtStorageSystemDrive")
$progressStorage       = $window.FindName("ProgressStorage")
$txtStorageDisks       = $window.FindName("TxtStorageDisks")

$txtBatteryCondition   = $window.FindName("TxtBatteryCondition")
$progressBattery       = $window.FindName("ProgressBattery")
$txtBatteryDetails     = $window.FindName("TxtBatteryDetails")

$txtProcessorName      = $window.FindName("TxtProcessorName")
$txtMemoryUsage        = $window.FindName("TxtMemoryUsage")
$progressMemory        = $window.FindName("ProgressMemory")
$txtUptime             = $window.FindName("TxtUptime")

$txtCrashSummary       = $window.FindName("TxtCrashSummary")
$txtCrashDetails       = $window.FindName("TxtCrashDetails")
$txtStatusFooter       = $window.FindName("TxtStatusFooter")

$btnRefresh            = $window.FindName("BtnRefresh")
$btnSaveReport         = $window.FindName("BtnSaveReport")
$btnCopySummary        = $window.FindName("BtnCopySummary")

$script:lastResult = $null

function Update-Dashboard($data) {
    if (-not $data) { return }
    $script:lastResult = $data

    $score = $data.Health.Score
    $grade = $data.Health.Grade

    # Score Color
    $brushColor = if ($score -ge 85) { "#10B981" } elseif ($score -ge 70) { "#F59E0B" } else { "#EF4444" }
    $badgeBgColor = if ($score -ge 85) { "#065F46" } elseif ($score -ge 70) { "#78350F" } else { "#7F1D1D" }

    $bc = New-Object System.Windows.Media.BrushConverter
    $borderScoreCircle.BorderBrush = $bc.ConvertFromString($brushColor)
    $txtScoreNumber.Foreground     = $bc.ConvertFromString($brushColor)
    $txtScoreNumber.Text           = $score.ToString()

    $txtHealthGrade.Text           = $grade
    $txtGradeBadge.Text            = if ($score -ge 85) { "Excellent" } elseif ($score -ge 70) { "Good" } else { "Action Needed" }
    $badgeGrade.Background         = $bc.ConvertFromString($badgeBgColor)

    $txtMachineSubtitle.Text = "Computer: $($data.ComputerName) | OS: $($data.Performance.OperatingSystem)"

    if ($data.Health.Observations.Count -eq 0) {
        $txtScoreSummary.Text = "Your computer hardware and operating system are in top condition with zero errors detected."
        $txtTopObservations.Text = "✓ Storage healthy   ✓ Memory available   ✓ Zero blue screen crashes"
        $txtTopObservations.Foreground = $bc.ConvertFromString("#10B981")
    } else {
        $txtScoreSummary.Text = "The diagnostic scan completed. $($data.Health.Observations.Count) item(s) recommended for review:"
        $txtTopObservations.Text = ($data.Health.Observations -join "`n")
        $txtTopObservations.Foreground = $bc.ConvertFromString("#FBBF24")
    }

    # Storage Card
    $sysDrive = $data.Storage.Volumes | Where-Object { $_.IsSystemDrive } | Select-Object -First 1
    if ($sysDrive) {
        $txtStorageSystemDrive.Text = "$($sysDrive.DeviceID) ($($sysDrive.VolumeName)): $($sysDrive.FreeGB) GB free of $($sysDrive.TotalGB) GB ($($sysDrive.PercentFree)% available)"
        $progressStorage.Value = [Math]::Max(0, (100 - $sysDrive.PercentFree))
        $progressStorage.Foreground = if ($sysDrive.PercentFree -lt 15) { $bc.ConvertFromString("#EF4444") } else { $bc.ConvertFromString("#10B981") }
    }
    $disksText = ($data.Storage.PhysicalDisks | ForEach-Object { "$($_.FriendlyName) ($($_.MediaType), $($_.SizeGB) GB): $($_.HealthStatus)" }) -join " | "
    $txtStorageDisks.Text = if ($disksText) { $disksText } else { "Physical drives reporting healthy SMART telemetry." }

    # Battery Card
    if ($data.Battery.IsBatteryPresent) {
        $txtBatteryCondition.Text = "Battery Health: $($data.Battery.HealthPercent)% of factory capacity"
        $progressBattery.Value = $data.Battery.HealthPercent
        $progressBattery.Foreground = if ($data.Battery.HealthPercent -ge 75) { $bc.ConvertFromString("#10B981") } else { $bc.ConvertFromString("#F59E0B") }
        $txtBatteryDetails.Text = "$($data.Battery.FullChargeMWh) mWh current capacity (Factory design: $($data.Battery.DesignCapacityMWh) mWh)`nDegradation: $($data.Battery.WearLevelPercent)% wear | Cycle count: $($data.Battery.CycleCount)"
    } else {
        $txtBatteryCondition.Text = "Power: Desktop Direct Wall Power (AC)"
        $progressBattery.Value = 100
        $progressBattery.Foreground = $bc.ConvertFromString("#10B981")
        $txtBatteryDetails.Text = "Zero battery degradation (Standard desktop PC power supply)."
    }

    # Memory & CPU Card
    $txtProcessorName.Text = "CPU: $($data.Performance.ProcessorName) ($($data.Performance.PhysicalCores) Cores, Load: $($data.Performance.CpuLoadPercent)%)"
    $txtMemoryUsage.Text   = "RAM: $($data.Performance.UsedRamGB) GB used / $($data.Performance.TotalRamGB) GB total ($($data.Performance.FreeRamGB) GB free)"
    $progressMemory.Value  = $data.Performance.RamUsedPercent
    $txtUptime.Text        = "System Uptime: $($data.Performance.SystemUptime)"

    # Stability Card
    if ($data.Stability.CrashEvents.Count -eq 0) {
        $txtCrashSummary.Text = "Clean Stability Record (0 crashes in 30 days)"
        $txtCrashDetails.Text = "No blue screen crash dumps (minidumps) or fatal driver exceptions found."
        $txtCrashDetails.Foreground = $bc.ConvertFromString("#10B981")
    } else {
        $txtCrashSummary.Text = "$($data.Stability.CrashEvents.Count) Crash Event(s) Detected in Last 30 Days"
        $details = ($data.Stability.CrashEvents | ForEach-Object { "• $($_.Timestamp): $($_.Cause)" }) -join "`n"
        $txtCrashDetails.Text = $details
        $txtCrashDetails.Foreground = $bc.ConvertFromString("#F87171")
    }

    $timeStr = (Get-Date).ToString("HH:mm:ss")
    $txtStatusFooter.Text = "Diagnostics completed at $timeStr. Health Score: $score/100."
}

# Run diagnostics in background
function Invoke-DiagnosticsScan {
    $btnRefresh.IsEnabled = $false
    $txtStatusFooter.Text = "Scanning hardware devices, drive SMART status, and event logs..."

    $worker = [System.ComponentModel.BackgroundWorker]::new()
    $worker.DoWork += {
        & "$engineScript" -Scan -Format Json
    }
    $worker.RunWorkerCompleted += {
        param($s, $e)
        $btnRefresh.IsEnabled = $true
        if ($e.Result) {
            try {
                $rawJson = $e.Result
                # Filter to last JSON block if console logs appeared
                if ($rawJson -match '(?s)(\{.*\})') {
                    $rawJson = $Matches[1]
                }
                $data = $rawJson | ConvertFrom-Json
                Update-Dashboard $data
            } catch {
                $txtStatusFooter.Text = "Error parsing diagnostics: $($_.Exception.Message)"
            }
        } else {
            # Fallback direct call
            $res = & "$engineScript" -Scan
            Update-Dashboard $res
        }
    }
    $worker.RunWorkerAsync()
}

$btnRefresh.Add_Click({
    Invoke-DiagnosticsScan
})

$btnSaveReport.Add_Click({
    if (-not $script:lastResult) {
        [System.Windows.MessageBox]::Show("Please wait for diagnostics to complete first.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }
    $sfd = New-Object Microsoft.Win32.SaveFileDialog
    $sfd.Title = "Save PC Health Report"
    $sfd.Filter = "HTML Report (*.html)|*.html"
    $sfd.FileName = "Hardware-Health-Report-$($env:COMPUTERNAME).html"

    if ($sfd.ShowDialog($window) -eq $true) {
        $outPath = $sfd.FileName
        & "$engineScript" -Scan -Format Html -OutputPath "$outPath"
        [System.Windows.MessageBox]::Show("Health Report successfully saved to:`n$outPath", "Report Generated", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        Start-Process "explorer.exe" -ArgumentList "/select,`"$outPath`""
    }
})

$btnCopySummary.Add_Click({
    if (-not $script:lastResult) { return }
    $d = $script:lastResult
    $summary = @"
Hardware Sentinel - PC Health Summary
Computer: $($d.ComputerName)
Operating System: $($d.Performance.OperatingSystem)
Health Score: $($d.Health.Score)/100 ($($d.Health.Grade))

Processor: $($d.Performance.ProcessorName)
Memory: $($d.Performance.UsedRamGB) GB used / $($d.Performance.TotalRamGB) GB ($($d.Performance.FreeRamGB) GB available)
Storage: $(($d.Storage.Volumes | ForEach-Object { "$($_.DeviceID) ($($_.PercentFree)% free)" }) -join ', ')
Battery / Power: $($d.Battery.StatusSummary)
Crashes (30d): $($d.Stability.CrashesLast30Days)
Report Generated: $($d.Timestamp)
"@
    [System.Windows.Clipboard]::SetText($summary)
    $txtStatusFooter.Text = "Summary copied to clipboard!"
})

# Initial Scan on load
$window.Add_Loaded({
    Invoke-DiagnosticsScan
})

$null = $window.ShowDialog()
