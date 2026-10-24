#Requires -Version 5.1
<#
.SYNOPSIS
    Modern 10 - graphical front-end.

.DESCRIPTION
    A small Windows Forms window (built into Windows, nothing to install) that lets you pick
    theme, taskbar position, taskbar icon size and which parts to apply, previews the icons
    that will be drawn, and runs Modern10.ps1 with live output.
#>
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -STA -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
}
'@
}
[void][M10Gui]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()

. (Join-Path $PSScriptRoot 'Modern10.Icons.ps1')

$script:Engine  = Join-Path $PSScriptRoot 'Modern10.ps1'
$script:LogFile = Join-Path (Join-Path $env:ProgramData 'Modern10') 'modern10.log'
$script:Pal     = $null
$script:Proc    = $null
$script:UiLabels = @(); $script:UiSubs = @(); $script:UiChecks = @(); $script:UiSegs = @(); $script:UiSecBtns = @()

if (-not (Test-Path -LiteralPath $script:Engine)) {
    [System.Windows.Forms.MessageBox]::Show("Modern10.ps1 was not found next to this GUI:`n$script:Engine", 'Modern 10', 'OK', 'Error') | Out-Null
    exit 1
}

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

function New-Label([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, $Font, [string]$Role = 'text') {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Location = New-Pt $X $Y; $l.Size = New-Sz $W $H; $l.Font = $Font
    $l.BackColor = [System.Drawing.Color]::Transparent
    if ($Role -eq 'sub') { $script:UiSubs += $l } else { $script:UiLabels += $l }
    $form.Controls.Add($l)
    return $l
}

function New-Check([string]$Text, [int]$X, [int]$Y, [bool]$Checked = $true) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text; $c.Location = New-Pt $X $Y; $c.AutoSize = $true; $c.Checked = $Checked
    $c.Font = $script:FontBody; $c.Cursor = 'Hand'
    $script:UiChecks += $c
    $form.Controls.Add($c)
    return $c
}

function Get-SegValue($Panel) {
    $sel = $Panel.Controls | Where-Object { $_.Checked } | Select-Object -First 1
    if ($sel) { return [string]$sel.Text }
    return ''
}

function Update-Segments {
    if (-not $script:Pal) { return }
    foreach ($panel in $script:UiSegs) {
        foreach ($rb in $panel.Controls) {
            $rb.FlatAppearance.BorderColor = $script:Pal.Border
            $rb.FlatAppearance.CheckedBackColor = $script:Pal.Accent
            if ($rb.Checked) {
                $rb.BackColor = $script:Pal.Accent
                $rb.ForeColor = [System.Drawing.Color]::White
                $rb.Font = $script:FontBold
            } else {
                $rb.BackColor = $script:Pal.Panel
                $rb.ForeColor = $script:Pal.Text
                $rb.Font = $script:FontBody
            }
        }
    }
}

function New-Segment([string[]]$Items, [int]$X, [int]$Y, [int]$W, [int]$Index) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Pt $X $Y
    $panel.Size = New-Sz $W 34
    $bw = [int]($W / $Items.Count)
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Appearance = 'Button'; $rb.FlatStyle = 'Flat'; $rb.Text = $Items[$i]; $rb.TextAlign = 'MiddleCenter'
        $rb.Size = New-Sz $bw 34; $rb.Location = New-Pt ($i * $bw) 0
        $rb.FlatAppearance.BorderSize = 1; $rb.Cursor = 'Hand'
        $rb.Checked = ($i -eq $Index)
        $rb.Add_CheckedChanged({ Update-Segments })
        $panel.Controls.Add($rb)
    }
    $script:UiSegs += $panel
    $form.Controls.Add($panel)
    return $panel
}

function New-Button([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, [bool]$Primary) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Location = New-Pt $X $Y; $b.Size = New-Sz $W $H
    $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'; $b.Font = $script:FontBold
    if ($Primary) { $b.FlatAppearance.BorderSize = 0 } else { $b.FlatAppearance.BorderSize = 1; $script:UiSecBtns += $b }
    $form.Controls.Add($b)
    return $b
}

# ---------------------------------------------------------------- form
$script:FontBody = New-Object System.Drawing.Font('Segoe UI', 9)
$script:FontBold = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$fontTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 20)
$fontSmall = New-Object System.Drawing.Font('Segoe UI Semibold', 8)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Modern 10'
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode = 'Dpi'
$form.ClientSize = New-Sz 760 660
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = $script:FontBody
try {
    $bmpIco = New-M10IconBitmap 'Folder' 32 'Dark'
    $form.Icon = [System.Drawing.Icon]::FromHandle($bmpIco.GetHicon())
} catch { }

[void](New-Label 'Modern 10' 24 12 400 40 $fontTitle 'text')
[void](New-Label 'Glassy, macOS-inspired Windows 10 - no installs, fully reversible' 26 54 560 20 $script:FontBody 'sub')

[void](New-Label 'THEME' 24 94 200 16 $fontSmall 'sub')
[void](New-Label 'TASKBAR POSITION' 270 94 200 16 $fontSmall 'sub')
[void](New-Label 'TASKBAR ICON SIZE' 510 94 220 16 $fontSmall 'sub')

# start with the theme that matches the current Windows mode
$startTheme = 0
try {
    $cur = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop).AppsUseLightTheme
    if ($cur -eq 1) { $startTheme = 1 }
} catch { }

$segTheme = New-Segment @('Dark', 'Light') 24 114 220 $startTheme
$segPos   = New-Segment @('Top', 'Bottom') 270 114 220 0
$segSize  = New-Segment @('Small', 'Default', 'Keep') 510 114 226 0

[void](New-Label 'APPLY' 24 168 200 16 $fontSmall 'sub')
$chkWall    = New-Check 'Wallpaper' 24 192
$chkLock    = New-Check 'Lock screen' 24 220
$chkRestart = New-Check 'Restart Explorer (recommended)' 24 248
$chkSys     = New-Check 'System and drive icons' 270 192
$chkFolder  = New-Check 'Generic folder icon (asks for admin)' 270 220
$chkUser    = New-Check 'Documents, Downloads, Pictures... icons' 270 248

$chkSys.Add_CheckedChanged({
    $chkFolder.Enabled = $chkSys.Checked
    $chkUser.Enabled = $chkSys.Checked
})

[void](New-Label 'ICON PREVIEW' 510 168 200 16 $fontSmall 'sub')
$previewKinds = @('Folder', 'ThisPC', 'Drive', 'RecycleFull', 'User', 'Network')
$script:Previews = @()
for ($i = 0; $i -lt $previewKinds.Count; $i++) {
    $pb = New-Object System.Windows.Forms.PictureBox
    $pb.Size = New-Sz 64 64
    $pb.Location = New-Pt (510 + ($i % 3) * 76) (190 + [Math]::Floor($i / 3) * 76)
    $pb.SizeMode = 'Zoom'
    $pb.BackColor = [System.Drawing.Color]::Transparent
    $pb.Tag = $previewKinds[$i]
    $form.Controls.Add($pb)
    $script:Previews += $pb
}

function Update-Preview([string]$Theme) {
    foreach ($pb in $script:Previews) {
        $old = $pb.Image
        $pb.Image = New-M10IconBitmap ([string]$pb.Tag) 64 $Theme
        if ($old) { $old.Dispose() }
    }
}

$btnApply   = New-Button 'Apply' 24 352 170 42 $true
$btnRestore = New-Button 'Restore original' 206 352 140 42 $false
$btnLog     = New-Button 'Open log' 358 352 100 42 $false
$lblStatus  = New-Label 'Ready' 476 362 260 22 $script:FontBody 'sub'

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Pt 24 404
$progress.Size = New-Sz 712 6
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 30
$progress.Visible = $false
$form.Controls.Add($progress)

$log = New-Object System.Windows.Forms.RichTextBox
$log.Location = New-Pt 24 418
$log.Size = New-Sz 712 224
$log.ReadOnly = $true
$log.BorderStyle = 'FixedSingle'
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.DetectUrls = $false
$form.Controls.Add($log)

# ---------------------------------------------------------------- theming
function Apply-GuiTheme([string]$Theme) {
    $script:Pal = Get-GuiPalette $Theme
    $p = $script:Pal
    $form.BackColor = $p.Back
    $form.ForeColor = $p.Text
    foreach ($l in $script:UiLabels) { $l.ForeColor = $p.Text }
    foreach ($l in $script:UiSubs)   { $l.ForeColor = $p.Sub }
    foreach ($c in $script:UiChecks) { $c.ForeColor = $p.Text; $c.BackColor = $p.Back }
    foreach ($b in $script:UiSecBtns) {
        $b.BackColor = $p.Panel; $b.ForeColor = $p.Text; $b.FlatAppearance.BorderColor = $p.Border
    }
    $btnApply.BackColor = $p.Accent
    $btnApply.ForeColor = [System.Drawing.Color]::White
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
            Update-Preview $t
        }
    })
}

# ---------------------------------------------------------------- log output
function Add-LogLine([string]$Line, $Color = $null) {
    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    if (-not $Color) {
        $t = $Line.TrimStart()
        $Color = $script:Pal.Text
        if     ($t.StartsWith('+')) { $Color = $script:Pal.Good }
        elseif ($t.StartsWith('!')) { $Color = $script:Pal.Warn }
        elseif ($t.StartsWith('>')) { $Color = $script:Pal.Sub }
    }
    $log.SelectionStart = $log.TextLength
    $log.SelectionLength = 0
    $log.SelectionColor = $Color
    $log.AppendText($Line + "`n")
    $log.SelectionColor = $script:Pal.Text
    $log.ScrollToCaret()
}

function Read-NewOutput {
    if (-not $script:OutFile -or -not (Test-Path -LiteralPath $script:OutFile)) { return }
    try {
        $fs = [System.IO.File]::Open($script:OutFile, 'Open', 'Read', 'ReadWrite')
        try {
            if ($fs.Length -gt $script:ReadPos) {
                [void]$fs.Seek($script:ReadPos, 'Begin')
                $buf = New-Object byte[] ($fs.Length - $script:ReadPos)
                $n = $fs.Read($buf, 0, $buf.Length)
                $script:ReadPos += $n
                $text = $script:Partial + [System.Text.Encoding]::Default.GetString($buf, 0, $n)
                $parts = $text -split "`n"
                $script:Partial = $parts[$parts.Count - 1]
                for ($i = 0; $i -lt $parts.Count - 1; $i++) { Add-LogLine ($parts[$i].TrimEnd("`r")) }
            }
        } finally { $fs.Close() }
    } catch { }
}

function Set-Busy([bool]$Busy) {
    $btnApply.Enabled = -not $Busy
    $btnRestore.Enabled = -not $Busy
    $progress.Visible = $Busy
    foreach ($p in $segTheme, $segPos, $segSize) { $p.Enabled = -not $Busy }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    Read-NewOutput
    if ($script:Proc -and $script:Proc.HasExited) {
        Read-NewOutput
        if ($script:Partial) { Add-LogLine $script:Partial; $script:Partial = '' }
        if (Test-Path -LiteralPath $script:ErrFile) {
            $err = [string](Get-Content -LiteralPath $script:ErrFile -Raw -ErrorAction SilentlyContinue)
            foreach ($line in ($err -split "`n")) { Add-LogLine ($line.TrimEnd("`r")) $script:Pal.Bad }
        }
        $timer.Stop()
        $code = $script:Proc.ExitCode
        Remove-Item -LiteralPath $script:OutFile, $script:ErrFile -ErrorAction SilentlyContinue
        $script:Proc = $null
        Set-Busy $false
        if ($code -eq 0) { $lblStatus.Text = 'Finished' } else { $lblStatus.Text = "Finished with errors (code $code)" }
    }
})

function Start-Engine([string]$ArgLine, [string]$Title) {
    $tmp = [System.IO.Path]::GetTempPath()
    $id = [guid]::NewGuid().ToString('N')
    $script:OutFile = Join-Path $tmp "m10-out-$id.txt"
    $script:ErrFile = Join-Path $tmp "m10-err-$id.txt"
    $script:ReadPos = 0
    $script:Partial = ''
    $log.Clear()
    Add-LogLine "> $Title" $script:Pal.Sub
    $lblStatus.Text = $Title
    Set-Busy $true
    $a = '-NoProfile -ExecutionPolicy Bypass -File "{0}" {1} -NoPause' -f $script:Engine, $ArgLine
    try {
        $script:Proc = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -ArgumentList $a -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $script:OutFile -RedirectStandardError $script:ErrFile
        $null = $script:Proc.Handle    # keep the handle so ExitCode is readable later
        $timer.Start()
    } catch {
        Add-LogLine ("! Could not start the engine: " + $_.Exception.Message) $script:Pal.Bad
        Set-Busy $false
    }
}

# ---------------------------------------------------------------- actions
$btnApply.Add_Click({
    $theme = Get-SegValue $segTheme
    $pos   = Get-SegValue $segPos
    $size  = Get-SegValue $segSize
    if ($chkRestart.Checked) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "Explorer will restart to apply the taskbar and icons.`nOpen File Explorer windows will close. Continue?",
            'Modern 10', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
    }
    $a = "-Theme $theme -TaskbarPosition $pos -IconSize $size"
    if (-not $chkWall.Checked)    { $a += ' -NoWallpaper' }
    if (-not $chkLock.Checked)    { $a += ' -NoLockScreen' }
    if (-not $chkRestart.Checked) { $a += ' -NoRestartExplorer' }
    if ($chkSys.Checked) {
        $a += ' -Icons Yes'
        if (-not $chkFolder.Checked) { $a += ' -NoFolderIcons' }
        if (-not $chkUser.Checked)   { $a += ' -NoUserFolderIcons' }
    } else {
        $a += ' -Icons No'
    }
    Start-Engine $a "Applying $theme theme, taskbar at $($pos.ToLower())..."
})

$btnRestore.Add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Put back your original settings, icons and taskbar?`nExplorer will restart.",
        'Modern 10', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    Start-Engine '-Restore' 'Restoring original settings...'
})

$btnLog.Add_Click({
    if (Test-Path -LiteralPath $script:LogFile) { Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:LogFile) }
    else { [System.Windows.Forms.MessageBox]::Show('No log yet - run Apply first.', 'Modern 10', 'OK', 'Information') | Out-Null }
})

$form.Add_FormClosing({
    param($s, $e)
    if ($script:Proc -and -not $script:Proc.HasExited) {
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
Update-Preview (Get-SegValue $segTheme)
[void]$form.ShowDialog()
