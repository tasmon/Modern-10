#Requires -Version 5.1
<#
.SYNOPSIS
    Modern 10 - the application window.

.DESCRIPTION
    The only entry point of Modern 10 (started by Modern10.cmd). A Windows Forms window that is built into
    Windows - nothing to install. Pick theme, taskbar position, icon size and what to apply, then press Apply.
    The work is done by Modern10.Engine.ps1 in a background runspace, so the window never freezes.

    Developer: Tasmon Islam
#>
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $PSCommandPath
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:Root = $PSScriptRoot

function Show-M10Error([string]$Text) {
    [System.Windows.Forms.MessageBox]::Show($Text, 'Modern 10', 'OK', 'Error') | Out-Null
}

try {

if (-not ('M10Gui' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class M10Gui
{
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
'@
}
[void][M10Gui]::SetProcessDPIAware()
try { [void][M10Gui]::SetCurrentProcessExplicitAppUserModelID('TasmonIslam.Modern10') } catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:EnginePath = Join-Path $script:Root 'Modern10.Engine.ps1'
if (-not (Test-Path -LiteralPath $script:EnginePath)) {
    Show-M10Error "Modern10.Engine.ps1 was not found next to this window:`n$script:EnginePath"
    exit 1
}
. $script:EnginePath      # engine functions + icon library (nothing runs yet)

$script:Pal      = $null
$script:Async    = $null
$script:Shell    = $null
$script:Runspace = $null
$script:Queue    = $null
$script:SawWarn  = $false
$script:UiLabels = @(); $script:UiSubs = @(); $script:UiChecks = @(); $script:UiSegs = @(); $script:UiSecBtns = @(); $script:UiCombos = @()
$script:CustomPath = ''
$script:UiCards = @()
$script:UiHost = $null

# ---------------------------------------------------------------- palette
function Get-GuiPalette([string]$Theme) {
    if ($Theme -eq 'Light') {
        return @{
            Back = (New-M10Col '#F5F5F7'); Panel = (New-M10Col '#FFFFFF'); Text = (New-M10Col '#1D1D1F')
            Sub = (New-M10Col '#6E6E73'); Accent = (New-M10Col '#007AFF'); LogBack = (New-M10Col '#FFFFFF')
            Border = (New-M10Col '#D2D2D7'); Good = (New-M10Col '#1F8A3B'); Warn = (New-M10Col '#B25E00'); Bad = (New-M10Col '#C4261D')
        }
    }
    return @{
        Back = (New-M10Col '#1C1C1E'); Panel = (New-M10Col '#2C2C2E'); Text = (New-M10Col '#F2F2F7')
        Sub = (New-M10Col '#98989D'); Accent = (New-M10Col '#0A84FF'); LogBack = (New-M10Col '#111113')
        Border = (New-M10Col '#3A3A3C'); Good = (New-M10Col '#32D74B'); Warn = (New-M10Col '#FFD60A'); Bad = (New-M10Col '#FF453A')
    }
}

# ---------------------------------------------------------------- control helpers
function New-Pt([int]$X, [int]$Y) { return New-Object System.Drawing.Point($X, $Y) }
function New-Sz([int]$W, [int]$H) { return New-Object System.Drawing.Size($W, $H) }

function New-Card([int]$X, [int]$Y, [int]$W, [int]$H) {
    $c = New-Object System.Windows.Forms.Panel
    $c.Location = New-Pt $X $Y; $c.Size = New-Sz $W $H
    $c.Add_Paint({
        param($sender, $e)
        if (-not $script:Pal) { return }
        $pen = New-Object System.Drawing.Pen($script:Pal.Border)
        $e.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
        $pen.Dispose()
    })
    $script:UiCards += $c
    $form.Controls.Add($c)
    return $c
}

function New-Label([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, $Font, [string]$Role = 'text') {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Location = New-Pt $X $Y; $l.Size = New-Sz $W $H; $l.Font = $Font
    $l.BackColor = [System.Drawing.Color]::Transparent
    if ($Role -eq 'sub') { $script:UiSubs += $l } else { $script:UiLabels += $l }
    $script:UiHost.Controls.Add($l)
    return $l
}

function New-Check([string]$Text, [int]$X, [int]$Y, [bool]$Checked = $true) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text; $c.Location = New-Pt $X $Y; $c.AutoSize = $true; $c.Checked = $Checked
    $c.Font = $script:FontBody; $c.Cursor = 'Hand'
    $script:UiChecks += $c
    $script:UiHost.Controls.Add($c)
    return $c
}

function Get-SegValue($Panel) {
    $sel = $Panel.Controls | Where-Object { $_.Checked } | Select-Object -First 1
    if ($sel) { return [string]$sel.Tag }
    return ''
}

function Set-SegValue($Panel, [string]$Value) {
    foreach ($rb in $Panel.Controls) { if ([string]$rb.Tag -eq $Value) { $rb.Checked = $true } }
}

function Update-Segments {
    if (-not $script:Pal) { return }
    foreach ($panel in $script:UiSegs) {
        $panel.BackColor = $script:Pal.Panel
        foreach ($rb in $panel.Controls) {
            $rb.FlatAppearance.BorderColor = $script:Pal.Border
            $rb.FlatAppearance.CheckedBackColor = $script:Pal.Accent
            if ($rb.Checked) {
                $rb.BackColor = $script:Pal.Accent
                $rb.ForeColor = [System.Drawing.Color]::White
                $rb.Font = $script:FontBold
            } else {
                $rb.BackColor = $script:Pal.Back
                $rb.ForeColor = $script:Pal.Text
                $rb.Font = $script:FontBody
            }
        }
    }
}

# $Items: array of @(caption, value)
function New-Segment($Items, [int]$X, [int]$Y, [int]$W, [int]$Index) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Pt $X $Y
    $panel.Size = New-Sz $W 34
    $bw = [int]($W / $Items.Count)
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Appearance = 'Button'; $rb.FlatStyle = 'Flat'; $rb.Text = $Items[$i][0]; $rb.Tag = $Items[$i][1]
        $rb.TextAlign = 'MiddleCenter'
        $rb.Size = New-Sz $bw 34; $rb.Location = New-Pt ($i * $bw) 0
        $rb.FlatAppearance.BorderSize = 1; $rb.Cursor = 'Hand'
        $rb.Checked = ($i -eq $Index)
        $rb.Add_CheckedChanged({ Update-Segments })
        $panel.Controls.Add($rb)
    }
    $script:UiSegs += $panel
    $script:UiHost.Controls.Add($panel)
    return $panel
}

function New-Button([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, [bool]$Primary) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Location = New-Pt $X $Y; $b.Size = New-Sz $W $H
    $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'; $b.Font = $script:FontBold
    if ($Primary) { $b.FlatAppearance.BorderSize = 0 } else { $b.FlatAppearance.BorderSize = 1; $script:UiSecBtns += $b }
    $script:UiHost.Controls.Add($b)
    return $b
}

# ---------------------------------------------------------------- form
$script:FontBody = New-Object System.Drawing.Font('Segoe UI', 9)
$script:FontBold = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$fontTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 20)
$fontSmall = New-Object System.Drawing.Font('Segoe UI Semibold', 8)
$fontDev   = New-Object System.Drawing.Font('Segoe UI Semibold', 11)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Modern 10'
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode = 'Dpi'
$form.ClientSize = New-Sz 820 748
$form.AutoScroll = $true
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = $script:FontBody
try {
    $icoPath = Join-Path $script:Root 'assets\Modern10.ico'
    if (Test-Path -LiteralPath $icoPath) { $form.Icon = New-Object System.Drawing.Icon($icoPath) }
    else {
        $bmpIco = New-M10IconBitmap 'Folder' 32 'Dark'
        $form.Icon = [System.Drawing.Icon]::FromHandle($bmpIco.GetHicon())
    }
} catch { }

# ---- header: app icon, title, developer credit
$script:UiHost = $form
$logo = New-Object System.Windows.Forms.PictureBox
$logo.Location = New-Pt 24 18; $logo.Size = New-Sz 52 52; $logo.SizeMode = 'Zoom'
$logo.BackColor = [System.Drawing.Color]::Transparent
try {
    $logoPath = Join-Path $script:Root 'assets\Modern10.png'
    if (Test-Path -LiteralPath $logoPath) {
        $lbytes = [System.IO.File]::ReadAllBytes($logoPath)
        $lms = New-Object System.IO.MemoryStream(, $lbytes)
        $logo.Image = [System.Drawing.Image]::FromStream($lms)
    }
} catch { }
$form.Controls.Add($logo)
[void](New-Label 'Modern 10' 86 12 400 38 $fontTitle 'text')
[void](New-Label 'Glassy, macOS-inspired Windows 10 - reversible, nothing runs in the background' 88 52 480 20 $script:FontBody 'sub')

$lblDevCap = New-Label 'DEVELOPED BY' 596 16 200 14 $fontSmall 'sub'
$lblDevCap.TextAlign = 'MiddleRight'
$lblDev = New-Label $script:M10Developer 596 30 200 24 $fontDev 'text'
$lblDev.TextAlign = 'MiddleRight'
$lblMail = New-Label 'tasmon@outlook.com' 596 54 200 18 $script:FontBody 'sub'
$lblMail.TextAlign = 'MiddleRight'
$lblVer = New-Label ('Version ' + $script:M10Version) 596 72 200 18 $script:FontBody 'sub'
$lblVer.TextAlign = 'MiddleRight'

# start with the theme that matches the current Windows mode
$startTheme = 0
try {
    $cur = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop).AppsUseLightTheme
    if ($cur -eq 1) { $startTheme = 1 }
} catch { }

# ---- card A: theme and taskbar (left column)
$cardA = New-Card 24 96 384 206
$script:UiHost = $cardA
[void](New-Label 'THEME' 16 14 168 16 $fontSmall 'sub')
[void](New-Label 'TASKBAR POSITION' 200 14 168 16 $fontSmall 'sub')
$segTheme = New-Segment @(@('Dark', 'Dark'), @('Light', 'Light')) 16 32 168 $startTheme
$segPos   = New-Segment @(@('Top', 'Top'), @('Bottom', 'Bottom')) 200 32 168 0
[void](New-Label 'TASKBAR ICON SIZE' 16 76 168 16 $fontSmall 'sub')
$segSize  = New-Segment @(@('Small', 'Small'), @('Default', 'Default'), @('Keep', 'Keep')) 16 94 168 0
$btnDock  = New-Button 'Dock options...' 200 94 168 34 $false
[void](New-Label 'TASKBAR BEHAVIOUR' 16 138 200 16 $fontSmall 'sub')
$segBeh   = New-Segment @(@('Keep', 'Keep'), @('Always show', 'Show'), @('Auto-hide', 'AutoHide')) 16 156 352 0

# ---- card B: what to apply (left column)
$cardB = New-Card 24 314 384 224
$script:UiHost = $cardB
[void](New-Label 'APPLY' 16 14 200 16 $fontSmall 'sub')
$chkWall    = New-Check 'Wallpaper' 16 38
$chkLock    = New-Check 'Lock screen' 16 63
$chkRestart = New-Check 'Restart Explorer (recommended)' 16 88
$chkSys     = New-Check 'System, drive, folder-type icons' 16 113
$chkFolder  = New-Check 'This PC folder icons' 16 138
$chkProfile = New-Check 'Profile folder icons' 16 163
$chkGeneric = New-Check 'All users too (asks for admin)' 16 188

$chkSys.Add_CheckedChanged({
    $chkFolder.Enabled  = $chkSys.Checked
    $chkProfile.Enabled = $chkSys.Checked
    $chkGeneric.Enabled = $chkSys.Checked
    $cmbIcon.Enabled    = $chkSys.Checked
})
$chkLock.Add_CheckedChanged({ $cmbLock.Enabled = $chkLock.Checked })
$chkWall.Add_CheckedChanged({
    $cmbWall.Enabled = $chkWall.Checked
    $btnBrowse.Enabled = $chkWall.Checked
})

function New-Combo([string[]]$Items, [int]$X, [int]$Y, [int]$W) {
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'; $c.FlatStyle = 'Flat'; $c.Font = $script:FontBody
    $c.Location = New-Pt $X $Y; $c.Size = New-Sz $W 26; $c.Cursor = 'Hand'
    foreach ($i in $Items) { [void]$c.Items.Add($i) }
    $c.SelectedIndex = 0
    $script:UiCombos += $c
    $script:UiHost.Controls.Add($c)
    return $c
}

# ---- card C: wallpaper and lock screen (right column)
$cardC = New-Card 424 96 372 219
$script:UiHost = $cardC
[void](New-Label 'WALLPAPER' 16 14 200 16 $fontSmall 'sub')
$wallItems = @(Get-M10WallpaperStyleNames) + @('Custom image...')
$cmbWall = New-Combo $wallItems 16 36 340
$btnBrowse = New-Button 'Browse for your own image...' 16 68 340 28 $false
$pbWall = New-Object System.Windows.Forms.PictureBox
$pbWall.Location = New-Pt 16 104; $pbWall.Size = New-Sz 176 99; $pbWall.SizeMode = 'Zoom'
$pbWall.BorderStyle = 'FixedSingle'
$cardC.Controls.Add($pbWall)
[void](New-Label 'LOCK SCREEN' 208 104 148 16 $fontSmall 'sub')
$cmbLock = New-Combo (@('Same as wallpaper') + @(Get-M10WallpaperStyleNames)) 208 122 148

# ---- card D: icon theme (right column)
$cardD = New-Card 424 327 372 188
$script:UiHost = $cardD
[void](New-Label 'ICON THEME' 16 14 200 16 $fontSmall 'sub')
$cmbIcon = New-Combo @(Get-M10IconThemeNames) 16 36 340
$previewKinds = @('Folder', 'Documents', 'Downloads', 'Objects3D', 'Archive', 'ThisPC', 'Drive', 'RecycleFull', 'User', 'QuickAccess', 'Libraries', 'OneDrive')
$script:Previews = @()
for ($i = 0; $i -lt $previewKinds.Count; $i++) {
    $pb = New-Object System.Windows.Forms.PictureBox
    $pb.Size = New-Sz 44 44
    $pb.Location = New-Pt (16 + ($i % 6) * 56) (76 + [Math]::Floor($i / 6) * 56)
    $pb.SizeMode = 'Zoom'
    $pb.BackColor = [System.Drawing.Color]::Transparent
    $pb.Tag = $previewKinds[$i]
    $cardD.Controls.Add($pb)
    $script:Previews += $pb
}
$script:UiHost = $form

function Update-Preview {
    $t = Get-SegValue $segTheme
    $it = [string]$cmbIcon.SelectedItem
    foreach ($pb in $script:Previews) {
        $old = $pb.Image
        $pb.Image = New-M10IconBitmap ([string]$pb.Tag) 64 $t $it
        if ($old) { $old.Dispose() }
    }
}

function Get-WallStyle {
    $v = [string]$cmbWall.SelectedItem
    if ($v -like 'Custom*') { return 'Custom' }
    return $v
}

function Update-WallPreview {
    $old = $pbWall.Image
    $img = $null
    try {
        if ((Get-WallStyle) -eq 'Custom') {
            if ($script:CustomPath -and (Test-Path -LiteralPath $script:CustomPath)) {
                $bytes = [System.IO.File]::ReadAllBytes($script:CustomPath)
                $ms = New-Object System.IO.MemoryStream(, $bytes)
                $img = [System.Drawing.Image]::FromStream($ms)
            }
        } else {
            $img = New-M10GlassBitmap -W 400 -H 225 -Mode (Get-SegValue $segTheme) -Kind 'Wallpaper' -Style (Get-WallStyle) -Grain $false
        }
    } catch { $img = $null }
    $pbWall.Image = $img
    if ($old) { $old.Dispose() }
}

$cmbWall.Add_SelectedIndexChanged({ Update-WallPreview })
$cmbIcon.Add_SelectedIndexChanged({ Update-Preview })

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Choose a wallpaper image'
    $dlg.Filter = 'Images (*.jpg;*.jpeg;*.png;*.bmp)|*.jpg;*.jpeg;*.png;*.bmp'
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:CustomPath = $dlg.FileName
        $cmbWall.SelectedIndex = $cmbWall.Items.Count - 1
        Update-WallPreview
    }
    $dlg.Dispose()
})

# ---- action row, progress and log (full width)
$btnApply   = New-Button 'Apply' 24 552 170 42 $true
$btnRestore = New-Button 'Restore original' 206 552 140 42 $false
$btnLog     = New-Button 'Open log' 358 552 100 42 $false
$lblStatus  = New-Label 'Ready' 476 562 320 22 $script:FontBody 'sub'

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Pt 24 602
$progress.Size = New-Sz 772 6
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 30
$progress.Visible = $false
$form.Controls.Add($progress)

$log = New-Object System.Windows.Forms.RichTextBox
$log.Location = New-Pt 24 612
$log.Size = New-Sz 772 104
$log.ReadOnly = $true
$log.BorderStyle = 'FixedSingle'
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.DetectUrls = $false
$form.Controls.Add($log)

$lblFoot = New-Label 'Modern 10 - nothing runs in the background, every change is backed up' 24 722 772 20 $script:FontBody 'sub'

# ---------------------------------------------------------------- theming
function Apply-GuiTheme([string]$Theme) {
    $script:Pal = Get-GuiPalette $Theme
    $p = $script:Pal
    $form.BackColor = $p.Back
    $form.ForeColor = $p.Text
    foreach ($l in $script:UiLabels) { $l.ForeColor = $p.Text }
    foreach ($l in $script:UiSubs)   { $l.ForeColor = $p.Sub }
    foreach ($c in $script:UiChecks) { $c.ForeColor = $p.Text; $c.BackColor = $p.Panel }
    foreach ($b in $script:UiSecBtns) {
        $b.BackColor = $p.Back; $b.ForeColor = $p.Text; $b.FlatAppearance.BorderColor = $p.Border
    }
    foreach ($c in $script:UiCombos) { $c.BackColor = $p.Back; $c.ForeColor = $p.Text }
    $pbWall.BackColor = $p.Back
    foreach ($cd in $script:UiCards) { $cd.BackColor = $p.Panel; $cd.Invalidate() }
    $btnApply.BackColor = $p.Accent
    $btnApply.ForeColor = [System.Drawing.Color]::White
    $lblDev.ForeColor = $p.Accent
    $log.BackColor = $p.LogBack
    $log.ForeColor = $p.Text
    Update-Segments
    if ($form.IsHandleCreated) {
        $v = 0; if ($Theme -eq 'Dark') { $v = 1 }
        [void][M10Gui]::DwmSetWindowAttribute($form.Handle, 20, [ref]$v, 4)
        [void][M10Gui]::DwmSetWindowAttribute($form.Handle, 19, [ref]$v, 4)
    }
}

foreach ($rb in $segTheme.Controls) {
    $rb.Add_CheckedChanged({
        if ($this.Checked) {
            $t = Get-SegValue $segTheme
            Apply-GuiTheme $t
            Update-Preview
            Update-WallPreview
        }
    })
}

# ---------------------------------------------------------------- log output
function Add-LogLine([string]$Line, $Color = $null) {
    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    if (-not $Color) { $Color = $script:Pal.Text }
    $log.SelectionStart = $log.TextLength
    $log.SelectionLength = 0
    $log.SelectionColor = $Color
    $log.AppendText($Line + "`n")
    $log.SelectionColor = $script:Pal.Text
    $log.ScrollToCaret()
}

function Add-EngineLine([string]$Item) {
    $i = $Item.IndexOf('|')
    if ($i -lt 1) { Add-LogLine $Item; return }
    $lvl = $Item.Substring(0, $i); $text = $Item.Substring($i + 1)
    switch ($lvl) {
        'ok'   { Add-LogLine ('+ ' + $text) $script:Pal.Good }
        'warn' { $script:SawWarn = $true; Add-LogLine ('! ' + $text) $script:Pal.Warn }
        'err'  { $script:SawWarn = $true; Add-LogLine ('x ' + $text) $script:Pal.Bad }
        'done' { Add-LogLine ('> ' + $text) $script:Pal.Text }
        default { Add-LogLine ('> ' + $text) $script:Pal.Sub }
    }
}

function Set-Busy([bool]$Busy) {
    $btnApply.Enabled = -not $Busy
    $btnRestore.Enabled = -not $Busy
    $btnDock.Enabled = -not $Busy
    $cmbWall.Enabled = ((-not $Busy) -and $chkWall.Checked)
    $btnBrowse.Enabled = ((-not $Busy) -and $chkWall.Checked)
    $cmbIcon.Enabled = ((-not $Busy) -and $chkSys.Checked)
    $cmbLock.Enabled = ((-not $Busy) -and $chkLock.Checked)
    $progress.Visible = $Busy
    foreach ($p in $segTheme, $segPos, $segSize, $segBeh) { $p.Enabled = -not $Busy }
}

function Read-EngineQueue {
    if (-not $script:Queue) { return }
    $item = $null
    while ($script:Queue.TryDequeue([ref]$item)) { Add-EngineLine ([string]$item) }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    Read-EngineQueue
    if ($script:Async -and $script:Async.IsCompleted) {
        $timer.Stop()
        $failed = $false
        try { $script:Shell.EndInvoke($script:Async) } catch {
            $failed = $true
            Add-LogLine ('x ' + $_.Exception.Message) $script:Pal.Bad
        }
        Read-EngineQueue
        foreach ($e in $script:Shell.Streams.Error) {
            $failed = $true
            Add-LogLine ('x ' + [string]$e) $script:Pal.Bad
        }
        try { $script:Shell.Dispose(); $script:Runspace.Close(); $script:Runspace.Dispose() } catch { }
        $script:Async = $null; $script:Shell = $null; $script:Runspace = $null
        Set-Busy $false
        if ($failed) { $lblStatus.Text = 'Finished with errors - see the log' }
        elseif ($script:SawWarn) { $lblStatus.Text = 'Finished with warnings' }
        else { $lblStatus.Text = 'Finished' }
    }
})

# Runs Invoke-M10Apply / Invoke-M10Restore in a background runspace.
function Start-Engine([string]$Mode, $Opt, [string]$Title) {
    $script:Queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    $script:SawWarn = $false
    $log.Clear()
    Add-LogLine "> $Title" $script:Pal.Sub
    $lblStatus.Text = $Title
    Set-Busy $true
    try {
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass
        $rs = [runspacefactory]::CreateRunspace($iss)
        $rs.ApartmentState = 'STA'
        $rs.ThreadOptions = 'ReuseThread'
        $rs.Open()
        $rs.SessionStateProxy.SetVariable('M10Queue', $script:Queue)
        $rs.SessionStateProxy.SetVariable('M10Opt', $Opt)
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        $enginePath = $script:EnginePath.Replace("'", "''")
        $fn = 'Invoke-M10Apply'; if ($Mode -eq 'Restore') { $fn = 'Invoke-M10Restore' }
        [void]$ps.AddScript(". '$enginePath'; $fn `$M10Opt")
        $script:Runspace = $rs
        $script:Shell = $ps
        $script:Async = $ps.BeginInvoke()
        $timer.Start()
    } catch {
        Add-LogLine ('x Could not start the engine: ' + $_.Exception.Message) $script:Pal.Bad
        Set-Busy $false
    }
}

function Get-GuiOptions {
    $o = New-M10Options
    $o.Theme           = Get-SegValue $segTheme
    $o.Position        = Get-SegValue $segPos
    $o.IconSize        = Get-SegValue $segSize
    $o.Behavior        = Get-SegValue $segBeh
    $o.Wallpaper       = $chkWall.Checked
    $o.WallpaperStyle  = Get-WallStyle
    $o.CustomWallpaper = $script:CustomPath
    $o.LockStyle       = $(if ($cmbLock.SelectedIndex -le 0) { 'Match' } else { [string]$cmbLock.SelectedItem })
    $o.IconTheme       = [string]$cmbIcon.SelectedItem
    $o.LockScreen      = $chkLock.Checked
    $o.RestartExplorer = $chkRestart.Checked
    $o.SystemIcons     = $chkSys.Checked
    $o.FolderIcons     = ($chkSys.Checked -and $chkFolder.Checked)
    $o.ProfileIcons    = ($chkSys.Checked -and $chkProfile.Checked)
    $o.GenericFolder   = ($chkSys.Checked -and $chkGeneric.Checked)
    return $o
}

# ---------------------------------------------------------------- dock options window
function Show-DockWindow {
    $p = $script:Pal
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Dock options - Modern 10'
    $dlg.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
    $dlg.AutoScaleMode = 'Dpi'
    $dlg.ClientSize = New-Sz 640 470
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $p.Back; $dlg.ForeColor = $p.Text; $dlg.Font = $script:FontBody
    try { $dlg.Icon = $form.Icon } catch { }
    $dlg.ShowInTaskbar = $false

    $t = New-Object System.Windows.Forms.Label
    $t.Text = 'Dock-style taskbar'; $t.Font = $fontDev; $t.Location = New-Pt 20 14; $t.Size = New-Sz 600 24
    $dlg.Controls.Add($t)

    $d = New-Object System.Windows.Forms.Label
    $d.Text = "No extra software: the preset below puts the taskbar at the bottom with standard icons and hides it until you move the mouse to the edge (a registry setting). It fills in the options on the main window; press Apply there to use it."
    $d.Location = New-Pt 20 42; $d.Size = New-Sz 600 54; $d.ForeColor = $p.Sub
    $dlg.Controls.Add($d)

    $bp = New-Object System.Windows.Forms.Button
    $bp.Text = 'Use the dock-style preset'; $bp.FlatStyle = 'Flat'; $bp.Font = $script:FontBold
    $bp.Location = New-Pt 20 100; $bp.Size = New-Sz 220 36
    $bp.BackColor = $p.Accent; $bp.ForeColor = [System.Drawing.Color]::White; $bp.FlatAppearance.BorderSize = 0
    $bp.Add_Click({
        Set-SegValue $segPos 'Bottom'; Set-SegValue $segSize 'Default'; Set-SegValue $segBeh 'AutoHide'
        $this.FindForm().Close()
    })
    $dlg.Controls.Add($bp)

    $h = New-Object System.Windows.Forms.Label
    $h.Text = 'OPTIONAL ADD-ONS (nothing is installed unless you tick it and press Install)'
    $h.Font = $fontSmall; $h.ForeColor = $p.Sub; $h.Location = New-Pt 20 156; $h.Size = New-Sz 600 16
    $dlg.Controls.Add($h)

    $items = @(
        @{ Name = 'KiraDock'; Id = '9NPD1H35D0WD'; Source = 'msstore'
           Url = 'https://apps.microsoft.com/detail/9NPD1H35D0WD'
           Info = 'Purpose: a macOS-style dock for Windows - a floating, animated launcher bar for your favourite apps at the edge of the screen. Free app from the Microsoft Store.' },
        @{ Name = 'TaskbarX'; Id = 'ChrisAndriessen.TaskbarX'; Source = 'winget'
           Url = 'https://github.com/ChrisAnd1998/TaskbarX/releases'
           Info = 'Purpose: centres the taskbar icons and animates them, for a floating-dock look on the normal taskbar. A small open-source app from GitHub that keeps running in the background.' }
    )
    $y = 182
    foreach ($it in $items) {
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text = $it.Name; $c.Font = $script:FontBold; $c.AutoSize = $true; $c.Cursor = 'Hand'
        $c.Location = New-Pt 20 $y; $c.Tag = $it
        $c.ForeColor = $p.Text; $c.BackColor = $p.Back
        $dlg.Controls.Add($c)
        $s = New-Object System.Windows.Forms.Label
        $s.Text = $it.Info; $s.ForeColor = $p.Sub; $s.Location = New-Pt 40 ($y + 26); $s.Size = New-Sz 580 50
        $dlg.Controls.Add($s)
        $lk = New-Object System.Windows.Forms.LinkLabel
        $lk.Text = $it.Url; $lk.Location = New-Pt 40 ($y + 78); $lk.Size = New-Sz 580 18
        $lk.LinkColor = $p.Accent; $lk.ActiveLinkColor = $p.Accent
        $lk.Tag = $it.Url
        $lk.Add_LinkClicked({ param($s2, $e2) Start-Process ([string]$s2.Tag) })
        $dlg.Controls.Add($lk)
        $y += 112
    }

    $bi = New-Object System.Windows.Forms.Button
    $bi.Text = 'Install selected'; $bi.FlatStyle = 'Flat'; $bi.Font = $script:FontBold
    $bi.Location = New-Pt 20 412; $bi.Size = New-Sz 180 36
    $bi.BackColor = $p.Panel; $bi.ForeColor = $p.Text; $bi.FlatAppearance.BorderColor = $p.Border
    $bi.Add_Click({
        $form2 = $this.FindForm()
        $sel = @()
        foreach ($ctl in $form2.Controls) { if (($ctl -is [System.Windows.Forms.CheckBox]) -and $ctl.Checked) { $sel += $ctl.Tag } }
        if ($sel.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('Tick KiraDock and/or TaskbarX first. Nothing is installed otherwise.', 'Modern 10', 'OK', 'Information') | Out-Null
            return
        }
        $names = ($sel | ForEach-Object { $_.Name }) -join ' and '
        $r = [System.Windows.Forms.MessageBox]::Show(("Install {0}?`n`nA setup window opens (it uses winget). If winget is missing or fails, the download page opens instead." -f $names), 'Modern 10', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
        foreach ($it2 in $sel) {
            $src = ''
            if ($it2.Source -eq 'msstore') { $src = ' --source msstore' }
            $cmd = "Write-Host 'Installing $($it2.Name)...'; winget install --id $($it2.Id) -e$src --accept-package-agreements --accept-source-agreements; if (`$LASTEXITCODE -ne 0) { Write-Host 'Could not install with winget. Opening the download page instead...'; Start-Process '$($it2.Url)' }; Read-Host 'Press Enter to close this window'"
            try { Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', ('"' + $cmd + '"')) }
            catch { Start-Process $it2.Url }
        }
    })
    $dlg.Controls.Add($bi)

    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'Optional. Modern 10 works without them. Uninstall them later from Settings > Apps.'
    $note.ForeColor = $p.Sub; $note.Location = New-Pt 212 421; $note.Size = New-Sz 410 20
    $dlg.Controls.Add($note)
    $dlg.Add_Shown({
        $v = 0; if ($script:Pal.Back.R -lt 100) { $v = 1 }
        [void][M10Gui]::DwmSetWindowAttribute($this.Handle, 20, [ref]$v, 4)
        [void][M10Gui]::DwmSetWindowAttribute($this.Handle, 19, [ref]$v, 4)
    })
    [void]$dlg.ShowDialog($form)
    $dlg.Dispose()
}

# ---------------------------------------------------------------- actions
$btnApply.Add_Click({
    if ($chkRestart.Checked) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "Explorer will restart to apply the taskbar and icons.`nOpen File Explorer windows will close. Continue?",
            'Modern 10', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
    }
    $o = Get-GuiOptions
    if ($o.Wallpaper -and $o.WallpaperStyle -eq 'Custom' -and -not (Test-Path -LiteralPath ([string]$o.CustomWallpaper))) {
        [System.Windows.Forms.MessageBox]::Show('Choose an image first (Browse for your own image...).', 'Modern 10', 'OK', 'Information') | Out-Null
        return
    }
    Start-Engine 'Apply' $o ("Applying {0} theme, taskbar at {1}..." -f $o.Theme, $o.Position.ToLower())
})

$btnRestore.Add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Put back your original settings, icons and taskbar?`nExplorer will restart.",
        'Modern 10', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    $o = New-M10Options
    $o.RestartExplorer = $true
    Start-Engine 'Restore' $o 'Restoring original settings...'
})

$btnLog.Add_Click({
    if (Test-Path -LiteralPath $script:LogFile) { Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:LogFile) }
    else { [System.Windows.Forms.MessageBox]::Show('No log yet - press Apply first.', 'Modern 10', 'OK', 'Information') | Out-Null }
})

$btnDock.Add_Click({ Show-DockWindow })

$form.Add_FormClosing({
    param($s, $e)
    if ($script:Async -and -not $script:Async.IsCompleted) {
        $r = [System.Windows.Forms.MessageBox]::Show('Modern 10 is still working. Close anyway?', 'Modern 10', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { $e.Cancel = $true }
    }
})

$form.Add_Shown({
    Apply-GuiTheme (Get-SegValue $segTheme)
    Add-LogLine '> Pick your options and press Apply. Everything can be undone with "Restore original".' $script:Pal.Sub
})

# initial paint
Apply-GuiTheme (Get-SegValue $segTheme)
Update-Preview
Update-WallPreview
[void]$form.ShowDialog()

} catch {
    Show-M10Error ("Modern 10 could not start:`n`n" + $_.Exception.Message + "`n`n" + $_.ScriptStackTrace)
    exit 1
}
