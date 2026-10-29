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
$script:CustomPath = ''

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

# ---------------------------------------------------------------- layout helpers
function New-Pt([int]$X, [int]$Y) { return New-Object System.Drawing.Point($X, $Y) }
function New-Sz([int]$W, [int]$H) { return New-Object System.Drawing.Size($W, $H) }
function New-Pad([int]$L, [int]$T, [int]$R, [int]$B) { return New-Object System.Windows.Forms.Padding($L, $T, $R, $B) }

$script:FontBody  = New-Object System.Drawing.Font('Segoe UI', 9)
$script:FontBold  = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$fontTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 20)
$fontHead  = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
$fontSmall = New-Object System.Drawing.Font('Segoe UI Semibold', 8)
$fontDev   = New-Object System.Drawing.Font('Segoe UI Semibold', 11)

$script:Pages = @()
$script:NavButtons = @()

# every text label sizes itself to its text and wraps at a fixed width, so nothing can be cropped
function New-Lbl($Parent, [string]$Text, $Font, [string]$Role = 'text', [int]$Wrap = 0, $Margin = $null) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Font = $Font; $l.AutoSize = $true
    if ($Wrap -gt 0) { $l.MaximumSize = New-Sz $Wrap 0 }
    if ($Margin) { $l.Margin = $Margin }
    if ($Role -eq 'sub') { $script:UiSubs += $l } elseif ($Role -eq 'accent') { $script:UiAccent += $l } else { $script:UiLabels += $l }
    $Parent.Controls.Add($l)
    return $l
}

function New-Page {
    $f = New-Object System.Windows.Forms.FlowLayoutPanel
    $f.Dock = 'Fill'; $f.FlowDirection = 'TopDown'; $f.WrapContents = $false; $f.AutoScroll = $true
    $f.Padding = New-Pad 28 22 20 16
    $f.Visible = $false
    $script:PagesHost.Controls.Add($f)
    $script:Pages += $f
    return $f
}

function Add-Heading($Page, [string]$Title, [string]$Desc) {
    [void](New-Lbl $Page $Title $fontHead 'text' 0 (New-Pad 0 0 0 4))
    [void](New-Lbl $Page $Desc $script:FontBody 'sub' 560 (New-Pad 0 0 0 18))
}

function Add-Caption($Page, [string]$Text) {
    [void](New-Lbl $Page $Text $fontSmall 'sub' 0 (New-Pad 0 6 0 5))
}

function Add-Note($Page, [string]$Text) {
    [void](New-Lbl $Page $Text $script:FontBody 'sub' 560 (New-Pad 0 8 0 0))
}

# a row of radio buttons; the panel holds the choice (Tag of the checked button)
function Add-Radios($Page, $Items, [int]$Index) {
    $f = New-Object System.Windows.Forms.FlowLayoutPanel
    $f.FlowDirection = 'LeftToRight'; $f.WrapContents = $false; $f.AutoSize = $true
    $f.AutoSizeMode = 'GrowAndShrink'; $f.Margin = New-Pad 0 0 0 10; $f.Padding = New-Pad 0 0 0 0
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Text = $Items[$i][0]; $rb.Tag = $Items[$i][1]; $rb.AutoSize = $true
        $rb.Margin = New-Pad 0 0 26 0; $rb.Cursor = 'Hand'
        $rb.Checked = ($i -eq $Index)
        $f.Controls.Add($rb)
    }
    $Page.Controls.Add($f)
    return $f
}

function Add-Check($Page, [string]$Text, [bool]$On = $true, [int]$Indent = 0) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text; $c.AutoSize = $true; $c.Checked = $On; $c.Cursor = 'Hand'
    $c.Margin = New-Pad $Indent 4 0 6
    $Page.Controls.Add($c)
    return $c
}

function Add-Combo($Page, $Items, [int]$W = 300) {
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'; $c.FlatStyle = 'Flat'; $c.Cursor = 'Hand'
    $c.Width = $W; $c.Margin = New-Pad 0 0 0 10
    foreach ($i in $Items) { [void]$c.Items.Add($i) }
    $c.SelectedIndex = 0
    $script:UiCombos += $c
    $Page.Controls.Add($c)
    return $c
}

function New-Btn($Parent, [string]$Text, [int]$W, [int]$H, [bool]$Primary) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Size = New-Sz $W $H; $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'; $b.Font = $script:FontBold
    $b.Margin = New-Pad 0 0 10 0
    if ($Primary) { $b.FlatAppearance.BorderSize = 0 } else { $b.FlatAppearance.BorderSize = 1; $script:UiSecBtns += $b }
    $Parent.Controls.Add($b)
    return $b
}

function Get-SegValue($Panel) {
    $sel = $Panel.Controls | Where-Object { $_.Checked } | Select-Object -First 1
    if ($sel) { return [string]$sel.Tag }
    return ''
}

function Set-SegValue($Panel, [string]$Value) {
    foreach ($rb in $Panel.Controls) { if ([string]$rb.Tag -eq $Value) { $rb.Checked = $true } }
}

# ---------------------------------------------------------------- window shell
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Modern 10'
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode = 'Dpi'
$form.ClientSize = New-Sz 900 740
$form.MinimumSize = New-Sz 840 600
$form.StartPosition = 'CenterScreen'
$form.Font = $script:FontBody
try {
    $icoPath = Join-Path $script:Root 'assets\Modern10.ico'
    if (Test-Path -LiteralPath $icoPath) { $form.Icon = New-Object System.Drawing.Icon($icoPath) }
} catch { }

$script:UiLabels = @(); $script:UiSubs = @(); $script:UiAccent = @(); $script:UiSecBtns = @(); $script:UiCombos = @()

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'; $header.Height = 84; $header.Padding = New-Pad 18 10 18 4
$bottom = New-Object System.Windows.Forms.Panel
$bottom.Dock = 'Bottom'; $bottom.Height = 220; $bottom.Padding = New-Pad 18 0 18 10
$body = New-Object System.Windows.Forms.Panel
$body.Dock = 'Fill'
# the fill panel goes in first, the docked edges after it
$form.Controls.Add($body)
$form.Controls.Add($bottom)
$form.Controls.Add($header)

# ---- header: icon, title, developer credit
$titlePanel = New-Object System.Windows.Forms.Panel
$titlePanel.Dock = 'Fill'
$lblTitle = New-Lbl $titlePanel 'Modern 10' $fontTitle 'text'
$lblTitle.Location = New-Pt 6 2
$lblSub = New-Lbl $titlePanel 'A glassy, macOS-inspired look for Windows 10' $script:FontBody 'sub'
$lblSub.Location = New-Pt 10 46

$devFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$devFlow.Dock = 'Right'; $devFlow.FlowDirection = 'TopDown'; $devFlow.WrapContents = $false
$devFlow.AutoSize = $true; $devFlow.AutoSizeMode = 'GrowAndShrink'; $devFlow.Padding = New-Pad 0 2 0 0
[void](New-Lbl $devFlow 'DEVELOPED BY' $fontSmall 'sub' 0 (New-Pad 0 0 0 0))
$lblDev = New-Lbl $devFlow $script:M10Developer $fontDev 'accent' 0 (New-Pad 0 0 0 0)
[void](New-Lbl $devFlow 'tasmon@outlook.com' $script:FontBody 'sub' 0 (New-Pad 0 0 0 0))
[void](New-Lbl $devFlow ('Version ' + $script:M10Version) $script:FontBody 'sub' 0 (New-Pad 0 0 0 0))

$logo = New-Object System.Windows.Forms.PictureBox
$logo.Dock = 'Left'; $logo.Width = 66; $logo.SizeMode = 'Zoom'
try {
    $logoPath = Join-Path $script:Root 'assets\Modern10.png'
    if (Test-Path -LiteralPath $logoPath) {
        $lbytes = [System.IO.File]::ReadAllBytes($logoPath)
        $lms = New-Object System.IO.MemoryStream(, $lbytes)
        $logo.Image = [System.Drawing.Image]::FromStream($lms)
    }
} catch { }
$header.Controls.Add($titlePanel)
$header.Controls.Add($devFlow)
$header.Controls.Add($logo)

# ---- body: menu on the left, one page at a time on the right
$script:PagesHost = New-Object System.Windows.Forms.Panel
$script:PagesHost.Dock = 'Fill'
$nav = New-Object System.Windows.Forms.Panel
$nav.Dock = 'Left'; $nav.Width = 230; $nav.Padding = New-Pad 10 14 10 10
$body.Controls.Add($script:PagesHost)
$body.Controls.Add($nav)

# start with the theme that matches the current Windows mode
$startTheme = 0
try {
    $cur = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop).AppsUseLightTheme
    if ($cur -eq 1) { $startTheme = 1 }
} catch { }

# ---- page 1: look
$pLook = New-Page
Add-Heading $pLook '1. Look' 'Pick dark or light. This sets the colours of Windows apps and the taskbar, and the wallpaper, lock screen and icons you create here follow it.'
Add-Caption $pLook 'COLOUR MODE'
$segTheme = Add-Radios $pLook @(@('Dark', 'Dark'), @('Light', 'Light')) $startTheme
$chkRestart = Add-Check $pLook 'Restart Explorer when applying (recommended, so changes show straight away)' $true
Add-Note $pLook 'Nothing is changed until you press Apply. You can always go back with Restore original.'

# ---- page 2: wallpaper and lock screen
$pWall = New-Page
Add-Heading $pWall '2. Wallpaper and lock screen' 'Choose one of the built-in designs or use your own picture. Everything is drawn on your PC at your screen size.'
$chkWall = Add-Check $pWall 'Change my wallpaper' $true
$wallItems = @(Get-M10WallpaperStyleNames) + @('Custom image...')
$cmbWall = Add-Combo $pWall $wallItems 320
$btnBrowse = New-Btn $pWall 'Choose my own picture...' 220 32 $false
$btnBrowse.Margin = New-Pad 0 0 0 10
$pbWall = New-Object System.Windows.Forms.PictureBox
$pbWall.Size = New-Sz 320 180; $pbWall.SizeMode = 'Zoom'; $pbWall.BorderStyle = 'FixedSingle'
$pbWall.Margin = New-Pad 0 0 0 14
$pWall.Controls.Add($pbWall)
$chkLock = Add-Check $pWall 'Change my lock screen' $true
$cmbLock = Add-Combo $pWall (@('Same as wallpaper') + @(Get-M10WallpaperStyleNames)) 320

# ---- page 3: icons
$pIcons = New-Page
Add-Heading $pIcons '3. Icons' 'Replace the folder, drive and system icons in File Explorer with a matching set.'
$chkSys = Add-Check $pIcons 'Change system, drive and folder icons' $true
$cmbIcon = Add-Combo $pIcons @(Get-M10IconThemeNames) 320
$prevFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$prevFlow.FlowDirection = 'LeftToRight'; $prevFlow.WrapContents = $true; $prevFlow.Size = New-Sz 400 132
$prevFlow.Margin = New-Pad 0 0 0 12
$previewKinds = @('Folder', 'Documents', 'Downloads', 'Objects3D', 'Archive', 'ThisPC', 'Drive', 'RecycleFull', 'User', 'QuickAccess', 'Libraries', 'OneDrive')
$script:Previews = @()
foreach ($k in $previewKinds) {
    $pb = New-Object System.Windows.Forms.PictureBox
    $pb.Size = New-Sz 52 52; $pb.SizeMode = 'Zoom'; $pb.Margin = New-Pad 2 2 8 8; $pb.Tag = $k
    $prevFlow.Controls.Add($pb)
    $script:Previews += $pb
}
$pIcons.Controls.Add($prevFlow)
$chkFolder  = Add-Check $pIcons 'Documents, Downloads, Pictures and the other This PC folders' $true 16
$chkProfile = Add-Check $pIcons 'The same folders inside my user folder' $true 16
$chkGeneric = Add-Check $pIcons 'Every other folder, for all users (asks for administrator permission)' $true 16

# ---- page 4: taskbar
$pTask = New-Page
Add-Heading $pTask '4. Taskbar' 'Move the taskbar, change its icon size and choose whether it hides.'
Add-Caption $pTask 'POSITION ON SCREEN'
$segPos = Add-Radios $pTask @(@('Top', 'Top'), @('Bottom', 'Bottom')) 0
Add-Caption $pTask 'ICON SIZE'
$segSize = Add-Radios $pTask @(@('Small', 'Small'), @('Default', 'Default'), @('Keep what I have', 'Keep')) 0
Add-Caption $pTask 'HIDING'
$segBeh = Add-Radios $pTask @(@('Keep what I have', 'Keep'), @('Always show', 'Show'), @('Hide until I point at it', 'AutoHide')) 0
$btnDock = New-Btn $pTask 'Dock options...' 180 34 $false
$btnDock.Margin = New-Pad 0 14 0 0
Add-Note $pTask 'Dock options offers a one-click dock-style preset and two optional apps, KiraDock and TaskbarX.'

# ---- menu buttons (added in reverse so the first one ends up on top)
$navNames = @('1. Look', '2. Wallpaper & lock screen', '3. Icons', '4. Taskbar')
for ($i = $navNames.Count - 1; $i -ge 0; $i--) {
    $nb = New-Object System.Windows.Forms.Button
    $nb.Text = $navNames[$i]; $nb.Tag = $i; $nb.Dock = 'Top'; $nb.Height = 46
    $nb.FlatStyle = 'Flat'; $nb.FlatAppearance.BorderSize = 0; $nb.Cursor = 'Hand'
    $nb.TextAlign = 'MiddleLeft'; $nb.Padding = New-Pad 10 0 4 0; $nb.Font = $script:FontBody
    $nb.Add_Click({ Show-Page ([int]$this.Tag) })
    $nav.Controls.Add($nb)
    $script:NavButtons = @($nb) + $script:NavButtons
}

function Update-Nav {
    if (-not $script:Pal) { return }
    foreach ($nb in $script:NavButtons) {
        if ([int]$nb.Tag -eq $script:CurrentPage) {
            $nb.BackColor = $script:Pal.Accent; $nb.ForeColor = [System.Drawing.Color]::White; $nb.Font = $script:FontBold
        } else {
            $nb.BackColor = $script:Pal.Panel; $nb.ForeColor = $script:Pal.Text; $nb.Font = $script:FontBody
        }
    }
}

function Show-Page([int]$Index) {
    $script:CurrentPage = $Index
    for ($i = 0; $i -lt $script:Pages.Count; $i++) { $script:Pages[$i].Visible = ($i -eq $Index) }
    Update-Nav
}
$script:CurrentPage = 0
$script:Pages[0].Visible = $true

# ---- bottom: actions, progress, log
$log = New-Object System.Windows.Forms.RichTextBox
$log.Dock = 'Fill'; $log.ReadOnly = $true; $log.BorderStyle = 'FixedSingle'
$log.Font = New-Object System.Drawing.Font('Consolas', 9); $log.DetectUrls = $false
$lblFoot = New-Object System.Windows.Forms.Label
$lblFoot.Dock = 'Bottom'; $lblFoot.Height = 26; $lblFoot.TextAlign = 'MiddleLeft'
$lblFoot.Text = 'Modern 10 - nothing runs in the background, every change is backed up'
$script:UiSubs += $lblFoot
$actions = New-Object System.Windows.Forms.FlowLayoutPanel
$actions.Dock = 'Top'; $actions.Height = 66; $actions.FlowDirection = 'LeftToRight'; $actions.WrapContents = $false
$actions.Padding = New-Pad 0 10 0 8
$btnApply   = New-Btn $actions 'Apply' 170 44 $true
$btnRestore = New-Btn $actions 'Restore original' 160 44 $false
$btnLog     = New-Btn $actions 'Open log' 120 44 $false
$lblStatus  = New-Lbl $actions 'Ready' $script:FontBody 'sub' 0 (New-Pad 8 14 0 0)
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Dock = 'Top'; $progress.Height = 5; $progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 30; $progress.Visible = $false
$bottom.Controls.Add($log)
$bottom.Controls.Add($lblFoot)
$bottom.Controls.Add($actions)
$bottom.Controls.Add($progress)

# ---------------------------------------------------------------- behaviour of the controls
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
    $dlg.Title = 'Choose a wallpaper picture'
    $dlg.Filter = 'Pictures (*.jpg;*.jpeg;*.png;*.bmp)|*.jpg;*.jpeg;*.png;*.bmp'
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:CustomPath = $dlg.FileName
        $cmbWall.SelectedIndex = $cmbWall.Items.Count - 1
        Update-WallPreview
    }
    $dlg.Dispose()
})

# ---------------------------------------------------------------- theming
function Get-GuiPaletteCompat([string]$Theme) { return (Get-GuiPalette $Theme) }

function Apply-GuiTheme([string]$Theme) {
    $script:Pal = Get-GuiPalette $Theme
    $p = $script:Pal
    $form.BackColor = $p.Back
    $form.ForeColor = $p.Text
    $nav.BackColor = $p.Panel
    foreach ($l in $script:UiLabels) { $l.ForeColor = $p.Text }
    foreach ($l in $script:UiSubs)   { $l.ForeColor = $p.Sub }
    foreach ($l in $script:UiAccent) { $l.ForeColor = $p.Accent }
    foreach ($b in $script:UiSecBtns) {
        $b.BackColor = $p.Panel; $b.ForeColor = $p.Text; $b.FlatAppearance.BorderColor = $p.Border
    }
    foreach ($c in $script:UiCombos) { $c.BackColor = $p.Panel; $c.ForeColor = $p.Text }
    $pbWall.BackColor = $p.Panel
    $btnApply.BackColor = $p.Accent
    $btnApply.ForeColor = [System.Drawing.Color]::White
    $log.BackColor = $p.LogBack
    $log.ForeColor = $p.Text
    Update-Nav
    if ($form.IsHandleCreated) {
        $v = 0; if ($Theme -eq 'Dark') { $v = 1 }
        [void][M10Gui]::DwmSetWindowAttribute($form.Handle, 20, [ref]$v, 4)
        [void][M10Gui]::DwmSetWindowAttribute($form.Handle, 19, [ref]$v, 4)
    }
}

foreach ($rb in $segTheme.Controls) {
    $rb.Add_CheckedChanged({
        if ($this.Checked) {
            Apply-GuiTheme (Get-SegValue $segTheme)
            Update-Preview
            Update-WallPreview
        }
    })
}

function Set-Busy([bool]$Busy) {
    $btnApply.Enabled = -not $Busy
    $btnRestore.Enabled = -not $Busy
    $nav.Enabled = -not $Busy
    $script:PagesHost.Enabled = -not $Busy
    $progress.Visible = $Busy
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
    $dlg.ClientSize = New-Sz 660 560
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor = $p.Back; $dlg.ForeColor = $p.Text; $dlg.Font = $script:FontBody
    try { $dlg.Icon = $form.Icon } catch { }
    $dlg.ShowInTaskbar = $false

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Fill'; $flow.FlowDirection = 'TopDown'; $flow.WrapContents = $false; $flow.AutoScroll = $true
    $flow.Padding = New-Pad 24 18 18 12
    $dlg.Controls.Add($flow)

    $t = New-Object System.Windows.Forms.Label
    $t.Text = 'Dock-style taskbar'; $t.Font = $fontHead; $t.AutoSize = $true; $t.Margin = New-Pad 0 0 0 6
    $flow.Controls.Add($t)

    $d = New-Object System.Windows.Forms.Label
    $d.Text = 'No extra software needed: this preset puts the taskbar at the bottom with standard icons and hides it until you move the mouse to the screen edge. It only fills in the choices on the main window - press Apply there to use it.'
    $d.AutoSize = $true; $d.MaximumSize = New-Sz 600 0; $d.ForeColor = $p.Sub; $d.Margin = New-Pad 0 0 0 12
    $flow.Controls.Add($d)

    $bp = New-Object System.Windows.Forms.Button
    $bp.Text = 'Use the dock-style preset'; $bp.FlatStyle = 'Flat'; $bp.Font = $script:FontBold; $bp.Cursor = 'Hand'
    $bp.Size = New-Sz 240 38; $bp.Margin = New-Pad 0 0 0 20
    $bp.BackColor = $p.Accent; $bp.ForeColor = [System.Drawing.Color]::White; $bp.FlatAppearance.BorderSize = 0
    $bp.Add_Click({
        Set-SegValue $segPos 'Bottom'; Set-SegValue $segSize 'Default'; Set-SegValue $segBeh 'AutoHide'
        $this.FindForm().Close()
    })
    $flow.Controls.Add($bp)

    $h = New-Object System.Windows.Forms.Label
    $h.Text = 'OPTIONAL ADD-ONS - nothing is installed unless you tick it and press Install'
    $h.Font = $fontSmall; $h.ForeColor = $p.Sub; $h.AutoSize = $true; $h.Margin = New-Pad 0 0 0 8
    $flow.Controls.Add($h)

    $items = @(
        @{ Name = 'KiraDock'; Id = '9NPD1H35D0WD'; Source = 'msstore'
           Url = 'https://apps.microsoft.com/detail/9NPD1H35D0WD'
           Info = 'Purpose: a macOS-style dock for Windows - a floating, animated launcher bar for your favourite apps at the edge of the screen. Free app from the Microsoft Store.' },
        @{ Name = 'TaskbarX'; Id = 'ChrisAndriessen.TaskbarX'; Source = 'winget'
           Url = 'https://github.com/ChrisAnd1998/TaskbarX/releases'
           Info = 'Purpose: centres the taskbar icons and animates them, for a floating-dock look on the normal taskbar. A small open-source app from GitHub that keeps running in the background.' }
    )
    $checks = @()
    foreach ($it in $items) {
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text = $it.Name; $c.Font = $script:FontBold; $c.AutoSize = $true; $c.Cursor = 'Hand'
        $c.Tag = $it; $c.Margin = New-Pad 0 4 0 2
        $flow.Controls.Add($c)
        $checks += $c
        $s = New-Object System.Windows.Forms.Label
        $s.Text = $it.Info; $s.ForeColor = $p.Sub; $s.AutoSize = $true; $s.MaximumSize = New-Sz 580 0
        $s.Margin = New-Pad 22 0 0 2
        $flow.Controls.Add($s)
        $lk = New-Object System.Windows.Forms.LinkLabel
        $lk.Text = $it.Url; $lk.AutoSize = $true; $lk.Margin = New-Pad 22 0 0 14
        $lk.LinkColor = $p.Accent; $lk.ActiveLinkColor = $p.Accent
        $lk.Tag = $it.Url
        $lk.Add_LinkClicked({ param($s2, $e2) Start-Process ([string]$s2.Tag) })
        $flow.Controls.Add($lk)
    }

    $row = New-Object System.Windows.Forms.FlowLayoutPanel
    $row.FlowDirection = 'LeftToRight'; $row.WrapContents = $false; $row.AutoSize = $true; $row.Margin = New-Pad 0 6 0 0
    $bi = New-Object System.Windows.Forms.Button
    $bi.Text = 'Install selected'; $bi.FlatStyle = 'Flat'; $bi.Font = $script:FontBold; $bi.Cursor = 'Hand'
    $bi.Size = New-Sz 170 38; $bi.Margin = New-Pad 0 0 14 0
    $bi.BackColor = $p.Panel; $bi.ForeColor = $p.Text; $bi.FlatAppearance.BorderColor = $p.Border
    $bi.Tag = $checks
    $bi.Add_Click({
        $sel = @()
        foreach ($ctl in $this.Tag) { if ($ctl.Checked) { $sel += $ctl.Tag } }
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
    $row.Controls.Add($bi)
    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'Optional. Modern 10 works without them.'
    $note.ForeColor = $p.Sub; $note.AutoSize = $true; $note.Margin = New-Pad 0 11 0 0
    $row.Controls.Add($note)
    $flow.Controls.Add($row)

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
    try {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        if ($form.Height -gt $wa.Height) { $form.Height = $wa.Height; $form.Top = $wa.Top }
        if ($form.Width -gt $wa.Width) { $form.Width = $wa.Width; $form.Left = $wa.Left }
    } catch { }
    Apply-GuiTheme (Get-SegValue $segTheme)
    Add-LogLine '> Pick your options and press Apply. Everything can be undone with "Restore original".' $script:Pal.Sub
})

# initial paint
Apply-GuiTheme (Get-SegValue $segTheme)
Update-Preview
Update-WallPreview
[void]$form.ShowDialog()

} catch {
    $msg = "Modern 10 could not start:`n`n" + $_.Exception.Message + "`n`n" + $_.ScriptStackTrace
    try { Set-Content -LiteralPath (Join-Path $env:TEMP 'Modern10-startup.log') -Value ((Get-Date -Format s) + "`r`n" + $msg + "`r`n" + ($_ | Out-String)) } catch { }
    Show-M10Error $msg
    exit 1
}
