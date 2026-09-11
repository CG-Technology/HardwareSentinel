<#
.SYNOPSIS
    Hardware Sentinel - Modern WPF Desktop Dashboard
.DESCRIPTION
    Launches the Hardware Sentinel desktop interface displaying the 0-100% PC Health Score,
    storage integrity, battery wear level, processor/memory utilization, and plain-English
    crash history. Includes real-time progress indicators and responsive telemetry streaming.
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

# WPF Message Pump to keep UI interactive and smoothly animated
function Do-WpfEvents {
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [System.Windows.Threading.DispatcherOperationCallback]{
            param($f)
            $f.Continue = $false
            return $null
        },
        $frame
    ) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Hardware Sentinel - PC Health &amp; Diagnostics"
        Height="760" Width="940"
        MinHeight="680" MinWidth="850"
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
            <RowDefinition Height="Auto"/> <!-- Row 0: Header -->
            <RowDefinition Height="Auto"/> <!-- Row 1: Score Hero Card -->
            <RowDefinition Height="Auto"/> <!-- Row 2: Scan Progress Bar -->
            <RowDefinition Height="*"/>    <!-- Row 3: 4 Diagnostic Cards -->
            <RowDefinition Height="Auto"/> <!-- Row 4: Footer status -->
        </Grid.RowDefinitions>

        <!-- Header -->
        <Grid Grid.Row="0" Margin="0,0,0,14">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <StackPanel Grid.Column="0">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Background="#1E1B4B" BorderBrush="#4F46E5" BorderThickness="1" CornerRadius="6" Width="32" Height="32" Margin="0,0,10,0">
                        <Path Data="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4z" Fill="#818CF8" Width="16" Height="16" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="Hardware Sentinel" FontSize="20" FontWeight="Bold" Foreground="#F8FAFC" VerticalAlignment="Center"/>
                    <Border Background="#065F46" CornerRadius="10" Padding="8,2" Margin="10,0,0,0" VerticalAlignment="Center">
                        <TextBlock Text="v1.0.3" FontSize="11" FontWeight="Bold" Foreground="#34D399"/>
                    </Border>
                </StackPanel>
                <TextBlock x:Name="TxtMachineSubtitle" Text="Computer: Checking... | OS: Windows" FontSize="12" Foreground="#94A3B8" Margin="42,4,0,0"/>
            </StackPanel>

            <!-- Top Action Buttons -->
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                <Button x:Name="BtnRefresh" Style="{StaticResource ActionButton}" Content="Rescan" Margin="0,0,8,0"/>
                <Button x:Name="BtnSaveReport" Style="{StaticResource PrimaryButton}" Content="Save Report (.html)" Margin="0,0,8,0"/>
                <Button x:Name="BtnCopySummary" Style="{StaticResource ActionButton}" Content="Copy Summary"/>
            </StackPanel>
        </Grid>

        <!-- Score Hero Card -->
        <Border Grid.Row="1" Style="{StaticResource CardBorder}" Margin="0,0,0,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="100"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Health Score Dial -->
                <Border x:Name="BorderScoreCircle" Grid.Column="0" Width="85" Height="85" CornerRadius="42.5" BorderThickness="4" BorderBrush="#38BDF8" Background="#0F172A">
                    <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                        <TextBlock x:Name="TxtScoreNumber" Text="--" FontSize="30" FontWeight="ExtraBold" Foreground="#38BDF8" HorizontalAlignment="Center" LineHeight="32"/>
                        <TextBlock Text="HEALTH" FontSize="9" FontWeight="Bold" Foreground="#94A3B8" HorizontalAlignment="Center" Margin="0,-2,0,0"/>
                    </StackPanel>
                </Border>

                <!-- Score Text & Observations -->
                <StackPanel Grid.Column="1" Margin="20,0,0,0" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock x:Name="TxtHealthGrade" Text="Analyzing PC Health..." FontSize="18" FontWeight="Bold" Foreground="#F8FAFC"/>
                        <Border x:Name="BadgeGrade" Background="#0369A1" CornerRadius="12" Padding="8,2" Margin="10,0,0,0" VerticalAlignment="Center">
                            <TextBlock x:Name="TxtGradeBadge" Text="Scanning" FontSize="11" FontWeight="Bold" Foreground="#38BDF8"/>
                        </Border>
                    </StackPanel>
                    <TextBlock x:Name="TxtScoreSummary" Text="Inspecting drives, memory pressure, battery degradation, and crash history..." FontSize="13" Foreground="#94A3B8" Margin="0,4,0,6" TextWrapping="Wrap"/>
                    <TextBlock x:Name="TxtTopObservations" Text="" FontSize="12" Foreground="#FBBF24" TextWrapping="Wrap"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Active Scan Progress Banner -->
        <Border x:Name="BorderScanProgress" Grid.Row="2" Background="#111827" BorderBrush="#1F2937" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,0,0,12">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0" Margin="0,0,0,6">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock x:Name="TxtScanStep" Text="Initializing diagnostic probes..." FontSize="12" FontWeight="SemiBold" Foreground="#38BDF8"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtScanPercent" Text="0%" FontSize="12" FontWeight="Bold" Foreground="#38BDF8" HorizontalAlignment="Right"/>
                </Grid>
                <ProgressBar x:Name="ProgressScanOverall" Grid.Row="1" Height="6" Minimum="0" Maximum="100" Value="0"
                             Background="#1E293B" Foreground="#38BDF8" BorderThickness="0"/>
            </Grid>
        </Border>

        <!-- 4 Diagnostic Cards Grid -->
        <Grid Grid.Row="3">
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Card 1: Storage & Drives -->
            <Border x:Name="CardStorage" Grid.Row="0" Grid.Column="0" Style="{StaticResource CardBorder}" Margin="0,0,8,8" Cursor="Hand" ToolTip="Click to open Disk Space Visualizer">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Grid Grid.Row="0" Margin="0,0,0,8">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <Path Data="M4 6a2 2 0 012-2h12a2 2 0 012 2v12a2 2 0 01-2 2H6a2 2 0 01-2-2V6zm2 4h12V6H6v4zm0 4h12v-2H6v2zm0 4h6v-2H6v2z" Fill="#38BDF8" Width="14" Height="14" Stretch="Uniform" Margin="0,0,8,0" VerticalAlignment="Center"/>
                            <TextBlock Text="Storage &amp; Drive Health" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC" VerticalAlignment="Center"/>
                        </StackPanel>
                        <Button x:Name="BtnOpenDiskTree" Style="{StaticResource ActionButton}" HorizontalAlignment="Right" Padding="8,2" FontSize="11" ToolTip="Explore folder hierarchy and largest files">
                            <StackPanel Orientation="Horizontal">
                                <Path Data="M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z" Fill="#38BDF8" Width="11" Height="11" Stretch="Uniform" Margin="0,0,5,0" VerticalAlignment="Center"/>
                                <TextBlock Text="Tree Analyzer" Foreground="#38BDF8" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                    </Grid>
                    <StackPanel Grid.Row="1">
                        <TextBlock x:Name="TxtStorageSystemDrive" Text="C: Drive: Checking space..." FontSize="12" Foreground="#CBD5E1"/>
                        <ProgressBar x:Name="ProgressStorage" Height="7" Margin="0,5,0,5" Value="0" Maximum="100" Background="#1E293B" Foreground="#10B981" BorderThickness="0"/>
                        <TextBlock x:Name="TxtStorageDisks" Text="Physical Disks: Probing SMART..." FontSize="11" Foreground="#94A3B8" TextWrapping="Wrap" Margin="0,0,0,6"/>
                        
                        <!-- Top Space Consumers on C: -->
                        <Border x:Name="BorderStorageTopConsumers" Background="#161E2E" CornerRadius="6" Padding="8,6" Margin="0,2,0,0" Cursor="Hand" ToolTip="Click to open Disk Space Visualizer">
                            <StackPanel>
                                <Grid Margin="0,0,0,2">
                                    <TextBlock Text="Largest Space Consumers on C:" FontSize="10.5" FontWeight="Bold" Foreground="#38BDF8" VerticalAlignment="Center"/>
                                    <TextBlock Text="Explore &gt;" FontSize="10" Foreground="#64748B" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                                </Grid>
                                <TextBlock x:Name="TxtStorageTopConsumers" Text="Analyzing disk usage..." FontSize="11" Foreground="#E2E8F0" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>
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
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
                        <Path Data="M17 6h-2V5c0-.55-.45-1-1-1h-4c-.55 0-1 .45-1 1v1H7c-1.1 0-2 .9-2 2v11c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2z" Fill="#10B981" Width="13" Height="13" Stretch="Uniform" Margin="0,0,8,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Battery &amp; Power Health" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC"/>
                    </StackPanel>
                    <StackPanel Grid.Row="1">
                        <TextBlock x:Name="TxtBatteryCondition" Text="Power Source: Detecting..." FontSize="12" Foreground="#CBD5E1"/>
                        <ProgressBar x:Name="ProgressBattery" Height="7" Margin="0,5,0,6" Value="0" Maximum="100" Background="#1E293B" Foreground="#10B981" BorderThickness="0"/>
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
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
                        <Path Data="M9 3L5 6.99h3V14H3v-3L0 15l3 4v-3h6v6h-3l4 4 4-4h-3v-6h5v3l3-4-3-4v3h-5V6.99h3L9 3z" Fill="#818CF8" Width="14" Height="14" Stretch="Uniform" Margin="0,0,8,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Processor &amp; Memory" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC"/>
                    </StackPanel>
                    <StackPanel Grid.Row="1">
                        <TextBlock x:Name="TxtProcessorName" Text="CPU: Detecting..." FontSize="12" Foreground="#CBD5E1"/>
                        <TextBlock x:Name="TxtTopCpu" Text="Active CPU: Analyzing threads..." FontSize="10.5" Foreground="#38BDF8" Margin="0,2,0,4" TextWrapping="Wrap"/>
                        <TextBlock x:Name="TxtMemoryUsage" Text="RAM: Probing utilization..." FontSize="12" Foreground="#CBD5E1"/>
                        <ProgressBar x:Name="ProgressMemory" Height="7" Margin="0,5,0,4" Value="0" Maximum="100" Background="#1E293B" Foreground="#6366F1" BorderThickness="0"/>
                        <TextBlock x:Name="TxtTopMemory" Text="Top RAM: Analyzing memory..." FontSize="10.5" Foreground="#A78BFA" Margin="0,0,0,4" TextWrapping="Wrap"/>
                        <TextBlock x:Name="TxtUptime" Text="Uptime: Calculating..." FontSize="11" Foreground="#64748B"/>
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
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
                        <Path Data="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z" Fill="#F87171" Width="14" Height="14" Stretch="Uniform" Margin="0,0,8,0" VerticalAlignment="Center"/>
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
        <Grid Grid.Row="4" Margin="0,14,0,0">
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

# Progress Bar Elements
$borderScanProgress  = $window.FindName("BorderScanProgress")
$txtScanStep         = $window.FindName("TxtScanStep")
$txtScanPercent      = $window.FindName("TxtScanPercent")
$progressScanOverall = $window.FindName("ProgressScanOverall")

$txtStorageSystemDrive   = $window.FindName("TxtStorageSystemDrive")
$progressStorage         = $window.FindName("ProgressStorage")
$txtStorageDisks         = $window.FindName("TxtStorageDisks")
$txtStorageTopConsumers  = $window.FindName("TxtStorageTopConsumers")
$cardStorage             = $window.FindName("CardStorage")
$btnOpenDiskTree         = $window.FindName("BtnOpenDiskTree")
$borderStorageTopConsumers = $window.FindName("BorderStorageTopConsumers")

$txtBatteryCondition   = $window.FindName("TxtBatteryCondition")
$progressBattery       = $window.FindName("ProgressBattery")
$txtBatteryDetails     = $window.FindName("TxtBatteryDetails")

$txtProcessorName      = $window.FindName("TxtProcessorName")
$txtTopCpu             = $window.FindName("TxtTopCpu")
$txtMemoryUsage        = $window.FindName("TxtMemoryUsage")
$progressMemory        = $window.FindName("ProgressMemory")
$txtTopMemory          = $window.FindName("TxtTopMemory")
$txtUptime             = $window.FindName("TxtUptime")

$txtCrashSummary       = $window.FindName("TxtCrashSummary")
$txtCrashDetails       = $window.FindName("TxtCrashDetails")
$txtStatusFooter       = $window.FindName("TxtStatusFooter")

$btnRefresh            = $window.FindName("BtnRefresh")
$btnSaveReport         = $window.FindName("BtnSaveReport")
$btnCopySummary        = $window.FindName("BtnCopySummary")

$script:lastResult = $null

function Invoke-DiagnosticsScan {
    $btnRefresh.IsEnabled     = $false
    $btnSaveReport.IsEnabled  = $false
    $btnCopySummary.IsEnabled = $false

    $bc = New-Object System.Windows.Media.BrushConverter

    # Setup Progress Banner
    $borderScanProgress.Visibility  = [System.Windows.Visibility]::Visible
    $progressScanOverall.Value      = 5
    $progressScanOverall.Foreground = $bc.ConvertFromString("#38BDF8")
    $txtScanStep.Text               = "Initializing diagnostic probes..."
    $txtScanStep.Foreground         = $bc.ConvertFromString("#38BDF8")
    $txtScanPercent.Text            = "5%"
    $txtScanPercent.Foreground      = $bc.ConvertFromString("#38BDF8")
    $txtStatusFooter.Text           = "Initializing Hardware Sentinel diagnostic engine..."

    # Reset score dial to scanning state
    $borderScoreCircle.BorderBrush  = $bc.ConvertFromString("#38BDF8")
    $txtScoreNumber.Foreground      = $bc.ConvertFromString("#38BDF8")
    $txtScoreNumber.Text            = "--"
    $txtHealthGrade.Text            = "Analyzing PC Health..."
    $txtGradeBadge.Text             = "Scanning"
    $badgeGrade.Background          = $bc.ConvertFromString("#0369A1")
    $txtScoreSummary.Text           = "Inspecting drives, memory pressure, battery degradation, and crash history..."
    $txtTopObservations.Text        = ""

    # Reset card previews to active scanning placeholders
    $txtStorageSystemDrive.Text     = "C: Drive: Probing free space..."
    $progressStorage.Value          = 0
    $txtStorageDisks.Text           = "Physical Disks: Querying SMART telemetry..."
    $txtStorageTopConsumers.Text    = "Scanning largest folders & files on C:..."

    $txtBatteryCondition.Text       = "Power Source: Detecting battery and power supply..."
    $progressBattery.Value          = 0
    $txtBatteryDetails.Text         = "Reading factory design vs full charge capacity..."

    $txtProcessorName.Text          = "CPU: Detecting model and active load..."
    $txtTopCpu.Text                 = "Active CPU: Analyzing threads..."
    $txtMemoryUsage.Text            = "RAM: Probing utilization and available memory..."
    $progressMemory.Value           = 0
    $txtTopMemory.Text              = "Top RAM: Inspecting process working sets..."
    $txtUptime.Text                 = "Uptime: Calculating system running time..."

    $txtCrashSummary.Text           = "Stability: Scanning minidump directory..."
    $txtCrashDetails.Text           = "Checking Event Log for recent BugCheck exceptions..."

    Do-WpfEvents

    # Ensure engine functions are loaded into memory
    . "$engineScript" -LoadFunctionsOnly

    # -------------------------------------------------------------
    # STEP 1: Storage & Drive Health (20%)
    # -------------------------------------------------------------
    $progressScanOverall.Value = 20
    $txtScanStep.Text          = "Step 1 of 5: Probing storage drives, SMART telemetry, and top space consumers..."
    $txtScanPercent.Text       = "20%"
    $txtStatusFooter.Text      = "Reading physical disk health, partition space, and largest folders..."
    Do-WpfEvents

    $storage = Get-SentinelStorageInfo

    # Update Storage Card Live!
    $sysDrive = $storage.Volumes | Where-Object { $_.IsSystemDrive } | Select-Object -First 1
    if ($sysDrive) {
        $txtStorageSystemDrive.Text = "$($sysDrive.DeviceID) ($($sysDrive.VolumeName)): $($sysDrive.FreeGB) GB free of $($sysDrive.TotalGB) GB ($($sysDrive.PercentFree)% available)"
        $progressStorage.Value = [Math]::Max(0, (100 - $sysDrive.PercentFree))
        $progressStorage.Foreground = if ($sysDrive.PercentFree -lt 15) { $bc.ConvertFromString("#EF4444") } else { $bc.ConvertFromString("#10B981") }
    }
    $disksText = ($storage.PhysicalDisks | ForEach-Object { "$($_.FriendlyName) ($($_.MediaType), $($_.SizeGB) GB): $($_.HealthStatus)" }) -join " | "
    $txtStorageDisks.Text = if ($disksText) { $disksText } else { "Physical drives reporting healthy SMART telemetry." }

    if ($storage.TopConsumers -and $storage.TopConsumers.Count -gt 0) {
        $topStr = ($storage.TopConsumers | ForEach-Object { "$($_.Name): $($_.Display)" }) -join "   |   "
        $txtStorageTopConsumers.Text = $topStr
    } else {
        $txtStorageTopConsumers.Text = "Standard system directories within normal capacity."
    }
    Do-WpfEvents

    # -------------------------------------------------------------
    # STEP 2: Battery & Power Health (40%)
    # -------------------------------------------------------------
    $progressScanOverall.Value = 40
    $txtScanStep.Text          = "Step 2 of 5: Querying battery degradation, cycle count, and power rails..."
    $txtScanPercent.Text       = "40%"
    $txtStatusFooter.Text      = "Querying Windows power management telemetry..."
    Do-WpfEvents

    $battery = Get-SentinelBatteryInfo

    # Update Battery Card Live!
    if ($battery.IsBatteryPresent) {
        $txtBatteryCondition.Text = "Battery Health: $($battery.HealthPercent)% of factory capacity"
        $progressBattery.Value = $battery.HealthPercent
        $progressBattery.Foreground = if ($battery.HealthPercent -ge 75) { $bc.ConvertFromString("#10B981") } else { $bc.ConvertFromString("#F59E0B") }
        $txtBatteryDetails.Text = "$($battery.FullChargeMWh) mWh current capacity (Design: $($battery.DesignCapacityMWh) mWh)`nDegradation: $($battery.WearLevelPercent)% wear | Cycle count: $($battery.CycleCount)"
    } else {
        $txtBatteryCondition.Text = "Power: Direct AC Wall Power"
        $progressBattery.Value = 100
        $progressBattery.Foreground = $bc.ConvertFromString("#10B981")
        $txtBatteryDetails.Text = "Desktop PC - Zero battery degradation (Continuous wall power)."
    }
    Do-WpfEvents

    # -------------------------------------------------------------
    # STEP 3: Processor & Memory (60%)
    # -------------------------------------------------------------
    $progressScanOverall.Value = 60
    $txtScanStep.Text          = "Step 3 of 5: Analyzing CPU load, memory utilization, and top processes..."
    $txtScanPercent.Text       = "60%"
    $txtStatusFooter.Text      = "Measuring active CPU threads and process memory working sets..."
    Do-WpfEvents

    $performance = Get-SentinelPerformanceInfo

    # Update CPU/RAM Card Live!
    $txtProcessorName.Text = "CPU: $($performance.ProcessorName) ($($performance.PhysicalCores) Cores, Load: $($performance.CpuLoadPercent)%)"
    if ($performance.TopCpuProcesses -and $performance.TopCpuProcesses.Count -gt 0) {
        $topCpuStr = ($performance.TopCpuProcesses | ForEach-Object { "$($_.Name) ($($_.Display))" }) -join "   |   "
        $txtTopCpu.Text = "Active CPU: $topCpuStr"
    } else {
        $txtTopCpu.Text = "Active CPU: Idle (No high-usage processes)"
    }

    $txtMemoryUsage.Text   = "RAM: $($performance.UsedRamGB) GB used / $($performance.TotalRamGB) GB total ($($performance.FreeRamGB) GB free)"
    $progressMemory.Value  = $performance.RamUsedPercent
    if ($performance.TopMemoryProcesses -and $performance.TopMemoryProcesses.Count -gt 0) {
        $topMemStr = ($performance.TopMemoryProcesses | ForEach-Object { "$($_.Name) ($($_.Display))" }) -join "   |   "
        $txtTopMemory.Text = "Top RAM: $topMemStr"
    } else {
        $txtTopMemory.Text = "Top RAM: Within standard operating limits"
    }

    $txtUptime.Text        = "System Uptime: $($performance.SystemUptime)"
    $txtMachineSubtitle.Text = "Computer: $($env:COMPUTERNAME) | OS: $($performance.OperatingSystem)"
    Do-WpfEvents

    # -------------------------------------------------------------
    # STEP 4: System Stability & Crashes (80%)
    # -------------------------------------------------------------
    $progressScanOverall.Value = 80
    $txtScanStep.Text          = "Step 4 of 5: Inspecting minidumps and crash event logs..."
    $txtScanPercent.Text       = "80%"
    $txtStatusFooter.Text      = "Checking for blue screens and unexpected shutdowns..."
    Do-WpfEvents

    $stability = Get-SentinelStabilityInfo

    # Update Stability Card Live!
    if ($stability.CrashEvents.Count -eq 0) {
        $txtCrashSummary.Text = "Clean Stability Record (0 crashes in 30 days)"
        $txtCrashDetails.Text = "No blue screen crash dumps (minidumps) or fatal driver exceptions found."
        $txtCrashDetails.Foreground = $bc.ConvertFromString("#10B981")
    } else {
        $txtCrashSummary.Text = "$($stability.CrashEvents.Count) Crash Event(s) Detected in Last 30 Days"
        $details = ($stability.CrashEvents | ForEach-Object { "- $($_.Timestamp): $($_.Cause)" }) -join "`n"
        $txtCrashDetails.Text = $details
        $txtCrashDetails.Foreground = $bc.ConvertFromString("#F87171")
    }
    Do-WpfEvents

    # -------------------------------------------------------------
    # STEP 5: Composite Health Score Calculation (100%)
    # -------------------------------------------------------------
    $progressScanOverall.Value = 95
    $txtScanStep.Text          = "Step 5 of 5: Calculating composite health score..."
    $txtScanPercent.Text       = "95%"
    $txtStatusFooter.Text      = "Weighting diagnostics and compiling health observations..."
    Do-WpfEvents

    $health = Calculate-SentinelHealthScore -Storage $storage -Battery $battery -Performance $performance -Stability $stability

    # Store in memory for immediate HTML export or copying
    $script:lastResult = @{
        ComputerName = $env:COMPUTERNAME
        Timestamp    = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        Health       = $health
        Storage      = $storage
        Battery      = $battery
        Performance  = $performance
        Stability    = $stability
    }

    # Update Score Hero Card
    $score = $health.Score
    $grade = $health.Grade

    $brushColor   = if ($score -ge 85) { "#10B981" } elseif ($score -ge 70) { "#F59E0B" } else { "#EF4444" }
    $badgeBgColor = if ($score -ge 85) { "#065F46" } elseif ($score -ge 70) { "#78350F" } else { "#7F1D1D" }

    $borderScoreCircle.BorderBrush = $bc.ConvertFromString($brushColor)
    $txtScoreNumber.Foreground     = $bc.ConvertFromString($brushColor)
    $txtScoreNumber.Text           = $score.ToString()

    $txtHealthGrade.Text           = $grade
    $txtGradeBadge.Text            = if ($score -ge 85) { "Excellent" } elseif ($score -ge 70) { "Good" } else { "Action Needed" }
    $badgeGrade.Background         = $bc.ConvertFromString($badgeBgColor)

    if ($health.Observations.Count -eq 0) {
        $txtScoreSummary.Text = "Your computer hardware and operating system are in top condition with zero errors detected."
        $txtTopObservations.Text = "[OK] Storage healthy   |   [OK] Memory available   |   [OK] Zero blue screen crashes"
        $txtTopObservations.Foreground = $bc.ConvertFromString("#10B981")
    } else {
        $txtScoreSummary.Text = "The diagnostic scan completed. $($health.Observations.Count) item(s) recommended for review:"
        $txtTopObservations.Text = ($health.Observations -join "`n")
        $txtTopObservations.Foreground = $bc.ConvertFromString("#FBBF24")
    }

    # Finalize Progress Bar
    $progressScanOverall.Value      = 100
    $progressScanOverall.Foreground = $bc.ConvertFromString("#10B981")
    $txtScanStep.Text               = "Diagnostic scan complete"
    $txtScanStep.Foreground         = $bc.ConvertFromString("#10B981")
    $txtScanPercent.Text            = "100%"
    $txtScanPercent.Foreground      = $bc.ConvertFromString("#10B981")

    $timeStr = (Get-Date).ToString("HH:mm:ss")
    $txtStatusFooter.Text = "Diagnostics completed at $timeStr. Health Score: $score/100 ($grade)."

    $btnRefresh.IsEnabled     = $true
    $btnSaveReport.IsEnabled  = $true
    $btnCopySummary.IsEnabled = $true

    Do-WpfEvents
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
        . "$engineScript" -LoadFunctionsOnly
        New-SentinelHtmlReport -Result $script:lastResult -FilePath $outPath | Out-Null
        [System.Windows.MessageBox]::Show("Health Report successfully saved to:`n$outPath", "Report Generated", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        Start-Process "explorer.exe" -ArgumentList "/select,`"$outPath`""
    }
})

$btnCopySummary.Add_Click({
    if (-not $script:lastResult) { return }
    $d = $script:lastResult

    $consumerSummary = if ($d.Storage.TopConsumers -and $d.Storage.TopConsumers.Count -gt 0) { 
        ($d.Storage.TopConsumers | ForEach-Object { "  - $($_.Name): $($_.Display)" }) -join "`n" 
    } else { "  - Standard system directories within normal thresholds" }

    $topCpuSummary = if ($d.Performance.TopCpuProcesses -and $d.Performance.TopCpuProcesses.Count -gt 0) { 
        ($d.Performance.TopCpuProcesses | ForEach-Object { "$($_.Name) ($($_.Display))" }) -join ", " 
    } else { "Idle" }

    $topMemSummary = if ($d.Performance.TopMemoryProcesses -and $d.Performance.TopMemoryProcesses.Count -gt 0) { 
        ($d.Performance.TopMemoryProcesses | ForEach-Object { "$($_.Name) ($($_.Display))" }) -join ", " 
    } else { "None" }

    $summary = @"
Hardware Sentinel - PC Health Summary
Computer: $($d.ComputerName)
Operating System: $($d.Performance.OperatingSystem)
Health Score: $($d.Health.Score)/100 ($($d.Health.Grade))

Processor: $($d.Performance.ProcessorName) (Load: $($d.Performance.CpuLoadPercent)%)
Top Active CPU: $topCpuSummary

Memory: $($d.Performance.UsedRamGB) GB used / $($d.Performance.TotalRamGB) GB ($($d.Performance.FreeRamGB) GB available)
Top RAM Consumers: $topMemSummary

Storage: $(($d.Storage.Volumes | ForEach-Object { "$($_.DeviceID) ($($_.PercentFree)% free)" }) -join ', ')
Top Space Consumers on C:
$consumerSummary

Battery / Power: $($d.Battery.StatusSummary)
Crashes (30d): $($d.Stability.CrashesLast30Days)
Report Generated: $($d.Timestamp)
"@
    [System.Windows.Clipboard]::SetText($summary)
    $txtStatusFooter.Text = "Summary copied to clipboard!"
})

# Open Disk Space Visualizer
$openDiskTreeAction = {
    $diskTreeScript = Join-Path $scriptDir "Show-SentinelDiskTree.ps1"
    if (Test-Path $diskTreeScript) {
        $sysDrive = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd('\').TrimEnd(':') } else { "C" }
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$diskTreeScript`" -InitialPath `"$sysDrive`""
    } else {
        [System.Windows.MessageBox]::Show("Disk Tree Analyzer script not found at:`n$diskTreeScript", "Hardware Sentinel", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
}

if ($btnOpenDiskTree) {
    $btnOpenDiskTree.Add_Click($openDiskTreeAction)
}

if ($cardStorage) {
    $cardStorage.Add_MouseLeftButtonUp({
        param($s, $e)
        if ($e.OriginalSource -is [System.Windows.Controls.Button] -or $e.OriginalSource.Parent -is [System.Windows.Controls.Button]) { return }
        & $openDiskTreeAction
    })
}

if ($borderStorageTopConsumers) {
    $borderStorageTopConsumers.Add_MouseLeftButtonUp({
        param($s, $e)
        & $openDiskTreeAction
    })
}

# Initial Scan on window load
$window.Add_ContentRendered({
    Invoke-DiagnosticsScan
})

$null = $window.ShowDialog()
