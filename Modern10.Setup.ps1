#Requires -Version 5.1
<#
.SYNOPSIS
    Modern 10 - setup wizard (per-user install, no administrator rights needed).

.DESCRIPTION
    Copies Modern 10 to %LOCALAPPDATA%\Programs\Modern10 (or a folder you choose), adds Start menu and
    optional Desktop shortcuts with the Modern 10 icon, and registers the app in Settings > Apps so it can be
    uninstalled like any other program. Started by Setup.cmd.
#>
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $PSCommandPath
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if (-not ('M10Setup' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class M10Setup
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
[void][M10Setup]::SetProcessDPIAware()
try { [void][M10Setup]::SetCurrentProcessExplicitAppUserModelID('TasmonIslam.Modern10.Setup') } catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Src = $PSScriptRoot
$script:UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Modern10'
$script:AppFiles = @('Modern10.GUI.ps1', 'Modern10.Engine.ps1', 'Modern10.Icons.ps1', 'Modern10.Elevated.ps1',
                     'Modern10.Uninstall.ps1', 'Modern10.cmd', 'LICENSE', 'README.md')
$script:AppAssets = @('assets\Modern10.ico', 'assets\Modern10.png')
$script:PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Get-SetupVersion {
    try {
        $t = [System.IO.File]::ReadAllText((Join-Path $script:Src 'Modern10.Engine.ps1'))
        $m = [regex]::Match($t, "M10Version\s*=\s*'([^']+)'")
        if ($m.Success) { return $m.Groups[1].Value }
    } catch { }
    return '2.1'
}
$script:Version = Get-SetupVersion

function Get-InstalledLocation {
    try { return [string](Get-ItemProperty -LiteralPath $script:UninstallKey -ErrorAction Stop).InstallLocation } catch { return '' }
}

function Test-SourceComplete {
    foreach ($f in ($script:AppFiles + $script:AppAssets)) {
        if (-not (Test-Path -LiteralPath (Join-Path $script:Src $f))) { return $f }
    }
    return ''
}

function New-M10Shortcut([string]$LnkPath, [string]$Dest) {
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($LnkPath)
    $lnk.TargetPath = $script:PsExe
    $lnk.Arguments = '-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $Dest 'Modern10.GUI.ps1') + '"'
    $lnk.WorkingDirectory = $Dest
    $lnk.IconLocation = (Join-Path $Dest 'assets\Modern10.ico') + ',0'
    $lnk.WindowStyle = 7
    $lnk.Description = 'Modern 10 - a macOS-inspired look for Windows 10'
    $lnk.Save()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws)
}

function Install-M10([string]$Dest, [bool]$StartMenu, [bool]$Desktop) {
    $missing = Test-SourceComplete
    if ($missing) { throw "Setup is incomplete - '$missing' is missing. Extract the whole ZIP first." }

    $sameFolder = ($Dest.TrimEnd('\') -ieq $script:Src.TrimEnd('\'))
    if (-not $sameFolder) {
        New-Item -ItemType Directory -Path (Join-Path $Dest 'assets') -Force | Out-Null
        foreach ($f in ($script:AppFiles + $script:AppAssets)) {
            Copy-Item -LiteralPath (Join-Path $script:Src $f) -Destination (Join-Path $Dest $f) -Force
        }
    }

    $startLnk = Join-Path ([Environment]::GetFolderPath('Programs')) 'Modern 10.lnk'
    $deskLnk  = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Modern 10.lnk'
    if ($StartMenu) { New-M10Shortcut $startLnk $Dest } elseif (Test-Path -LiteralPath $startLnk) { Remove-Item -LiteralPath $startLnk -Force }
    if ($Desktop)   { New-M10Shortcut $deskLnk $Dest }  elseif (Test-Path -LiteralPath $deskLnk)  { Remove-Item -LiteralPath $deskLnk -Force }

    $sizeKb = 0
    try { $sizeKb = [int]((Get-ChildItem -LiteralPath $Dest -Recurse -File | Measure-Object Length -Sum).Sum / 1KB) } catch { }
    $unCmd = '"' + $script:PsExe + '" -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $Dest 'Modern10.Uninstall.ps1') + '"'
    $k = New-Item -Path $script:UninstallKey -Force
    $vals = @{
        DisplayName = 'Modern 10'; DisplayVersion = $script:Version; Publisher = 'Tasmon Islam'
        DisplayIcon = (Join-Path $Dest 'assets\Modern10.ico'); InstallLocation = $Dest
        UninstallString = $unCmd; InstallDate = (Get-Date -Format 'yyyyMMdd')
    }
    foreach ($n in $vals.Keys) { New-ItemProperty -LiteralPath $script:UninstallKey -Name $n -Value $vals[$n] -PropertyType String -Force | Out-Null }
    New-ItemProperty -LiteralPath $script:UninstallKey -Name 'NoModify' -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -LiteralPath $script:UninstallKey -Name 'NoRepair' -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -LiteralPath $script:UninstallKey -Name 'EstimatedSize' -Value $sizeKb -PropertyType DWord -Force | Out-Null
}

# ---------------------------------------------------------------- window
$light = $false
try { $light = ((Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop).AppsUseLightTheme -eq 1) } catch { }
if ($light) {
    $cBack = [System.Drawing.ColorTranslator]::FromHtml('#F5F5F7'); $cPanel = [System.Drawing.ColorTranslator]::FromHtml('#FFFFFF')
    $cText = [System.Drawing.ColorTranslator]::FromHtml('#1D1D1F'); $cSub = [System.Drawing.ColorTranslator]::FromHtml('#6E6E73')
    $cBorder = [System.Drawing.ColorTranslator]::FromHtml('#D2D2D7'); $cAccent = [System.Drawing.ColorTranslator]::FromHtml('#007AFF')
} else {
    $cBack = [System.Drawing.ColorTranslator]::FromHtml('#1C1C1E'); $cPanel = [System.Drawing.ColorTranslator]::FromHtml('#2C2C2E')
    $cText = [System.Drawing.ColorTranslator]::FromHtml('#F2F2F7'); $cSub = [System.Drawing.ColorTranslator]::FromHtml('#98989D')
    $cBorder = [System.Drawing.ColorTranslator]::FromHtml('#3A3A3C'); $cAccent = [System.Drawing.ColorTranslator]::FromHtml('#0A84FF')
}
$fBody = New-Object System.Drawing.Font('Segoe UI', 9)
$fBold = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$fTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
$fSmall = New-Object System.Drawing.Font('Segoe UI Semibold', 8)

function Add-Ctl($Ctl, [int]$X, [int]$Y, [int]$W, [int]$H) {
    $Ctl.Location = New-Object System.Drawing.Point($X, $Y); $Ctl.Size = New-Object System.Drawing.Size($W, $H)
    $form.Controls.Add($Ctl); return $Ctl
}
function New-Lbl([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, $Font, $Color) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Font = $Font; $l.ForeColor = $Color; $l.BackColor = [System.Drawing.Color]::Transparent
    return (Add-Ctl $l $X $Y $W $H)
}
function New-Btn([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, [bool]$Primary) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.FlatStyle = 'Flat'; $b.Font = $fBold; $b.Cursor = 'Hand'
    if ($Primary) { $b.BackColor = $cAccent; $b.ForeColor = [System.Drawing.Color]::White; $b.FlatAppearance.BorderSize = 0 }
    else { $b.BackColor = $cPanel; $b.ForeColor = $cText; $b.FlatAppearance.BorderColor = $cBorder; $b.FlatAppearance.BorderSize = 1 }
    return (Add-Ctl $b $X $Y $W $H)
}
function New-Chk([string]$Text, [int]$X, [int]$Y, [bool]$On) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text; $c.Font = $fBody; $c.ForeColor = $cText; $c.BackColor = $cBack; $c.Checked = $On; $c.AutoSize = $true; $c.Cursor = 'Hand'
    $c.Location = New-Object System.Drawing.Point($X, $Y); $form.Controls.Add($c); return $c
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Modern 10 Setup'
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode = 'Dpi'
$form.ClientSize = New-Object System.Drawing.Size(540, 430)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false; $form.MinimizeBox = $true
$form.BackColor = $cBack; $form.ForeColor = $cText; $form.Font = $fBody
try {
    $ico = Join-Path $script:Src 'assets\Modern10.ico'
    if (Test-Path -LiteralPath $ico) { $form.Icon = New-Object System.Drawing.Icon($ico) }
} catch { }

$logo = New-Object System.Windows.Forms.PictureBox
$logo.SizeMode = 'Zoom'; $logo.BackColor = [System.Drawing.Color]::Transparent
try {
    $png = Join-Path $script:Src 'assets\Modern10.png'
    if (Test-Path -LiteralPath $png) {
        $ms = New-Object System.IO.MemoryStream(, [System.IO.File]::ReadAllBytes($png))
        $logo.Image = [System.Drawing.Image]::FromStream($ms)
    }
} catch { }
[void](Add-Ctl $logo 28 24 72 72)
$existing = Get-InstalledLocation
$isUpdate = [bool]$existing
$titleText = 'Install Modern 10'; if ($isUpdate) { $titleText = 'Update Modern 10' }
[void](New-Lbl $titleText 116 26 400 36 $fTitle $cText)
[void](New-Lbl ('Version ' + $script:Version + '  -  by Tasmon Islam') 118 64 400 20 $fBody $cSub)
[void](New-Lbl 'A glassy, macOS-inspired look for Windows 10.' 118 84 400 20 $fBody $cSub)

[void](New-Lbl 'INSTALL LOCATION' 28 124 300 16 $fSmall $cSub)
$defaultDest = Join-Path $env:LOCALAPPDATA 'Programs\Modern10'
if ($existing) { $defaultDest = $existing }
$txtDest = New-Object System.Windows.Forms.TextBox
$txtDest.Font = $fBody; $txtDest.BackColor = $cPanel; $txtDest.ForeColor = $cText; $txtDest.BorderStyle = 'FixedSingle'
$txtDest.Text = $defaultDest
[void](Add-Ctl $txtDest 28 144 372 26)
$btnBrowse = New-Btn 'Browse...' 410 142 100 28 $false

[void](New-Lbl 'OPTIONS' 28 190 300 16 $fSmall $cSub)
$chkStart  = New-Chk 'Add Modern 10 to the Start menu' 28 212 $true
$chkDesk   = New-Chk 'Create a Desktop shortcut' 28 238 $true
$chkLaunch = New-Chk 'Open Modern 10 when setup finishes' 28 264 $true

$note = New-Lbl ("Installs for your account only - no administrator rights needed. Modern 10 appears in Settings > Apps, where you can uninstall it. " +
                 "Your Windows settings are not changed until you press Apply inside Modern 10.") 28 298 484 48 $fBody $cSub

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Style = 'Marquee'; $progress.MarqueeAnimationSpeed = 30; $progress.Visible = $false
[void](Add-Ctl $progress 28 356 484 6)
$lblStatus = New-Lbl '' 28 366 484 20 $fBody $cSub

$goText = 'Install'; if ($isUpdate) { $goText = 'Update' }
$btnGo = New-Btn $goText 292 386 120 34 $true
$btnCancel = New-Btn 'Cancel' 422 386 90 34 $false
$script:Done = $false
$script:FinalDest = ''

$btnBrowse.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Choose where to install Modern 10 (a Modern10 folder is created inside it)'
    if ($d.ShowDialog() -eq 'OK') { $txtDest.Text = (Join-Path $d.SelectedPath 'Modern10') }
    $d.Dispose()
})
$btnCancel.Add_Click({ $form.Close() })

$btnGo.Add_Click({
    if ($script:Done) {
        if ($chkLaunch.Checked) {
            try { Start-Process -FilePath $script:PsExe -ArgumentList @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + (Join-Path $script:FinalDest 'Modern10.GUI.ps1') + '"')) -WorkingDirectory $script:FinalDest } catch { }
        }
        $form.Close(); return
    }
    $dest = $txtDest.Text.Trim().Trim('"')
    if (-not $dest -or -not [System.IO.Path]::IsPathRooted($dest)) {
        [System.Windows.Forms.MessageBox]::Show('Please enter a full folder path, for example C:\Users\you\AppData\Local\Programs\Modern10.', 'Modern 10 Setup', 'OK', 'Warning') | Out-Null
        return
    }
    $dest = [System.IO.Path]::GetFullPath($dest).TrimEnd('\')
    if ([System.IO.Path]::GetPathRoot($dest).TrimEnd('\') -ieq $dest) {
        [System.Windows.Forms.MessageBox]::Show('Please choose a folder, not the root of a drive.', 'Modern 10 Setup', 'OK', 'Warning') | Out-Null
        return
    }
    # always keep Modern 10 in its own folder, so uninstalling can never touch other files
    if ((Split-Path $dest -Leaf) -ine 'Modern10') { $dest = Join-Path $dest 'Modern10' }
    $txtDest.Text = $dest

    foreach ($c in @($btnGo, $btnCancel, $btnBrowse, $txtDest, $chkStart, $chkDesk, $chkLaunch)) { $c.Enabled = $false }
    $progress.Visible = $true
    $lblStatus.Text = 'Installing...'
    $form.Refresh()
    try {
        Install-M10 $dest $chkStart.Checked $chkDesk.Checked
        $script:Done = $true
        $script:FinalDest = $dest
        $progress.Visible = $false
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(50, 170, 75)
        $lblStatus.Text = 'Done. Modern 10 is installed.'
        $btnGo.Text = 'Finish'; $btnGo.Enabled = $true
        $btnCancel.Visible = $false
    } catch {
        $progress.Visible = $false
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(220, 60, 50)
        $lblStatus.Text = 'Setup failed.'
        [System.Windows.Forms.MessageBox]::Show(('Setup could not finish:' + "`n`n" + $_.Exception.Message), 'Modern 10 Setup', 'OK', 'Error') | Out-Null
        foreach ($c in @($btnGo, $btnCancel, $btnBrowse, $txtDest, $chkStart, $chkDesk, $chkLaunch)) { $c.Enabled = $true }
    }
})

$form.Add_Shown({
    $v = 0; if (-not $light) { $v = 1 }
    [void][M10Setup]::DwmSetWindowAttribute($form.Handle, 20, [ref]$v, 4)
    [void][M10Setup]::DwmSetWindowAttribute($form.Handle, 19, [ref]$v, 4)
})

try { [void]$form.ShowDialog() }
catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Modern 10 Setup', 'OK', 'Error') | Out-Null }
