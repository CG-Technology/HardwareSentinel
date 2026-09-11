<#
.SYNOPSIS
    Hardware Sentinel - Disk Space Tree Analyzer (TreeSize-Style)
.DESCRIPTION
    Interactive disk space visualizer with hierarchical folder tree exploration (lazy-loaded),
    size distribution indicators, and largest single files finder.
.COMPANY
    CG Technology (https://github.com/CG-Technology)
#>

[CmdletBinding()]
param(
    [string]$InitialPath = "C:\"
)

# Sanitize initial path (strips accidental trailing quotes or backslashes)
if ($InitialPath) {
    $cleanInit = $InitialPath.Trim().Trim('"').Trim("'").TrimEnd('\').TrimEnd(':')
    if ([string]::IsNullOrWhiteSpace($cleanInit)) { $cleanInit = "C" }
    $InitialPath = "$($cleanInit):\"
} else {
    $InitialPath = "C:\"
}

$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# WPF Dispatcher frame pump
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

function Format-FileSize {
    param([int64]$Bytes)
    if ($Bytes -ge 1TB) {
        return ("{0:N2} TB" -f ($Bytes / 1TB))
    } elseif ($Bytes -ge 1GB) {
        return ("{0:N2} GB" -f ($Bytes / 1GB))
    } elseif ($Bytes -ge 1MB) {
        return ("{0:N1} MB" -f ($Bytes / 1MB))
    } elseif ($Bytes -ge 1KB) {
        return ("{0:N0} KB" -f ($Bytes / 1KB))
    } else {
        return ("{0} B" -f $Bytes)
    }
}

function Get-FolderSizeFast {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    
    # Try fast robocopy query
    try {
        $roboOut = & robocopy.exe $Path NULL /L /S /NJH /BYTES /XJ /R:0 /W:0 /NP 2>$null
        foreach ($line in $roboOut) {
            if ($line -match '^\s*Bytes\s*:\s*(\d+)') {
                return [int64]$matches[1]
            }
        }
    } catch {}

    # Fallback to shallow file sum
    $total = 0
    try {
        $files = [System.IO.Directory]::GetFiles($Path)
        foreach ($f in $files) {
            $total += (New-Object System.IO.FileInfo($f)).Length
        }
    } catch {}
    return $total
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Hardware Sentinel - Disk Space Tree Analyzer"
        Height="780" Width="1020"
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
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="12"/>
        </Style>
        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="Foreground" Value="#F8FAFC"/>
            <Setter Property="BorderBrush" Value="#334155"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,6"/>
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
                                <Setter TargetName="border" Property="BorderBrush" Value="#38BDF8"/>
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
            <Setter Property="Background" Value="#0284C7"/>
            <Setter Property="BorderBrush" Value="#38BDF8"/>
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
                                <Setter TargetName="border" Property="Background" Value="#0369A1"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="FilterChip" TargetType="Button" BasedOn="{StaticResource ActionButton}">
            <Setter Property="Background" Value="#0F172A"/>
            <Setter Property="BorderBrush" Value="#1E293B"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Padding" Value="10,4"/>
            <Setter Property="Margin" Value="0,0,6,0"/>
        </Style>
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>
        <Style TargetType="TabItem">
            <Setter Property="Background" Value="#111827"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="BorderBrush" Value="#1F2937"/>
            <Setter Property="BorderThickness" Value="1,1,1,0"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6,6,0,0" Margin="0,0,4,0"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#1E293B"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#38BDF8"/>
                                <Setter Property="Foreground" Value="#38BDF8"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#F8FAFC"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="TreeView">
            <Setter Property="Background" Value="#0F172A"/>
            <Setter Property="Foreground" Value="#E2E8F0"/>
            <Setter Property="BorderBrush" Value="#1E293B"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8"/>
        </Style>
        <Style TargetType="TreeViewItem">
            <Setter Property="Foreground" Value="#E2E8F0"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="2"/>
        </Style>
        <Style TargetType="ListView">
            <Setter Property="Background" Value="#0F172A"/>
            <Setter Property="Foreground" Value="#E2E8F0"/>
            <Setter Property="BorderBrush" Value="#1E293B"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="ListViewItem">
            <Setter Property="Foreground" Value="#E2E8F0"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="Padding" Value="4,3"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Setter Property="BorderBrush" Value="#162032"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#1E3A8A"/>
                    <Setter Property="Foreground" Value="#F8FAFC"/>
                </Trigger>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#1E293B"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/> <!-- Row 0: Header & Drive bar -->
            <RowDefinition Height="*"/>    <!-- Row 1: Main Tabs (Tree & Largest Files) -->
            <RowDefinition Height="Auto"/> <!-- Row 2: Selected item & Actions footer -->
        </Grid.RowDefinitions>

        <!-- Header Bar -->
        <Grid Grid.Row="0" Margin="0,0,0,12">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Top Brand & Drive Selector -->
            <Grid Grid.Row="0" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Background="#0C4A6E" BorderBrush="#0284C7" BorderThickness="1" CornerRadius="6" Width="30" Height="30" Margin="0,0,10,0">
                        <Path Data="M4 6a2 2 0 012-2h12a2 2 0 012 2v12a2 2 0 01-2 2H6a2 2 0 01-2-2V6zm2 4h12V6H6v4zm0 4h12v-2H6v2zm0 4h6v-2H6v2z" Fill="#38BDF8" Width="14" Height="14" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <TextBlock Text="Disk Space Tree Analyzer" FontSize="18" FontWeight="Bold" Foreground="#F8FAFC"/>
                            <Border Background="#1E293B" CornerRadius="8" Padding="6,1" Margin="8,0,0,0" VerticalAlignment="Center">
                                <TextBlock Text="TreeSize View" FontSize="10" FontWeight="Bold" Foreground="#38BDF8"/>
                            </Border>
                        </StackPanel>
                        <TextBlock x:Name="TxtDriveSubtitle" Text="Select a drive or folder to explore directory sizes and large files" FontSize="11.5" Foreground="#94A3B8"/>
                    </StackPanel>
                </StackPanel>

                <!-- Drive Selection & Actions -->
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="Drive:" FontSize="12" Foreground="#94A3B8" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <ComboBox x:Name="ComboDrives" Width="90" Height="28" Background="#1E293B" Foreground="#F8FAFC" BorderBrush="#334155" FontSize="12" FontWeight="SemiBold" VerticalContentAlignment="Center" Margin="0,0,10,0"/>
                    <Button x:Name="BtnRescanDrive" Style="{StaticResource ActionButton}" Content="Rescan Drive" Margin="0,0,6,0"/>
                </StackPanel>
            </Grid>

            <!-- Drive Capacity Bar Card -->
            <Border Grid.Row="1" Style="{StaticResource CardBorder}">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Grid Grid.Row="0" Margin="0,0,0,6">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock x:Name="TxtDriveLabel" Text="Drive C: (System)" FontSize="12" FontWeight="Bold" Foreground="#F8FAFC"/>
                            <TextBlock x:Name="TxtDriveCapacityDetail" Text=" - Used: -- | Free: --" FontSize="12" Foreground="#94A3B8" Margin="4,0,0,0"/>
                        </StackPanel>
                        <TextBlock x:Name="TxtDrivePercent" Text="--% Used" FontSize="12" FontWeight="Bold" Foreground="#38BDF8" HorizontalAlignment="Right"/>
                    </Grid>
                    <ProgressBar x:Name="ProgressDriveCapacity" Grid.Row="1" Height="8" Minimum="0" Maximum="100" Value="0"
                                 Background="#1E293B" Foreground="#38BDF8" BorderThickness="0"/>
                </Grid>
            </Border>
        </Grid>

        <!-- Main Content Tabs -->
        <TabControl x:Name="TabMain" Grid.Row="1">
            <!-- Tab 1: Hierarchical Folder Tree -->
            <TabItem Header="  Folder Tree (Hierarchical)  ">
                <Grid Margin="0,8,0,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Background="#111827" BorderBrush="#1F2937" BorderThickness="1" CornerRadius="6" Padding="10,6" Margin="0,0,0,6">
                        <Grid>
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <Path Data="M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z" Fill="#FBBF24" Width="13" Height="13" Stretch="Uniform" Margin="0,0,6,0" VerticalAlignment="Center"/>
                                <TextBlock Text="Expand folders (+) to navigate and calculate child sizes. Sorted by size descending." FontSize="11" Foreground="#94A3B8"/>
                            </StackPanel>
                            <TextBlock x:Name="TxtTreeScanStatus" Text="Ready" FontSize="11" Foreground="#38BDF8" HorizontalAlignment="Right"/>
                        </Grid>
                    </Border>

                    <TreeView x:Name="TreeFolderView" Grid.Row="1"/>
                </Grid>
            </TabItem>

            <!-- Tab 2: Largest Files Finder -->
            <TabItem Header="  Largest Files (>= 50 MB)  ">
                <Grid Margin="0,8,0,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- Filter Chips & Fast Scan Bar -->
                    <Border Grid.Row="0" Background="#111827" BorderBrush="#1F2937" BorderThickness="1" CornerRadius="6" Padding="10,8" Margin="0,0,0,8">
                        <Grid>
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="Filter:" FontSize="11" FontWeight="Bold" Foreground="#94A3B8" VerticalAlignment="Center" Margin="0,0,8,0"/>
                                <Button x:Name="BtnFilterAll" Style="{StaticResource FilterChip}" Content="All Files"/>
                                <Button x:Name="BtnFilterInstallers" Style="{StaticResource FilterChip}" Content="Installers (.msi, .exe, .msp)"/>
                                <Button x:Name="BtnFilterArchives" Style="{StaticResource FilterChip}" Content="Archives (.zip, .cab, .iso)"/>
                                <Button x:Name="BtnFilterSystem" Style="{StaticResource FilterChip}" Content="Virtual / System (.sys, .vhd)"/>
                            </StackPanel>

                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                                <Button x:Name="BtnScanLargestFiles" Style="{StaticResource PrimaryButton}" Content="Scan Largest Files" Padding="10,4"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Largest Files Grid -->
                    <ListView x:Name="ListLargestFiles" Grid.Row="1">
                        <ListView.View>
                            <GridView>
                                <GridViewColumn Header="  Rank  " Width="55" DisplayMemberBinding="{Binding Rank}"/>
                                <GridViewColumn Header="  Size  " Width="105" DisplayMemberBinding="{Binding SizeFormatted}"/>
                                <GridViewColumn Header="  File Name  " Width="260" DisplayMemberBinding="{Binding Name}"/>
                                <GridViewColumn Header="  Type  " Width="90" DisplayMemberBinding="{Binding Type}"/>
                                <GridViewColumn Header="  Folder Location  " Width="430" DisplayMemberBinding="{Binding Directory}"/>
                            </GridView>
                        </ListView.View>
                    </ListView>
                </Grid>
            </TabItem>
        </TabControl>

        <!-- Selected Item & Action Footer -->
        <Border Grid.Row="2" Background="#111827" BorderBrush="#1F2937" BorderThickness="1" CornerRadius="8" Padding="12,10" Margin="0,10,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" VerticalAlignment="Center">
                    <TextBlock Text="Selected Target:" FontSize="10.5" FontWeight="Bold" Foreground="#64748B"/>
                    <TextBlock x:Name="TxtSelectedPath" Text="Click any folder or file to inspect details" FontSize="11.5" Foreground="#CBD5E1" TextTrimming="CharacterEllipsis"/>
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="BtnOpenInExplorer" Style="{StaticResource PrimaryButton}" Content="Open in Explorer" Margin="0,0,8,0"/>
                    <Button x:Name="BtnCopyPath" Style="{StaticResource ActionButton}" Content="Copy Path"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Control References
$comboDrives           = $window.FindName("ComboDrives")
$btnRescanDrive        = $window.FindName("BtnRescanDrive")
$txtDriveLabel         = $window.FindName("TxtDriveLabel")
$txtDriveCapacityDetail= $window.FindName("TxtDriveCapacityDetail")
$txtDrivePercent       = $window.FindName("TxtDrivePercent")
$progressDriveCapacity = $window.FindName("ProgressDriveCapacity")
$txtDriveSubtitle      = $window.FindName("TxtDriveSubtitle")

$tabMain               = $window.FindName("TabMain")
$treeFolderView        = $window.FindName("TreeFolderView")
$txtTreeScanStatus     = $window.FindName("TxtTreeScanStatus")

$listLargestFiles      = $window.FindName("ListLargestFiles")
$btnScanLargestFiles   = $window.FindName("BtnScanLargestFiles")
$btnFilterAll          = $window.FindName("BtnFilterAll")
$btnFilterInstallers   = $window.FindName("BtnFilterInstallers")
$btnFilterArchives     = $window.FindName("BtnFilterArchives")
$btnFilterSystem       = $window.FindName("BtnFilterSystem")

$txtSelectedPath       = $window.FindName("TxtSelectedPath")
$btnOpenInExplorer     = $window.FindName("BtnOpenInExplorer")
$btnCopyPath           = $window.FindName("BtnCopyPath")

$script:currentDriveRoot = "C:\"
$script:allLargestFiles  = @()
$script:currentFilter    = "ALL"

# Helper: Create styled TreeViewItem Header Grid
function New-TreeNodeHeader {
    param(
        [string]$Name,
        [int64]$Bytes,
        [int64]$ParentBytes,
        [bool]$IsFolder = $true
    )

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $panel.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)

    # Icon
    $pathIcon = New-Object System.Windows.Shapes.Path
    $pathIcon.Width = 13
    $pathIcon.Height = 13
    $pathIcon.Stretch = [System.Windows.Media.Stretch]::Uniform
    $pathIcon.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
    $pathIcon.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $bc = New-Object System.Windows.Media.BrushConverter
    if ($IsFolder) {
        $pathIcon.Data = [System.Windows.Media.Geometry]::Parse("M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z")
        $pathIcon.Fill = $bc.ConvertFromString("#FBBF24")
    } else {
        $pathIcon.Data = [System.Windows.Media.Geometry]::Parse("M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z")
        $pathIcon.Fill = $bc.ConvertFromString("#38BDF8")
    }
    [void]$panel.Children.Add($pathIcon)

    # Name
    $txt = New-Object System.Windows.Controls.TextBlock
    $txt.Text = $Name
    $txt.FontWeight = [System.Windows.FontWeights]::SemiBold
    $txt.Foreground = $bc.ConvertFromString("#F8FAFC")
    $txt.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [void]$panel.Children.Add($txt)

    # Size text
    $txtSize = New-Object System.Windows.Controls.TextBlock
    if ($Bytes -lt 0) {
        $txtSize.Text = "Calculating..."
        $txtSize.Foreground = $bc.ConvertFromString("#38BDF8")
    } else {
        $txtSize.Text = Format-FileSize $Bytes
        $txtSize.Foreground = $bc.ConvertFromString("#94A3B8")
    }
    $txtSize.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
    $txtSize.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [void]$panel.Children.Add($txtSize)

    # Mini Visual % Bar
    if ($ParentBytes -gt 0 -and $Bytes -gt 0) {
        $pct = [math]::Round(($Bytes / $ParentBytes) * 100, 1)
        if ($pct -gt 100) { $pct = 100 }

        $borderOuter = New-Object System.Windows.Controls.Border
        $borderOuter.Background = $bc.ConvertFromString("#1E293B")
        $borderOuter.CornerRadius = New-Object System.Windows.CornerRadius(2)
        $borderOuter.Width = 45
        $borderOuter.Height = 5
        $borderOuter.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
        $borderOuter.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $borderOuter.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left

        $borderInner = New-Object System.Windows.Controls.Border
        $innerColor = if ($pct -gt 50) { "#F43F5E" } elseif ($pct -gt 25) { "#F59E0B" } else { "#38BDF8" }
        $borderInner.Background = $bc.ConvertFromString($innerColor)
        $borderInner.CornerRadius = New-Object System.Windows.CornerRadius(2)
        $borderInner.Width = [math]::Max(2, [math]::Round(($pct / 100) * 45))
        $borderInner.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $borderOuter.Child = $borderInner
        [void]$panel.Children.Add($borderOuter)

        $txtPct = New-Object System.Windows.Controls.TextBlock
        $txtPct.Text = ("{0:N1}%" -f $pct)
        $txtPct.FontSize = 10
        $txtPct.Foreground = $bc.ConvertFromString("#64748B")
        $txtPct.Margin = New-Object System.Windows.Thickness(4, 0, 0, 0)
        $txtPct.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [void]$panel.Children.Add($txtPct)
    }

    return $panel
}

# Expand Folder Node Handler (Lazy Loading)
function Expand-FolderNode {
    param([System.Windows.Controls.TreeViewItem]$Node)

    if ($Node.Items.Count -eq 1 -and $Node.Items[0].Tag -eq "__DUMMY__") {
        $Node.Items.Clear()
        $targetPath = [string]$Node.Tag
        if (-not (Test-Path -LiteralPath $targetPath)) { return }

        $txtTreeScanStatus.Text = "Reading $targetPath..."
        Do-WpfEvents

        # 1. Enumerate Directories & Files instantly
        $subdirs = @()
        try {
            $subdirs = [System.IO.Directory]::GetDirectories($targetPath)
        } catch {}

        $fileEntries = @()
        try {
            $files = [System.IO.Directory]::GetFiles($targetPath)
            foreach ($fl in $files) {
                $fInfo = New-Object System.IO.FileInfo($fl)
                $fileEntries += [PSCustomObject]@{
                    Name  = $fInfo.Name
                    Path  = $fl
                    Bytes = $fInfo.Length
                }
            }
        } catch {}

        # Parent total size for percentage calculation
        $parentSize = [int64]$Node.ToolTip
        if ($parentSize -le 0) { $parentSize = 1 }

        # Add Files sorted descending by size immediately
        $fileEntries | Sort-Object Bytes -Descending | ForEach-Object {
            $fileNode = New-Object System.Windows.Controls.TreeViewItem
            $fileNode.Header = New-TreeNodeHeader -Name $_.Name -Bytes $_.Bytes -ParentBytes $parentSize -IsFolder $false
            $fileNode.Tag = $_.Path
            $fileNode.ToolTip = $_.Bytes

            $fileNode.Add_Selected({
                param($s, $e)
                if ($e.Source -eq $s) {
                    $txtSelectedPath.Text = [string]$s.Tag
                }
            })

            [void]$Node.Items.Add($fileNode)
        }

        # Add Subdirectories immediately with initial Calculating status
        $dirNodes = @()
        foreach ($sd in $subdirs) {
            $dName = [System.IO.Path]::GetFileName($sd)
            if ($dName -in @("System Volume Information", "`$RECYCLE.BIN")) {
                continue
            }

            $childNode = New-Object System.Windows.Controls.TreeViewItem
            $childNode.Header = New-TreeNodeHeader -Name $dName -Bytes -1 -ParentBytes $parentSize -IsFolder $true
            $childNode.Tag = $sd
            $childNode.ToolTip = 0

            # Add dummy child for lazy subfolder expansion
            $dummy = New-Object System.Windows.Controls.TreeViewItem
            $dummy.Header = "Loading..."
            $dummy.Tag = "__DUMMY__"
            [void]$childNode.Items.Add($dummy)
            
            $childNode.Add_Expanded({
                param($s, $e)
                if ($e.Source -eq $s) { Expand-FolderNode -Node $s }
            })

            $childNode.Add_Selected({
                param($s, $e)
                if ($e.Source -eq $s) {
                    $txtSelectedPath.Text = [string]$s.Tag
                }
            })

            [void]$Node.Items.Add($childNode)
            $dirNodes += $childNode
        }

        # Render all discovered folders and files instantly in the UI
        $txtTreeScanStatus.Text = ("Discovered {0} folders and {1} files. Calculating sizes..." -f $dirNodes.Count, $fileEntries.Count)
        Do-WpfEvents

        # 2. Progressively compute directory sizes
        foreach ($dn in $dirNodes) {
            $sPath = [string]$dn.Tag
            $sName = [System.IO.Path]::GetFileName($sPath)
            $txtTreeScanStatus.Text = "Calculating size for $sName..."
            Do-WpfEvents

            $dBytes = Get-FolderSizeFast $sPath
            $dn.ToolTip = $dBytes
            $dn.Header = New-TreeNodeHeader -Name $sName -Bytes $dBytes -ParentBytes $parentSize -IsFolder $true
            Do-WpfEvents
        }

        # 3. Sort subdirectories and files descending by size once calculated
        $sortedItems = @($Node.Items) | Sort-Object ToolTip -Descending
        $Node.Items.Clear()
        foreach ($item in $sortedItems) {
            [void]$Node.Items.Add($item)
        }

        $txtTreeScanStatus.Text = "Ready"
        Do-WpfEvents
    }
}

# Populate Drive Telemetry and Root Tree
function Load-DriveTelemetry {
    param([string]$DriveLetter = "C:\")

    # Robust drive letter sanitization
    $cleanLetter = $DriveLetter.Trim().Trim('"').Trim("'").TrimEnd('\').TrimEnd(':')
    if ([string]::IsNullOrWhiteSpace($cleanLetter)) { $cleanLetter = "C" }
    $DriveLetter = "$($cleanLetter):\"
    $script:currentDriveRoot = $DriveLetter

    $cleanDrive = "$($cleanLetter):"
    $driveObj = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $cleanDrive }
    if (-not $driveObj) {
        $driveObj = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | Select-Object -First 1
    }

    if ($driveObj) {
        $totalBytes = [int64]$driveObj.Size
        $freeBytes  = [int64]$driveObj.FreeSpace
        $usedBytes  = $totalBytes - $freeBytes
        $pctUsed    = if ($totalBytes -gt 0) { [math]::Round(($usedBytes / $totalBytes) * 100, 1) } else { 0 }

        $txtDriveLabel.Text = ("Drive {0} ({1})" -f $driveObj.DeviceID, (if ($driveObj.VolumeName) { $driveObj.VolumeName } else { "Local Disk" }))
        $txtDriveCapacityDetail.Text = (" - Used: {0} | Free: {1} | Total: {2}" -f (Format-FileSize $usedBytes), (Format-FileSize $freeBytes), (Format-FileSize $totalBytes))
        $txtDrivePercent.Text = ("{0:N1}% Used" -f $pctUsed)
        $progressDriveCapacity.Value = $pctUsed

        $bc = New-Object System.Windows.Media.BrushConverter
        $capColor = if ($pctUsed -ge 90) { "#EF4444" } elseif ($pctUsed -ge 80) { "#F59E0B" } else { "#38BDF8" }
        $progressDriveCapacity.Foreground = $bc.ConvertFromString($capColor)
    }

    # Initialize Tree View with Root Node
    $treeFolderView.Items.Clear()
    $rootNode = New-Object System.Windows.Controls.TreeViewItem
    $rootSize = if ($usedBytes) { $usedBytes } else { 1 }
    $rootNode.Header = New-TreeNodeHeader -Name $DriveLetter -Bytes $rootSize -ParentBytes $totalBytes -IsFolder $true
    $rootNode.Tag = $DriveLetter
    $rootNode.ToolTip = $rootSize
    $rootNode.IsExpanded = $true

    $dummy = New-Object System.Windows.Controls.TreeViewItem
    $dummy.Header = "Loading..."
    $dummy.Tag = "__DUMMY__"
    [void]$rootNode.Items.Add($dummy)

    $rootNode.Add_Expanded({
        param($s, $e)
        if ($e.Source -eq $s) { Expand-FolderNode -Node $s }
    })

    $rootNode.Add_Selected({
        param($s, $e)
        if ($e.Source -eq $s) {
            $txtSelectedPath.Text = [string]$s.Tag
        }
    })

    [void]$treeFolderView.Items.Add($rootNode)

    # Expand the root node initially
    Expand-FolderNode -Node $rootNode
}

# Scan Largest Files Function
function Scan-LargestFiles {
    param([string]$DrivePath = $script:currentDriveRoot)

    $btnScanLargestFiles.IsEnabled = $false
    $btnScanLargestFiles.Content = "Scanning..."
    $txtDriveSubtitle.Text = "Scanning drive for files >= 50 MB using native index..."
    Do-WpfEvents

    $cleanLetter = $DrivePath.Trim().Trim('"').Trim("'").TrimEnd('\').TrimEnd(':')
    if ([string]::IsNullOrWhiteSpace($cleanLetter)) { $cleanLetter = "C" }
    $cleanRoot = "$($cleanLetter):\"

    # Query files >= 50MB (52428800 bytes)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $roboOut = & robocopy.exe $cleanRoot NULL /L /S /NJH /NJS /NC /NDL /BYTES /XJ /R:0 /W:0 /MIN:52428800 2>$null
    $sw.Stop()

    $parsed = @()
    foreach ($line in $roboOut) {
        if ($line -match '^\s*(\d+)\s+(.+)$') {
            $bytes = [int64]$matches[1]
            $fPath = $matches[2].Trim()
            $fName = [System.IO.Path]::GetFileName($fPath)
            $fDir  = [System.IO.Path]::GetDirectoryName($fPath)
            $fExt  = [System.IO.Path]::GetExtension($fPath).ToUpper()

            $cat = "Other"
            if ($fExt -in @(".MSI", ".EXE", ".MSP", ".INTUNEWIN")) { $cat = "Installer" }
            elseif ($fExt -in @(".ZIP", ".CAB", ".TAR", ".GZ", ".7Z", ".ISO", ".WIM")) { $cat = "Archive" }
            elseif ($fExt -in @(".SYS", ".VHD", ".VHDX", ".TMP", ".LOG")) { $cat = "System" }
            elseif ($fExt -in @(".MP4", ".MKV", ".AVI", ".MOV", ".WAV", ".MP3")) { $cat = "Media" }

            $parsed += [PSCustomObject]@{
                Bytes         = $bytes
                SizeFormatted = Format-FileSize $bytes
                Name          = $fName
                Directory     = $fDir
                FullPath      = $fPath
                Extension     = $fExt
                Category      = $cat
            }
        }
    }

    # Sort descending
    $sorted = $parsed | Sort-Object Bytes -Descending
    $rank = 1
    foreach ($item in $sorted) {
        Add-Member -InputObject $item -NotePropertyName "Rank" -NotePropertyValue $rank
        Add-Member -InputObject $item -NotePropertyName "Type" -NotePropertyValue $item.Category
        $rank++
    }

    $script:allLargestFiles = $sorted
    Apply-LargestFilesFilter -Filter $script:currentFilter

    $btnScanLargestFiles.IsEnabled = $true
    $btnScanLargestFiles.Content = "Scan Largest Files"
    $txtDriveSubtitle.Text = ("Found {0} files >= 50 MB in {1:N1}s on drive {2}" -f $sorted.Count, ($sw.ElapsedMilliseconds / 1000), $DrivePath)
    Do-WpfEvents
}

function Apply-LargestFilesFilter {
    param([string]$Filter)
    $script:currentFilter = $Filter

    $filtered = $script:allLargestFiles
    if ($Filter -eq "INSTALLER") {
        $filtered = $script:allLargestFiles | Where-Object { $_.Category -eq "Installer" }
    } elseif ($Filter -eq "ARCHIVE") {
        $filtered = $script:allLargestFiles | Where-Object { $_.Category -eq "Archive" }
    } elseif ($Filter -eq "SYSTEM") {
        $filtered = $script:allLargestFiles | Where-Object { $_.Category -eq "System" }
    }

    $listLargestFiles.ItemsSource = $filtered
}

# Event Handlers
$btnFilterAll.Add_Click({ Apply-LargestFilesFilter -Filter "ALL" })
$btnFilterInstallers.Add_Click({ Apply-LargestFilesFilter -Filter "INSTALLER" })
$btnFilterArchives.Add_Click({ Apply-LargestFilesFilter -Filter "ARCHIVE" })
$btnFilterSystem.Add_Click({ Apply-LargestFilesFilter -Filter "SYSTEM" })

$btnScanLargestFiles.Add_Click({
    Scan-LargestFiles -DrivePath $script:currentDriveRoot
})

$listLargestFiles.Add_SelectionChanged({
    if ($listLargestFiles.SelectedItem) {
        $txtSelectedPath.Text = $listLargestFiles.SelectedItem.FullPath
    }
})

$btnOpenInExplorer.Add_Click({
    $target = $txtSelectedPath.Text
    if (-not [string]::IsNullOrWhiteSpace($target)) {
        if (Test-Path -LiteralPath $target) {
            Start-Process explorer.exe -ArgumentList "/select,`"$target`""
        } else {
            $dir = [System.IO.Path]::GetDirectoryName($target)
            if (Test-Path -LiteralPath $dir) {
                Start-Process explorer.exe -ArgumentList "`"$dir`""
            }
        }
    }
})

$btnCopyPath.Add_Click({
    $target = $txtSelectedPath.Text
    if (-not [string]::IsNullOrWhiteSpace($target)) {
        [System.Windows.Forms.Clipboard]::SetText($target)
        $btnCopyPath.Content = "Copied!"
        Start-Sleep -Milliseconds 600
        $btnCopyPath.Content = "Copy Path"
    }
})

$btnRescanDrive.Add_Click({
    Load-DriveTelemetry -DriveLetter $script:currentDriveRoot
})

$tabMain.Add_SelectionChanged({
    param($s, $e)
    if ($e.Source -eq $s) {
        if ($tabMain.SelectedIndex -eq 1 -and $script:allLargestFiles.Count -eq 0) {
            Scan-LargestFiles -DrivePath $script:currentDriveRoot
        }
    }
})

# Populate Drives Dropdown
$drives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
foreach ($d in $drives) {
    [void]$comboDrives.Items.Add($d.DeviceID + "\")
}
if ($comboDrives.Items.Count -gt 0) {
    if ($comboDrives.Items.Contains($InitialPath)) {
        $comboDrives.SelectedItem = $InitialPath
    } else {
        $comboDrives.SelectedItem = $comboDrives.Items[0]
    }
}

$comboDrives.Add_SelectionChanged({
    if ($comboDrives.SelectedItem) {
        Load-DriveTelemetry -DriveLetter $comboDrives.SelectedItem
    }
})

# Initial Load when window is visible
$window.Add_ContentRendered({
    Load-DriveTelemetry -DriveLetter $InitialPath
})

$window.ShowDialog() | Out-Null
