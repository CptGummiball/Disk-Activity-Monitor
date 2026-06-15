<#
.SYNOPSIS
    Disk Activity Monitor - Echtzeit-Ueberwachung der Festplattenzugriffe pro Prozess
.DESCRIPTION
    Zeigt welche Prozesse auf welche Speichermedien zugreifen, mit Lese-/Schreibraten.
    Keine externen Abhaengigkeiten - nutzt nur Windows-Bordmittel (WinForms + .NET).
    Fuer beste Ergebnisse als Administrator ausfuehren.
.NOTES
    Version: 1.1
    Erfordert: Windows 10+ / PowerShell 5.1+
#>

#Requires -Version 5.1

# ══════════════════════════════════════════════════════════════════
#  DPI Awareness
# ══════════════════════════════════════════════════════════════════
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class DpiHelper {
    [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@ -ErrorAction SilentlyContinue
    try { [DpiHelper]::SetProcessDpiAwareness(2) } catch { try { [DpiHelper]::SetProcessDPIAware() } catch {} }
} catch {}

# ══════════════════════════════════════════════════════════════════
#  Assemblies
# ══════════════════════════════════════════════════════════════════
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ══════════════════════════════════════════════════════════════════
#  Native Interop - GetProcessIoCounters via kernel32.dll
# ══════════════════════════════════════════════════════════════════
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class IOResult
{
    public ulong ReadOperationCount;
    public ulong WriteOperationCount;
    public ulong ReadTransferCount;
    public ulong WriteTransferCount;
}

public static class NativeIO
{
    [StructLayout(LayoutKind.Sequential)]
    private struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetProcessIoCounters(IntPtr hProcess, out IO_COUNTERS counters);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, bool inherit, int pid);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

    // Returns IOResult or null on failure - avoids PowerShell out-struct issues
    public static IOResult GetIOCounters(int pid)
    {
        IntPtr hProc = IntPtr.Zero;
        try
        {
            hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            if (hProc == IntPtr.Zero) return null;
            IO_COUNTERS counters;
            if (GetProcessIoCounters(hProc, out counters))
            {
                return new IOResult {
                    ReadOperationCount = counters.ReadOperationCount,
                    WriteOperationCount = counters.WriteOperationCount,
                    ReadTransferCount = counters.ReadTransferCount,
                    WriteTransferCount = counters.WriteTransferCount
                };
            }
            return null;
        }
        catch { return null; }
        finally { if (hProc != IntPtr.Zero) CloseHandle(hProc); }
    }
}
"@ -ErrorAction Stop

# ══════════════════════════════════════════════════════════════════
#  Colors & Fonts
# ══════════════════════════════════════════════════════════════════
$script:C = @{
    BgDark       = [Drawing.Color]::FromArgb(13, 17, 23)
    BgCard       = [Drawing.Color]::FromArgb(22, 27, 34)
    BgCardAlt    = [Drawing.Color]::FromArgb(28, 35, 51)
    BgHover      = [Drawing.Color]::FromArgb(33, 38, 45)
    Border       = [Drawing.Color]::FromArgb(48, 54, 61)
    BorderLight  = [Drawing.Color]::FromArgb(68, 76, 86)
    TextPri      = [Drawing.Color]::FromArgb(230, 237, 243)
    TextSec      = [Drawing.Color]::FromArgb(139, 148, 158)
    TextMut      = [Drawing.Color]::FromArgb(72, 79, 88)
    Blue         = [Drawing.Color]::FromArgb(88, 166, 255)
    Green        = [Drawing.Color]::FromArgb(63, 185, 80)
    Orange       = [Drawing.Color]::FromArgb(240, 136, 62)
    Red          = [Drawing.Color]::FromArgb(248, 81, 73)
    Purple       = [Drawing.Color]::FromArgb(188, 140, 255)
    Cyan         = [Drawing.Color]::FromArgb(57, 210, 192)
    Selection    = [Drawing.Color]::FromArgb(31, 111, 235, 80)
    ActiveRow    = [Drawing.Color]::FromArgb(17, 30, 50)
}
$script:FontUI       = New-Object Drawing.Font("Segoe UI", 9)
$script:FontUIBold   = New-Object Drawing.Font("Segoe UI", 9, [Drawing.FontStyle]::Bold)
$script:FontUISm     = New-Object Drawing.Font("Segoe UI", 8)
$script:FontUISmBold = New-Object Drawing.Font("Segoe UI", 8, [Drawing.FontStyle]::Bold)
$script:FontMono     = New-Object Drawing.Font("Consolas", 9)
$script:FontMonoSm   = New-Object Drawing.Font("Consolas", 8)
$script:FontTitle    = New-Object Drawing.Font("Segoe UI", 14, [Drawing.FontStyle]::Bold)
$script:FontSubtitle = New-Object Drawing.Font("Segoe UI", 10)

$script:DriveColors = @(
    [Drawing.Color]::FromArgb(88,166,255),
    [Drawing.Color]::FromArgb(63,185,80),
    [Drawing.Color]::FromArgb(210,153,34),
    [Drawing.Color]::FromArgb(248,81,73),
    [Drawing.Color]::FromArgb(188,140,255),
    [Drawing.Color]::FromArgb(57,210,192),
    [Drawing.Color]::FromArgb(240,136,62),
    [Drawing.Color]::FromArgb(219,97,162)
)

# ══════════════════════════════════════════════════════════════════
#  Global State
# ══════════════════════════════════════════════════════════════════
$script:PrevSnap       = @{}           # PID -> {Name, ReadBytes, WriteBytes}
$script:PrevTime       = [DateTime]::UtcNow
$script:Paused         = $false
$script:ActiveOnly     = $true
$script:SortCol        = 5             # Default: Write speed
$script:SortAsc        = $false
$script:RefreshCount   = 0
$script:DriveColorMap  = @{}
$script:DriveLabels    = @{}           # Drive cards reference for updating
$script:AccessDenied   = 0

# ══════════════════════════════════════════════════════════════════
#  Helper Functions
# ══════════════════════════════════════════════════════════════════
function Format-Bytes {
    param([double]$b, [string]$suf = "")
    if ($b -lt 0) { $b = 0 }
    $units = @("B","KB","MB","GB","TB")
    $i = 0; $v = $b
    while ($v -ge 1024 -and $i -lt 4) { $v /= 1024; $i++ }
    if ($i -eq 0) { return ("{0:N0} {1}{2}" -f $v, $units[$i], $suf) }
    return ("{0:N1} {1}{2}" -f $v, $units[$i], $suf)
}

function Format-Speed([double]$bps) { return (Format-Bytes $bps "/s") }

function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-VolumeLabel([string]$letter) {
    try {
        $vol = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$letter'" -ErrorAction Stop
        if ($vol.VolumeName) { return $vol.VolumeName }
    } catch {}
    return ""
}

# ══════════════════════════════════════════════════════════════════
#  Data Collection
# ══════════════════════════════════════════════════════════════════
function Get-DriveData {
    $drives = @()
    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop
        $perfDisks = @{}
        try {
            Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_LogicalDisk -ErrorAction Stop | ForEach-Object {
                $perfDisks[$_.Name] = $_
            }
        } catch {}

        $i = 0
        foreach ($d in ($disks | Sort-Object DeviceID)) {
            if (-not $d.DeviceID) { continue }
            $letter = $d.DeviceID
            $label  = if ($d.VolumeName) { $d.VolumeName } else { "" }
            $total  = [long]$d.Size
            $free   = [long]$d.FreeSpace
            $used   = $total - $free
            $pct    = if ($total -gt 0) { [Math]::Round($used / $total * 100, 1) } else { 0 }
            $fs     = if ($d.FileSystem) { $d.FileSystem } else { "?" }
            $dType  = $d.DriveType  # 2=Removable, 3=Fixed, 4=Network, 5=CD-ROM

            $readRate = 0.0; $writeRate = 0.0
            $perf = $perfDisks[$letter]
            if ($perf) {
                $readRate  = [double]$perf.DiskReadBytesPersec
                $writeRate = [double]$perf.DiskWriteBytesPersec
            }

            if (-not $script:DriveColorMap.ContainsKey($letter)) {
                $script:DriveColorMap[$letter] = $script:DriveColors[$i % $script:DriveColors.Count]
            }
            $i++

            $drives += [PSCustomObject]@{
                Letter    = $letter
                Label     = $label
                Total     = $total
                Used      = $used
                Free      = $free
                UsagePct  = $pct
                FsType    = $fs
                DriveType = $dType
                ReadRate  = $readRate
                WriteRate = $writeRate
                Color     = $script:DriveColorMap[$letter]
            }
        }
    } catch {}
    return $drives
}

function Get-ProcessIOData {
    $now = [DateTime]::UtcNow
    $elapsed = ($now - $script:PrevTime).TotalSeconds
    if ($elapsed -le 0.1) { $elapsed = 0.1 }

    $results = [System.Collections.ArrayList]::new()
    $currentSnap = @{}
    $denied = 0

    $processes = [System.Diagnostics.Process]::GetProcesses()
    try {
        foreach ($proc in $processes) {
            $procId = $proc.Id
            if ($procId -eq 0 -or $procId -eq 4) {
                # Skip System Idle Process and System
                $proc.Dispose()
                continue
            }

            $io = [NativeIO]::GetIOCounters($procId)

            if ($null -eq $io) {
                $denied++
                $proc.Dispose()
                continue
            }

            $pName = $proc.ProcessName
            $currentSnap[$procId] = @{
                Name = $pName
                RB   = [uint64]$io.ReadTransferCount
                WB   = [uint64]$io.WriteTransferCount
            }

            # Compute rate from previous snapshot
            if ($script:PrevSnap.ContainsKey($procId)) {
                $prev = $script:PrevSnap[$procId]
                if ($prev.Name -eq $pName) {
                    $rd = [Math]::Max(0, [long]($io.ReadTransferCount  - $prev.RB))
                    $wd = [Math]::Max(0, [long]($io.WriteTransferCount - $prev.WB))
                    $rSpeed = $rd / $elapsed
                    $wSpeed = $wd / $elapsed
                    $active = ($rd -gt 0) -or ($wd -gt 0)

                    # Determine drive from executable path (only for active procs)
                    $driveStr = ""
                    if ($active) {
                        try {
                            $exePath = $proc.MainModule.FileName
                            if ($exePath -and $exePath.Length -ge 2 -and $exePath[1] -eq ':') {
                                $driveStr = $exePath.Substring(0, 2).ToUpper()
                            }
                        } catch {}
                    }

                    $memMB = 0.0
                    try { $memMB = [Math]::Round($proc.WorkingSet64 / 1MB, 1) } catch {}

                    [void]$results.Add([PSCustomObject]@{
                        Active     = $active
                        PID        = $procId
                        Name       = $pName
                        Drives     = $driveStr
                        ReadSpeed  = $rSpeed
                        WriteSpeed = $wSpeed
                        ReadTotal  = [uint64]$io.ReadTransferCount
                        WriteTotal = [uint64]$io.WriteTransferCount
                        MemMB      = $memMB
                    })
                }
            }

            $proc.Dispose()
        }
    } catch {
        # Cleanup remaining processes
        foreach ($p in $processes) { try { $p.Dispose() } catch {} }
    }

    $script:PrevSnap = $currentSnap
    $script:PrevTime = $now
    $script:AccessDenied = $denied

    return $results
}

# ══════════════════════════════════════════════════════════════════
#  GUI Construction
# ══════════════════════════════════════════════════════════════════

# ── Main Form ──
$form = New-Object Windows.Forms.Form
$form.Text            = "Disk Activity Monitor"
$form.Size            = New-Object Drawing.Size(1320, 840)
$form.MinimumSize     = New-Object Drawing.Size(960, 600)
$form.StartPosition   = "CenterScreen"
$form.BackColor       = $C.BgDark
$form.ForeColor       = $C.TextPri
$form.Font            = $FontUI
# Set icon to a disk emoji via window title
try {
    $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
} catch {}

# Enable double buffering via reflection
$dgvBindingFlags = [Reflection.BindingFlags]"Instance,NonPublic"

# ── Header Panel ──
$headerPanel = New-Object Windows.Forms.Panel
$headerPanel.Dock      = "Top"
$headerPanel.Height    = 52
$headerPanel.BackColor = $C.BgCard
$headerPanel.Padding   = New-Object Windows.Forms.Padding(16, 0, 16, 0)
# Controls are added to $form at the end for correct dock order

$lblTitle = New-Object Windows.Forms.Label
$lblTitle.Text      = "Disk Activity Monitor"
$lblTitle.Font      = $FontTitle
$lblTitle.ForeColor = $C.TextPri
$lblTitle.AutoSize  = $true
$lblTitle.Location  = New-Object Drawing.Point(20, 12)
$headerPanel.Controls.Add($lblTitle)

$lblVersion = New-Object Windows.Forms.Label
$lblVersion.Text      = "v1.1"
$lblVersion.Font      = $FontUISm
$lblVersion.ForeColor = $C.TextMut
$lblVersion.AutoSize  = $true
$lblVersion.Location  = New-Object Drawing.Point(($lblTitle.Right + 8), 20)
$headerPanel.Controls.Add($lblVersion)

$isAdmin = Test-Admin
$lblAdmin = New-Object Windows.Forms.Label
$lblAdmin.Font      = $FontUI
$lblAdmin.AutoSize  = $true
$lblAdmin.Anchor    = "Top,Right"
if ($isAdmin) {
    $lblAdmin.Text      = "Administrator"
    $lblAdmin.ForeColor = $C.Green
} else {
    $lblAdmin.Text      = "Eingeschraenkt (kein Admin)"
    $lblAdmin.ForeColor = $C.Orange
}
$lblAdmin.Location = New-Object Drawing.Point(($form.ClientSize.Width - $lblAdmin.PreferredWidth - 24), 18)
$headerPanel.Controls.Add($lblAdmin)

# Header separator
$headerSep = New-Object Windows.Forms.Panel
$headerSep.Dock      = "Top"
$headerSep.Height    = 1
$headerSep.BackColor = $C.Border
# (headerSep added to form at the end for correct dock order)

# ── Drive Panel ──
$drivePanelOuter = New-Object Windows.Forms.Panel
$drivePanelOuter.Dock      = "Top"
$drivePanelOuter.Height    = 110
$drivePanelOuter.BackColor = $C.BgDark
$drivePanelOuter.Padding   = New-Object Windows.Forms.Padding(12, 8, 12, 4)
# (added to $form at the end for correct dock order)

$lblDriveHeader = New-Object Windows.Forms.Label
$lblDriveHeader.Text      = "Speichermedien"
$lblDriveHeader.Font      = $FontUISmBold
$lblDriveHeader.ForeColor = $C.TextSec
$lblDriveHeader.AutoSize  = $true
$lblDriveHeader.Location  = New-Object Drawing.Point(16, 6)
$lblDriveHeader.Dock      = "None"
$drivePanelOuter.Controls.Add($lblDriveHeader)

$driveFlow = New-Object Windows.Forms.FlowLayoutPanel
$driveFlow.Dock      = "None"
$driveFlow.Location  = New-Object Drawing.Point(12, 30)
$driveFlow.Size      = New-Object Drawing.Size($form.ClientSize.Width - 24, 76)
$driveFlow.Anchor    = "Top, Left, Right"
$driveFlow.BackColor = $C.BgDark
$driveFlow.AutoScroll = $true
$driveFlow.WrapContents = $false
$driveFlow.Padding = New-Object Windows.Forms.Padding(4, 0, 4, 0)
$drivePanelOuter.Controls.Add($driveFlow)

function Build-DriveCards {
    $driveFlow.SuspendLayout()
    $driveFlow.Controls.Clear()
    $script:DriveLabels = @{}

    $drives = Get-DriveData
    foreach ($drv in $drives) {
        $card = New-Object Windows.Forms.Panel
        $card.Size      = New-Object Drawing.Size(190, 66)
        $card.BackColor = $C.BgCard
        $card.Margin    = New-Object Windows.Forms.Padding(4, 2, 4, 2)
        # Rounded border via Paint event
        $cardColor = $drv.Color
        $card.Tag = $drv.Letter
        $card.Add_Paint({
            param($s, $e)
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $rect = New-Object Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
            $borderPen = New-Object Drawing.Pen($script:C.Border, 1)
            $g.DrawRectangle($borderPen, $rect)
            $borderPen.Dispose()
        })

        # Color dot + Drive letter
        $lblDot = New-Object Windows.Forms.Label
        $lblDot.Text      = [char]0x25CF  # ●
        $lblDot.Font      = New-Object Drawing.Font("Segoe UI", 11)
        $lblDot.ForeColor = $drv.Color
        $lblDot.Location  = New-Object Drawing.Point(8, 5)
        $lblDot.AutoSize  = $true
        $card.Controls.Add($lblDot)

        $lblLetter = New-Object Windows.Forms.Label
        $lblLetter.Text      = "$($drv.Letter) $($drv.Label)"
        $lblLetter.Font      = $FontUISmBold
        $lblLetter.ForeColor = $C.TextPri
        $lblLetter.Location  = New-Object Drawing.Point(24, 7)
        $lblLetter.AutoSize  = $false
        $lblLetter.Size      = New-Object Drawing.Size(120, 18)
        $lblLetter.AutoEllipsis = $true
        $card.Controls.Add($lblLetter)

        $lblFs = New-Object Windows.Forms.Label
        $lblFs.Text      = $drv.FsType
        $lblFs.Font      = $FontUISm
        $lblFs.ForeColor = $C.TextMut
        $lblFs.Location  = New-Object Drawing.Point(150, 8)
        $lblFs.AutoSize  = $true
        $card.Controls.Add($lblFs)

        # Progress bar (usage)
        $pbar = New-Object Windows.Forms.ProgressBar
        $pbar.Location = New-Object Drawing.Point(10, 28)
        $pbar.Size     = New-Object Drawing.Size(170, 8)
        $pbar.Style    = "Continuous"
        $pbar.Minimum  = 0
        $pbar.Maximum  = 100
        $pbar.Value    = [Math]::Min(100, [int]$drv.UsagePct)
        $card.Controls.Add($pbar)

        # Usage text
        $usageText = if ($drv.Total -gt 0) {
            "$(Format-Bytes $drv.Used) / $(Format-Bytes $drv.Total)  ($($drv.UsagePct)%)"
        } else { "N/A" }
        $lblUsage = New-Object Windows.Forms.Label
        $lblUsage.Text      = $usageText
        $lblUsage.Font      = $FontMonoSm
        $lblUsage.ForeColor = $C.TextSec
        $lblUsage.Location  = New-Object Drawing.Point(10, 40)
        $lblUsage.AutoSize  = $true
        $card.Controls.Add($lblUsage)

        # I/O rate labels
        $lblIO = New-Object Windows.Forms.Label
        $lblIO.Font      = $FontMonoSm
        $lblIO.ForeColor = $C.TextMut
        $lblIO.Location  = New-Object Drawing.Point(10, 52)
        $lblIO.AutoSize  = $true
        $lblIO.Text      = ""
        $card.Controls.Add($lblIO)

        $script:DriveLabels[$drv.Letter] = @{
            IOLabel   = $lblIO
            ProgBar   = $pbar
            UsageLabel= $lblUsage
        }

        $driveFlow.Controls.Add($card)
    }
    $driveFlow.ResumeLayout()
}

function Update-DriveCards {
    try {
        $drives = Get-DriveData
        foreach ($drv in $drives) {
            $refs = $script:DriveLabels[$drv.Letter]
            if ($refs) {
                $ioText = ""
                if ($drv.ReadRate -gt 0 -or $drv.WriteRate -gt 0) {
                    $r = Format-Speed $drv.ReadRate
                    $w = Format-Speed $drv.WriteRate
                    $ioText = "R:$r  W:$w"
                    $refs.IOLabel.ForeColor = $C.Blue
                } else {
                    $refs.IOLabel.ForeColor = $C.TextMut
                    $ioText = "Idle"
                }
                $refs.IOLabel.Text = $ioText

                $refs.ProgBar.Value = [Math]::Min(100, [int]$drv.UsagePct)
                $usageText = if ($drv.Total -gt 0) {
                    "$(Format-Bytes $drv.Used) / $(Format-Bytes $drv.Total)  ($($drv.UsagePct)%)"
                } else { "N/A" }
                $refs.UsageLabel.Text = $usageText
            }
        }
    } catch {}
}

# ── Toolbar Panel ──
$toolPanel = New-Object Windows.Forms.Panel
$toolPanel.Dock      = "Top"
$toolPanel.Height    = 40
$toolPanel.BackColor = $C.BgDark
$toolPanel.Padding   = New-Object Windows.Forms.Padding(12, 4, 12, 4)
# (added to $form at the end for correct dock order)

$lblSearch = New-Object Windows.Forms.Label
$lblSearch.Text      = "Suche:"
$lblSearch.Font      = $FontUI
$lblSearch.ForeColor = $C.TextSec
$lblSearch.AutoSize  = $true
$lblSearch.Location  = New-Object Drawing.Point(16, 10)
$toolPanel.Controls.Add($lblSearch)

$txtSearch = New-Object Windows.Forms.TextBox
$txtSearch.Location  = New-Object Drawing.Point(70, 7)
$txtSearch.Size      = New-Object Drawing.Size(200, 24)
$txtSearch.BackColor = $C.BgCard
$txtSearch.ForeColor = $C.TextPri
$txtSearch.Font      = $FontUI
$txtSearch.BorderStyle = "FixedSingle"
$toolPanel.Controls.Add($txtSearch)

$chkActive = New-Object Windows.Forms.CheckBox
$chkActive.Text      = "Nur aktive Prozesse"
$chkActive.Font      = $FontUI
$chkActive.ForeColor = $C.TextSec
$chkActive.Checked   = $true
$chkActive.AutoSize  = $true
$chkActive.Location  = New-Object Drawing.Point(290, 8)
$chkActive.FlatStyle = "Flat"
$chkActive.Add_CheckedChanged({ $script:ActiveOnly = $chkActive.Checked })
$toolPanel.Controls.Add($chkActive)

$btnPause = New-Object Windows.Forms.Button
$btnPause.Text      = "Pause"
$btnPause.Font      = $FontUI
$btnPause.Size      = New-Object Drawing.Size(80, 28)
$btnPause.Location  = New-Object Drawing.Point(480, 5)
$btnPause.FlatStyle = "Flat"
$btnPause.BackColor = $C.BgCard
$btnPause.ForeColor = $C.TextPri
$btnPause.FlatAppearance.BorderColor = $C.Border
$btnPause.Cursor = [Windows.Forms.Cursors]::Hand
$btnPause.Add_Click({
    $script:Paused = -not $script:Paused
    if ($script:Paused) {
        $btnPause.Text = "Weiter"
        $btnPause.BackColor = $C.Green
        $btnPause.ForeColor = $C.BgDark
    } else {
        $btnPause.Text = "Pause"
        $btnPause.BackColor = $C.BgCard
        $btnPause.ForeColor = $C.TextPri
    }
})
$toolPanel.Controls.Add($btnPause)

$btnRefresh = New-Object Windows.Forms.Button
$btnRefresh.Text      = "Aktualisieren"
$btnRefresh.Font      = $FontUIBold
$btnRefresh.Size      = New-Object Drawing.Size(110, 28)
$btnRefresh.Location  = New-Object Drawing.Point(570, 5)
$btnRefresh.FlatStyle = "Flat"
$btnRefresh.BackColor = $C.Blue
$btnRefresh.ForeColor = [Drawing.Color]::White
$btnRefresh.FlatAppearance.BorderSize = 0
$btnRefresh.Cursor = [Windows.Forms.Cursors]::Hand
$btnRefresh.Add_Click({
    $script:Paused = $false
    $btnPause.Text = "Pause"
    $btnPause.BackColor = $C.BgCard
    $btnPause.ForeColor = $C.TextPri
    Build-DriveCards
})
$toolPanel.Controls.Add($btnRefresh)

$lblCount = New-Object Windows.Forms.Label
$lblCount.Font      = $FontUISm
$lblCount.ForeColor = $C.TextMut
$lblCount.AutoSize  = $true
$lblCount.Location  = New-Object Drawing.Point(700, 12)
$toolPanel.Controls.Add($lblCount)

# ── Status Bar ──
$statusPanel = New-Object Windows.Forms.Panel
$statusPanel.Dock      = "Bottom"
$statusPanel.Height    = 28
$statusPanel.BackColor = $C.BgCard
# (statusPanel added to $form at the end for correct dock order)

$statusSep = New-Object Windows.Forms.Panel
$statusSep.Dock      = "Bottom"
$statusSep.Height    = 1
$statusSep.BackColor = $C.Border
# (statusSep added to $form at the end for correct dock order)

$lblStatus = New-Object Windows.Forms.Label
$lblStatus.Font      = $FontMonoSm
$lblStatus.ForeColor = $C.TextSec
$lblStatus.AutoSize  = $true
$lblStatus.Location  = New-Object Drawing.Point(16, 6)
$statusPanel.Controls.Add($lblStatus)

$lblTime = New-Object Windows.Forms.Label
$lblTime.Font      = $FontMonoSm
$lblTime.ForeColor = $C.TextMut
$lblTime.AutoSize  = $true
$lblTime.Anchor    = "Top,Right"
$lblTime.Location  = New-Object Drawing.Point(($form.ClientSize.Width - 80), 6)
$statusPanel.Controls.Add($lblTime)

# ── DataGridView (Process Table) ──
$dgv = New-Object Windows.Forms.DataGridView
$dgv.Dock = "Fill"
$dgv.BackgroundColor       = $C.BgCard
$dgv.ForeColor             = $C.TextPri
$dgv.GridColor             = $C.Border
$dgv.BorderStyle           = "None"
$dgv.CellBorderStyle       = "SingleHorizontal"
$dgv.RowHeadersVisible     = $false
$dgv.AllowUserToAddRows    = $false
$dgv.AllowUserToDeleteRows = $false
$dgv.AllowUserToResizeRows = $false
$dgv.ReadOnly              = $true
$dgv.SelectionMode         = "FullRowSelect"
$dgv.MultiSelect           = $false
$dgv.EnableHeadersVisualStyles = $false
$dgv.ColumnHeadersHeight      = 34
$dgv.ColumnHeadersHeightSizeMode = "DisableResizing"
$dgv.RowTemplate.Height    = 28
$dgv.AutoSizeColumnsMode   = "None"
$dgv.ScrollBars            = "Vertical"
$dgv.Font                  = $FontMono

# Double buffering
try {
    $pi = $dgv.GetType().GetProperty("DoubleBuffered", $dgvBindingFlags)
    $pi.SetValue($dgv, $true, $null)
} catch {}

# Column header style
$hdrStyle = New-Object Windows.Forms.DataGridViewCellStyle
$hdrStyle.BackColor          = $C.BgDark
$hdrStyle.ForeColor          = $C.TextSec
$hdrStyle.SelectionBackColor = $C.BgDark
$hdrStyle.SelectionForeColor = $C.TextSec
$hdrStyle.Font               = $FontUISmBold
$hdrStyle.Alignment          = "MiddleLeft"
$hdrStyle.Padding            = New-Object Windows.Forms.Padding(4, 0, 4, 0)
$dgv.ColumnHeadersDefaultCellStyle = $hdrStyle

# Default cell style
$cellStyle = New-Object Windows.Forms.DataGridViewCellStyle
$cellStyle.BackColor          = $C.BgCard
$cellStyle.ForeColor          = $C.TextSec
$cellStyle.SelectionBackColor = $C.Selection
$cellStyle.SelectionForeColor = $C.TextPri
$cellStyle.Padding            = New-Object Windows.Forms.Padding(4, 0, 4, 0)
$dgv.DefaultCellStyle = $cellStyle

# Alternating row style
$altStyle = New-Object Windows.Forms.DataGridViewCellStyle
$altStyle.BackColor          = $C.BgCardAlt
$altStyle.ForeColor          = $C.TextSec
$altStyle.SelectionBackColor = $C.Selection
$altStyle.SelectionForeColor = $C.TextPri
$dgv.AlternatingRowsDefaultCellStyle = $altStyle

# Define columns: Name, HeaderText, Width, Alignment
$colDefs = @(
    @("Aktiv",      "",              35,  "MiddleCenter"),
    @("PID",        "PID",           65,  "MiddleRight"),
    @("Prozess",    "Prozess",       190, "MiddleLeft"),
    @("Laufwerke",  "Laufwerke",     90,  "MiddleCenter"),
    @("LesenS",     "Lesen/s",       100, "MiddleRight"),
    @("SchreibenS", "Schreiben/s",   110, "MiddleRight"),
    @("LesenGes",   "Gelesen",       95,  "MiddleRight"),
    @("GeschrGes",  "Geschrieben",   100, "MiddleRight"),
    @("RAM",        "RAM (MB)",      80,  "MiddleRight")
)

foreach ($cd in $colDefs) {
    $col = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $col.Name            = $cd[0]
    $col.HeaderText      = $cd[1]
    $col.Width           = $cd[2]
    $col.DefaultCellStyle.Alignment = [Windows.Forms.DataGridViewContentAlignment]::($cd[3])
    $col.SortMode        = "Programmatic"
    $col.Resizable       = "True"
    [void]$dgv.Columns.Add($col)
}

# Column header click -> sort
$dgv.Add_ColumnHeaderMouseClick({
    param($sender, $e)
    $ci = $e.ColumnIndex
    if ($script:SortCol -eq $ci) {
        $script:SortAsc = -not $script:SortAsc
    } else {
        $script:SortCol = $ci
        # Default descending for numeric columns
        $script:SortAsc = ($ci -le 2)
    }
})

# Cell formatting for colors
$dgv.Add_CellFormatting({
    param($sender, $e)
    $colName = $dgv.Columns[$e.ColumnIndex].Name
    $val = $e.Value

    switch ($colName) {
        "Aktiv" {
            if ($val -eq [char]0x25CF) {
                $e.CellStyle.ForeColor = $script:C.Green
                $e.CellStyle.Font = New-Object Drawing.Font("Segoe UI", 10)
            } else {
                $e.CellStyle.ForeColor = $script:C.TextMut
            }
        }
        "Prozess" {
            $e.CellStyle.ForeColor = $script:C.TextPri
            $e.CellStyle.Font = $script:FontUI
        }
        "LesenS" {
            if ($val -and $val -ne [char]0x2014) {
                $e.CellStyle.ForeColor = $script:C.Blue
            }
        }
        "SchreibenS" {
            if ($val -and $val -ne [char]0x2014) {
                $e.CellStyle.ForeColor = $script:C.Orange
            }
        }
        "Laufwerke" {
            if ($val -and $val -ne [char]0x2014) {
                $e.CellStyle.ForeColor = $script:C.Cyan
                $e.CellStyle.Font = $script:FontUISmBold
            }
        }
    }
})

# Right-click context menu
$ctxMenu = New-Object Windows.Forms.ContextMenuStrip
$ctxMenu.BackColor = $C.BgCard
$ctxMenu.ForeColor = $C.TextPri
$ctxMenu.Font      = $FontUI
$ctxMenu.Renderer  = New-Object Windows.Forms.ToolStripProfessionalRenderer

$menuKill = New-Object Windows.Forms.ToolStripMenuItem("Prozess beenden")
$menuKill.Add_Click({
    if ($dgv.SelectedRows.Count -gt 0) {
        $row = $dgv.SelectedRows[0]
        $pidVal = $row.Cells["PID"].Value
        if ($pidVal) {
            $pid = [int]$pidVal
            $name = $row.Cells["Prozess"].Value
            $result = [Windows.Forms.MessageBox]::Show(
                "Prozess '$name' (PID $pid) wirklich beenden?",
                "Prozess beenden",
                "YesNo", "Warning"
            )
            if ($result -eq "Yes") {
                try {
                    Stop-Process -Id $pid -Force -ErrorAction Stop
                    [Windows.Forms.MessageBox]::Show("Prozess beendet.", "Erfolg", "OK", "Information")
                } catch {
                    [Windows.Forms.MessageBox]::Show("Fehler: $($_.Exception.Message)", "Fehler", "OK", "Error")
                }
            }
        }
    }
})
$ctxMenu.Items.Add($menuKill)

$menuOpenDir = New-Object Windows.Forms.ToolStripMenuItem("Dateipfad oeffnen")
$menuOpenDir.Add_Click({
    if ($dgv.SelectedRows.Count -gt 0) {
        $pidVal = $dgv.SelectedRows[0].Cells["PID"].Value
        if ($pidVal) {
            try {
                $proc = [Diagnostics.Process]::GetProcessById([int]$pidVal)
                $path = $proc.MainModule.FileName
                $proc.Dispose()
                if ($path) {
                    Start-Process explorer.exe -ArgumentList "/select,`"$path`""
                }
            } catch {
                [Windows.Forms.MessageBox]::Show("Pfad nicht verfuegbar.", "Info", "OK", "Information")
            }
        }
    }
})
$ctxMenu.Items.Add($menuOpenDir)

$dgv.ContextMenuStrip = $ctxMenu

# ══════════════════════════════════════════════════════════════════
#  Dock Order Fix: WinForms docks last-added Top controls at visual top.
#  We add in reverse visual order so the layout is correct:
#  Header → Sep → Drives → Toolbar → [DGV Fill] → StatusSep → StatusBar
# ══════════════════════════════════════════════════════════════════
$form.Controls.Add($statusPanel)      # Bottom dock: visual bottom
$form.Controls.Add($statusSep)        # Bottom dock: above status bar
$form.Controls.Add($dgv)              # Fill dock:   takes remaining space
$form.Controls.Add($toolPanel)        # Top dock:    bottom of top section
$form.Controls.Add($drivePanelOuter)  # Top dock:    above toolbar
$form.Controls.Add($headerSep)       # Top dock:    above drives
$form.Controls.Add($headerPanel)     # Top dock:    at very top

$form.Add_Resize({
    if ($driveFlow) {
        $driveFlow.Size = New-Object Drawing.Size($form.ClientSize.Width - 24, 76)
    }
})

# ══════════════════════════════════════════════════════════════════
#  Refresh / Update Logic
# ══════════════════════════════════════════════════════════════════
$script:ProcessData = @()

function Update-Table {
    $data = $script:ProcessData

    # Filter: active only
    if ($script:ActiveOnly) {
        $data = @($data | Where-Object { $_.Active })
    }

    # Filter: search text
    $searchText = $txtSearch.Text.Trim().ToLower()
    if ($searchText) {
        $data = @($data | Where-Object {
            $_.Name.ToLower().Contains($searchText) -or
            ([string]$_.PID).Contains($searchText) -or
            $_.Drives.ToLower().Contains($searchText)
        })
    }

    # Sort
    $sortProp = switch ($script:SortCol) {
        0 { "Active" }
        1 { "PID" }
        2 { "Name" }
        3 { "Drives" }
        4 { "ReadSpeed" }
        5 { "WriteSpeed" }
        6 { "ReadTotal" }
        7 { "WriteTotal" }
        8 { "MemMB" }
        default { "WriteSpeed" }
    }
    if ($script:SortAsc) {
        $data = @($data | Sort-Object -Property $sortProp)
    } else {
        $data = @($data | Sort-Object -Property $sortProp -Descending)
    }

    # Populate DataGridView
    $dgv.SuspendLayout()
    $dgv.Rows.Clear()

    $dash = [string][char]0x2014  # em-dash

    if ($data.Count -eq 0) {
        $emptyRow = $dgv.Rows.Add("", "", "Keine aktiven Disk-Zugriffe", "", "", "", "", "", "")
        $dgv.Rows[$emptyRow].DefaultCellStyle.ForeColor = $C.TextMut
        $dgv.Rows[$emptyRow].DefaultCellStyle.Font = $FontUI
    } else {
        $maxRows = [Math]::Min($data.Count, 300)
        for ($i = 0; $i -lt $maxRows; $i++) {
            $row = $data[$i]
            $dot = if ($row.Active) { [string][char]0x25CF } else { "" }  # ●
            $drives = if ($row.Drives) { $row.Drives } else { $dash }
            $rSpeed = if ($row.ReadSpeed -gt 0) { Format-Speed $row.ReadSpeed } else { $dash }
            $wSpeed = if ($row.WriteSpeed -gt 0) { Format-Speed $row.WriteSpeed } else { $dash }

            [void]$dgv.Rows.Add(
                $dot,
                $row.PID,
                $row.Name,
                $drives,
                $rSpeed,
                $wSpeed,
                (Format-Bytes $row.ReadTotal),
                (Format-Bytes $row.WriteTotal),
                ("{0:N1}" -f $row.MemMB)
            )

            # Highlight active rows
            if ($row.Active) {
                $dgv.Rows[$dgv.Rows.Count - 1].DefaultCellStyle.BackColor = $C.ActiveRow
            }
        }
    }

    $dgv.ResumeLayout()

    # Update count label
    $activeCount = @($script:ProcessData | Where-Object { $_.Active }).Count
    $totalCount  = $script:ProcessData.Count
    $lblCount.Text = "$activeCount aktiv / $totalCount gesamt"
}

# ══════════════════════════════════════════════════════════════════
#  Timer
# ══════════════════════════════════════════════════════════════════
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 2000  # 2 seconds

$timer.Add_Tick({
    if ($script:Paused) { return }

    $t0 = [Diagnostics.Stopwatch]::StartNew()

    try {
        # Collect process I/O data
        $script:ProcessData = @(Get-ProcessIOData)

        # Update process table
        Update-Table

        # Update drive cards every 5 cycles
        $script:RefreshCount++
        if ($script:RefreshCount % 5 -eq 0) {
            Update-DriveCards
        }

        # Status bar
        $totalRead  = ($script:ProcessData | Measure-Object -Property ReadSpeed  -Sum).Sum
        $totalWrite = ($script:ProcessData | Measure-Object -Property WriteSpeed -Sum).Sum
        if (-not $totalRead)  { $totalRead = 0 }
        if (-not $totalWrite) { $totalWrite = 0 }

        $t0.Stop()
        $elapsed = $t0.ElapsedMilliseconds

        $statusText = "Gesamt: R $(Format-Speed $totalRead)  W $(Format-Speed $totalWrite)"
        $statusText += "  |  Scan: ${elapsed}ms"
        if ($script:AccessDenied -gt 0) {
            $statusText += "  |  $($script:AccessDenied) Prozesse nicht lesbar"
        }
        $lblStatus.Text = $statusText
        $lblTime.Text = (Get-Date -Format "HH:mm:ss")
    }
    catch {
        $lblStatus.Text = "Fehler: $($_.Exception.Message)"
    }
})

# ══════════════════════════════════════════════════════════════════
#  Keyboard Shortcuts
# ══════════════════════════════════════════════════════════════════
$form.KeyPreview = $true
$form.Add_KeyDown({
    param($sender, $e)
    switch ($e.KeyCode) {
        "F5" {
            $script:Paused = $false
            $btnPause.Text = "Pause"
            $btnPause.BackColor = $C.BgCard
            $btnPause.ForeColor = $C.TextPri
            Build-DriveCards
            $e.Handled = $true
        }
        "Pause" {
            $btnPause.PerformClick()
            $e.Handled = $true
        }
        "Escape" {
            $form.Close()
            $e.Handled = $true
        }
        "F" {
            if ($e.Control) {
                $txtSearch.Focus()
                $txtSearch.SelectAll()
                $e.Handled = $true
            }
        }
    }
})

# ══════════════════════════════════════════════════════════════════
#  Form Events
# ══════════════════════════════════════════════════════════════════
$form.Add_Shown({
    # Initial scan (populates PrevSnap, results will be mostly empty)
    $null = Get-ProcessIOData
    Build-DriveCards
    $timer.Start()
})

$form.Add_FormClosing({
    $timer.Stop()
    $timer.Dispose()
})

$form.Add_Resize({
    # Reposition admin label
    $lblAdmin.Location = New-Object Drawing.Point(
        ($form.ClientSize.Width - $lblAdmin.Width - 24), 18
    )
    # Reposition time label
    $lblTime.Location = New-Object Drawing.Point(
        ($form.ClientSize.Width - 80), 6
    )
})

# ══════════════════════════════════════════════════════════════════
#  Launch
# ══════════════════════════════════════════════════════════════════
[Windows.Forms.Application]::Run($form)
