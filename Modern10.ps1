#Requires -Version 5.1
<#
.SYNOPSIS
    Modern 10 (v1.2) - a glassy, macOS-inspired Dark/Light look for Windows 10.

.DESCRIPTION
    Nothing is installed. The script only:
      * changes built-in Windows settings (registry, current user),
      * moves the taskbar to the top or bottom and applies the icon size you pick,
      * replaces system, drive and folder icons with macOS-style icons it draws itself,
      * draws its own wallpaper and lock screen image (System.Drawing),
      * sets the lock screen with the built-in per-user WinRT API (no admin needed),
      * backs up every value it touches so it can be fully undone,
      * verifies the result and writes a log: C:\ProgramData\Modern10\modern10.log

.PARAMETER Theme        Dark or Light. Asked if omitted.
.PARAMETER TaskbarPosition  Top or Bottom. Asked if omitted.
.PARAMETER IconSize     Small (16px), Default (32px) or Keep. Asked if omitted.
.PARAMETER Icons        Yes or No - change system/drive/folder icons. Asked if omitted.
.PARAMETER NoIcons      Same as -Icons No.
.PARAMETER NoFolderIcons      Skip the generic folder icon (the only icon step that needs admin).
.PARAMETER NoUserFolderIcons  Skip Documents/Downloads/Pictures/Music/Videos/Desktop folder icons.
.PARAMETER NoWallpaper  Do not draw / set the wallpaper.
.PARAMETER NoLockScreen Do not draw / set the lock screen.
.PARAMETER NoRestartExplorer  Do not restart explorer.exe (sign out/in to apply taskbar changes).
.PARAMETER NoPause      Do not wait for Enter at the end.
.PARAMETER Restore      Undo everything using the saved backup.

.EXAMPLE
    .\Modern10.ps1 -Theme Dark -IconSize Small
    .\Modern10.ps1 -Restore
#>
[CmdletBinding()]
param(
    [ValidateSet('Dark', 'Light')][string]$Theme,
    [ValidateSet('Top', 'Bottom')][string]$TaskbarPosition,
    [ValidateSet('Small', 'Default', 'Keep')][string]$IconSize,
    [ValidateSet('Yes', 'No')][string]$Icons,
    [switch]$NoIcons,
    [switch]$NoFolderIcons,
    [switch]$NoUserFolderIcons,
    [switch]$NoWallpaper,
    [switch]$NoLockScreen,
    [switch]$NoRestartExplorer,
    [switch]$NoPause,
    [switch]$Restore,
    [string]$InternalLockImage,
    [switch]$InternalLockRemove,
    [string]$InternalFolderIcon,
    [string]$InternalFolderIconOpen,
    [switch]$InternalFolderIconsRemove,
    [switch]$InternalMachineCleanup
)

$ErrorActionPreference = 'Stop'

# The WinRT lock screen API only exists in Windows PowerShell 5.1, not PowerShell 7+.
if ($PSVersionTable.PSEdition -eq 'Core') {
    $relaunch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) {
            if ($v.IsPresent) { $relaunch += "-$k" }
        } else {
            $relaunch += "-$k"; $relaunch += [string]$v
        }
    }
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @relaunch
    exit $LASTEXITCODE
}

$script:DataDir    = Join-Path $env:ProgramData 'Modern10'
$script:BackupFile = Join-Path $script:DataDir 'backup.json'
$script:LogFile    = Join-Path $script:DataDir 'modern10.log'
$script:Report     = [ordered]@{}
try { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null } catch { }

# ----------------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------------
function Write-Log([string]$Text) {
    try {
        Add-Content -LiteralPath $script:LogFile -Encoding UTF8 `
            -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Text)
    } catch { }
}
function Write-Step([string]$Text) { Write-Host ('  > ' + $Text) -ForegroundColor Gray;   Write-Log $Text }
function Write-Ok([string]$Text)   { Write-Host ('  + ' + $Text) -ForegroundColor Green;  Write-Log ('OK   ' + $Text) }
function Write-Warn([string]$Text) { Write-Host ('  ! ' + $Text) -ForegroundColor Yellow; Write-Log ('WARN ' + $Text) }

# ----------------------------------------------------------------------------
# Native helpers
# ----------------------------------------------------------------------------
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

if (-not ('M10Native' -as [type])) {
Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class M10Native
{
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);

    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);

    // Very light monochrome grain so dark gradients do not show banding.
    public static void AddGrain(System.Drawing.Bitmap bmp, int amp)
    {
        Random r = new Random(7);
        System.Drawing.Rectangle rect = new System.Drawing.Rectangle(0, 0, bmp.Width, bmp.Height);
        System.Drawing.Imaging.BitmapData d = bmp.LockBits(rect,
            System.Drawing.Imaging.ImageLockMode.ReadWrite,
            System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        int n = Math.Abs(d.Stride) * bmp.Height;
        byte[] buf = new byte[n];
        Marshal.Copy(d.Scan0, buf, 0, n);
        for (int i = 0; i < n; i += 4)
        {
            int v = r.Next(-amp, amp + 1);
            for (int c = 0; c < 3; c++)
            {
                int x = buf[i + c] + v;
                buf[i + c] = (byte)(x < 0 ? 0 : (x > 255 ? 255 : x));
            }
        }
        Marshal.Copy(buf, 0, d.Scan0, n);
        bmp.UnlockBits(d);
    }
}
'@
}

# Must be set before any screen metrics are read
[void][M10Native]::SetProcessDPIAware()

. (Join-Path $PSScriptRoot 'Modern10.Icons.ps1')

# ----------------------------------------------------------------------------
# Utilities
# ----------------------------------------------------------------------------
function Read-Choice {
    param([string]$Title, [string[]]$Options, [int]$Default = 1)
    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ('  [{0}] {1}' -f ($i + 1), $Options[$i])
    }
    while ($true) {
        $a = Read-Host ('Select 1-{0} (Enter = {1})' -f $Options.Count, $Default)
        if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
        $n = 0
        if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n }
        Write-Host 'Invalid choice.' -ForegroundColor Yellow
    }
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Get-AccentDword([int]$R, [int]$G, [int]$B) {
    # Accent colours are stored as ABGR in a DWORD (signed Int32 in PowerShell)
    return [int]((0xFF -shl 24) -bor ($B -shl 16) -bor ($G -shl 8) -bor $R)
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Runs this script elevated with an internal switch and returns the child's exit code.
function Invoke-SelfElevated([string[]]$ExtraArgs) {
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath)) + $ExtraArgs
    if (Test-IsAdmin) {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -Wait -PassThru -WindowStyle Hidden
    } else {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -Verb RunAs -Wait -PassThru -WindowStyle Hidden
    }
    return $p.ExitCode
}

function Send-SettingChange([string]$Area = 'ImmersiveColorSet') {
    $r = [UIntPtr]::Zero
    [void][M10Native]::SendMessageTimeout([IntPtr]0xFFFF, 0x1A, [UIntPtr]::Zero, $Area, 2, 2000, [ref]$r)
}

function Invoke-Stage {
    param([string]$Name, [scriptblock]$Action)
    try {
        & $Action
        if (-not $script:Report.Contains($Name)) { $script:Report[$Name] = 'OK' }
        Write-Log "STAGE OK: $Name"
    } catch {
        $msg = $_.Exception.Message
        Write-Warn "$Name failed: $msg"
        Write-Log ("STAGE FAILED: $Name`r`n" + ($_ | Out-String))
        $script:Report[$Name] = "FAILED - $msg"
    }
}

# ----------------------------------------------------------------------------
# Lock screen - machine-level fallback (admin) and cleanup
# ----------------------------------------------------------------------------
$script:CspKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
$script:PolKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'

function Set-LockScreenMachine([string]$ImagePath) {
    Set-Reg $script:CspKey 'LockScreenImagePath'   $ImagePath 'String'
    Set-Reg $script:CspKey 'LockScreenImageUrl'    $ImagePath 'String'
    Set-Reg $script:CspKey 'LockScreenImageStatus' 1          'DWord'
    Set-Reg $script:PolKey 'LockScreenImage'       $ImagePath 'String'
}

# True only if a machine-level override pointing at a Modern 10 image exists
# (never touches an override set by someone else, e.g. an organisation).
function Test-LockOverridesPresent {
    foreach ($pair in @(@($script:CspKey, 'LockScreenImagePath'), @($script:PolKey, 'LockScreenImage'))) {
        $v = Get-ItemProperty -LiteralPath $pair[0] -Name $pair[1] -ErrorAction SilentlyContinue
        if ($v -and ([string]$v.($pair[1])) -like '*\Modern10\*') { return $true }
    }
    return $false
}

function Remove-LockScreenMachine {
    if (-not (Test-LockOverridesPresent)) { return }
    foreach ($n in 'LockScreenImagePath', 'LockScreenImageUrl', 'LockScreenImageStatus') {
        Remove-ItemProperty -LiteralPath $script:CspKey -Name $n -ErrorAction SilentlyContinue
    }
    Remove-ItemProperty -LiteralPath $script:PolKey -Name 'LockScreenImage' -ErrorAction SilentlyContinue
}

# Generic folder icons live in HKLM "Shell Icons" (3 = closed folder, 4 = open folder) - admin only
$script:ShellIconsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons'

function Set-FolderIconsMachine([string]$Closed, [string]$Open) {
    Set-Reg $script:ShellIconsKey '3' ("$Closed,0") 'String'
    Set-Reg $script:ShellIconsKey '4' ("$Open,0")   'String'
}

function Test-FolderIconsMachine {
    foreach ($n in '3', '4') {
        $v = Get-ItemProperty -LiteralPath $script:ShellIconsKey -Name $n -ErrorAction SilentlyContinue
        if ($v -and ([string]$v.$n) -like '*\Modern10\*') { return $true }
    }
    return $false
}

function Remove-FolderIconsMachine {
    foreach ($n in '3', '4') {
        $v = Get-ItemProperty -LiteralPath $script:ShellIconsKey -Name $n -ErrorAction SilentlyContinue
        if ($v -and ([string]$v.$n) -like '*\Modern10\*') {
            Remove-ItemProperty -LiteralPath $script:ShellIconsKey -Name $n -ErrorAction SilentlyContinue
        }
    }
}

# Elevated child entry points
if ($InternalFolderIcon) {
    try { Set-FolderIconsMachine $InternalFolderIcon $InternalFolderIconOpen; Write-Log 'Child: folder icons set'; exit 0 }
    catch { Write-Log "Child: folder icons failed: $($_.Exception.Message)"; exit 1 }
}
if ($InternalFolderIconsRemove) {
    try { Remove-FolderIconsMachine; Write-Log 'Child: folder icons removed'; exit 0 }
    catch { Write-Log "Child: folder icon cleanup failed: $($_.Exception.Message)"; exit 1 }
}
if ($InternalMachineCleanup) {
    try { Remove-LockScreenMachine; Remove-FolderIconsMachine; Write-Log 'Child: machine cleanup done'; exit 0 }
    catch { Write-Log "Child: machine cleanup failed: $($_.Exception.Message)"; exit 1 }
}
if ($InternalLockImage) {
    try { Set-LockScreenMachine $InternalLockImage; Write-Log "Child: machine lock screen set to $InternalLockImage"; exit 0 }
    catch { Write-Log "Child: lock screen failed: $($_.Exception.Message)"; exit 1 }
}
if ($InternalLockRemove) {
    try { Remove-LockScreenMachine; Write-Log 'Child: machine lock screen override removed'; exit 0 }
    catch { Write-Log "Child: lock screen cleanup failed: $($_.Exception.Message)"; exit 1 }
}

# ----------------------------------------------------------------------------
# Lock screen - per-user WinRT API (the same call Settings uses; no admin)
# ----------------------------------------------------------------------------
function Set-LockScreenImageUser([string]$Path) {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.System.UserProfile.LockScreen,Windows.System.UserProfile,ContentType=WindowsRuntime]
    $null = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]

    $ext = [System.WindowsRuntimeSystemExtensions]
    $asTaskOp = ($ext.GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    $asTaskAction = ($ext.GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and -not $_.IsGenericMethod })[0]

    $op = [Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)
    $t1 = $asTaskOp.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke($null, @($op))
    [void]$t1.Wait(-1)
    $file = $t1.Result

    $act = [Windows.System.UserProfile.LockScreen]::SetImageFileAsync($file)
    $t2 = $asTaskAction.Invoke($null, @($act))
    [void]$t2.Wait(-1)

    try { return [string][Windows.System.UserProfile.LockScreen]::OriginalImageFile } catch { return $Path }
}

# ----------------------------------------------------------------------------
# Backup of every value Modern 10 touches
# ----------------------------------------------------------------------------
$EXP = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$script:Tracked = @(
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; N = 'AppsUseLightTheme' },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; N = 'SystemUsesLightTheme' },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; N = 'EnableTransparency' },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; N = 'ColorPrevalence' },
    @{ P = 'HKCU:\Software\Microsoft\Windows\DWM'; N = 'AccentColor' },
    @{ P = 'HKCU:\Software\Microsoft\Windows\DWM'; N = 'ColorPrevalence' },
    @{ P = "$EXP\Accent"; N = 'AccentColorMenu' },
    @{ P = "$EXP\Accent"; N = 'StartColorMenu' },
    @{ P = "$EXP\Advanced"; N = 'TaskbarSmallIcons' },
    @{ P = "$EXP\Advanced"; N = 'TaskbarGlomLevel' },
    @{ P = "$EXP\Advanced"; N = 'ShowTaskViewButton' },
    @{ P = "$EXP\Advanced"; N = 'ShowCortanaButton' },
    @{ P = "$EXP\Advanced"; N = 'ListviewAlphaSelect' },
    @{ P = "$EXP\Advanced"; N = 'ListviewShadow' },
    @{ P = "$EXP\Advanced"; N = 'TaskbarAnimations' },
    @{ P = "$EXP\Advanced\People"; N = 'PeopleBand' },
    @{ P = "$EXP\StuckRects3"; N = 'Settings' },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; N = 'SearchboxTaskbarMode' },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds'; N = 'ShellFeedsTaskbarViewMode' },
    @{ P = 'HKCU:\Control Panel\Desktop'; N = 'Wallpaper' },
    @{ P = 'HKCU:\Control Panel\Desktop'; N = 'WallpaperStyle' },
    @{ P = 'HKCU:\Control Panel\Desktop'; N = 'TileWallpaper' }
)

function Save-Backup {
    if (Test-Path -LiteralPath $script:BackupFile) {
        Write-Step 'Existing backup found - keeping your original settings.'
        return
    }
    $rows = foreach ($t in $script:Tracked) {
        $exists = $false; $kind = $null; $val = $null
        try {
            $key = Get-Item -LiteralPath $t.P -ErrorAction Stop
            if ($key.GetValueNames() -contains $t.N) {
                $exists = $true
                $kind = [string]$key.GetValueKind($t.N)
                $val = $key.GetValue($t.N, $null, 'DoNotExpandEnvironmentNames')
            }
        } catch { }
        [pscustomobject]@{ Path = $t.P; Name = $t.N; Exists = $exists; Kind = $kind; Value = $val }
    }
    $rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:BackupFile -Encoding UTF8
    Write-Ok "Backup saved: $($script:BackupFile)"
}

# ----------------------------------------------------------------------------
# Icons (system icons, drives, user folders) - all per-user, no admin
# ----------------------------------------------------------------------------
$script:ClearIcons = $false
$script:IconBackupFile = Join-Path $script:DataDir 'icons-backup.json'
$script:ClsidIcons = [ordered]@{
    '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' = 'ThisPC'
    '{59031a47-3f72-44a7-89c5-5595fe6b30ee}' = 'User'
    '{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}' = 'Network'
    '{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}' = 'ControlPanel'
    '{645FF040-5081-101B-9F08-00AA002F954E}' = 'RecycleEmpty'
}
$script:DrivesKey = 'HKCU:\Software\Classes\Applications\Explorer.exe\Drives'

function Get-KeyValueDump([string]$Path) {
    $vals = @()
    if (Test-Path -LiteralPath $Path) {
        $k = Get-Item -LiteralPath $Path
        foreach ($n in $k.GetValueNames()) {
            $vals += [pscustomobject]@{
                Name  = $n
                Kind  = [string]$k.GetValueKind($n)
                Value = [string]$k.GetValue($n, $null, 'DoNotExpandEnvironmentNames')
            }
        }
    }
    return $vals
}

function Get-UserFolderList {
    $map = [ordered]@{
        Desktop   = [Environment]::GetFolderPath('DesktopDirectory')
        Documents = [Environment]::GetFolderPath('MyDocuments')
        Pictures  = [Environment]::GetFolderPath('MyPictures')
        Music     = [Environment]::GetFolderPath('MyMusic')
        Videos    = [Environment]::GetFolderPath('MyVideos')
    }
    $dl = $null
    try {
        $usf = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop
        $raw = $usf.'{374DE290-123F-4565-9164-39C4925E467B}'
        if ($raw) { $dl = [Environment]::ExpandEnvironmentVariables([string]$raw) }
    } catch { }
    if (-not $dl) { $dl = Join-Path $env:USERPROFILE 'Downloads' }
    $map['Downloads'] = $dl

    $list = @()
    foreach ($k in $map.Keys) {
        $path = $map[$k]
        if ($path -and (Test-Path -LiteralPath $path -PathType Container)) {
            $list += [pscustomobject]@{ Kind = $k; Path = $path }
        }
    }
    return $list
}

function Save-IconBackup($UserFolders) {
    if (Test-Path -LiteralPath $script:IconBackupFile) { return }
    $clsid = foreach ($guid in $script:ClsidIcons.Keys) {
        $path = "$EXP\CLSID\$guid\DefaultIcon"
        [pscustomobject]@{ Path = $path; Existed = (Test-Path -LiteralPath $path); Values = @(Get-KeyValueDump $path) }
    }
    $folders = foreach ($u in $UserFolders) {
        $ini = Join-Path $u.Path 'desktop.ini'
        $has = Test-Path -LiteralPath $ini -PathType Leaf
        $content = ''; $iattr = 0
        if ($has) {
            $i = Get-Item -LiteralPath $ini -Force
            $iattr = [int]$i.Attributes
            $content = [string](Get-Content -LiteralPath $ini -Raw)
        }
        [pscustomobject]@{
            Folder = $u.Path; IniExisted = $has; Content = $content; IniAttr = $iattr
            FolderAttr = [int](Get-Item -LiteralPath $u.Path -Force).Attributes
        }
    }
    [pscustomobject]@{ Clsid = @($clsid); UserFolders = @($folders | Where-Object { $_ }) } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:IconBackupFile -Encoding UTF8
    Write-Log "Icon backup saved: $($script:IconBackupFile)"
}

function Set-SystemIcons([string]$Dir) {
    foreach ($guid in $script:ClsidIcons.Keys) {
        $key  = "$EXP\CLSID\$guid\DefaultIcon"
        $kind = $script:ClsidIcons[$guid]
        Set-Reg $key '(default)' ("{0},0" -f (Join-Path $Dir "$kind.ico")) 'String'
        if ($kind -eq 'RecycleEmpty') {
            Set-Reg $key 'empty' ("{0},0" -f (Join-Path $Dir 'RecycleEmpty.ico')) 'String'
            Set-Reg $key 'full'  ("{0},0" -f (Join-Path $Dir 'RecycleFull.ico'))  'String'
        }
    }
}

function Set-DriveIcons([string]$Dir) {
    $ico = "{0},0" -f (Join-Path $Dir 'Drive.ico')
    $count = 0
    foreach ($d in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
        $letter = $d.DeviceID.Substring(0, 1)
        Set-Reg "$($script:DrivesKey)\$letter\DefaultIcon" '(default)' $ico 'String'
        $count++
    }
    return $count
}

function Remove-DriveIcons {
    if (-not (Test-Path -LiteralPath $script:DrivesKey)) { return }
    foreach ($sub in @(Get-ChildItem -LiteralPath $script:DrivesKey -ErrorAction SilentlyContinue)) {
        $di = Join-Path $sub.PSPath 'DefaultIcon'
        if (Test-Path -LiteralPath $di) {
            $cur = [string](Get-Item -LiteralPath $di).GetValue('')
            if ($cur -like '*\Modern10\*') { Remove-Item -LiteralPath $sub.PSPath -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Set-FolderIconIni([string]$Folder, [string]$Ico) {
    $ini = Join-Path $Folder 'desktop.ini'
    $content = ''
    if (Test-Path -LiteralPath $ini -PathType Leaf) {
        $content = [string](Get-Content -LiteralPath $ini -Raw)
        [System.IO.File]::SetAttributes($ini, [System.IO.FileAttributes]::Normal)
    }
    $lines = @()
    if ($content) { $lines = @($content -split "\r?\n" | Where-Object { $_.Trim() -ne '' }) }
    $lines = @($lines | Where-Object { $_ -notmatch '^\s*(IconResource|IconFile|IconIndex)\s*=' })
    $idx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ieq '[.ShellClassInfo]') { $idx = $i; break }
    }
    if ($idx -lt 0) { $lines = @('[.ShellClassInfo]') + $lines; $idx = 0 }
    $out = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $out += $lines[$i]
        if ($i -eq $idx) { $out += "IconResource=$Ico,0" }
    }
    Set-Content -LiteralPath $ini -Value (($out -join "`r`n") + "`r`n") -Encoding Unicode -NoNewline
    [System.IO.File]::SetAttributes($ini, ([System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System))
    $fa = [int](Get-Item -LiteralPath $Folder -Force).Attributes
    if (($fa -band 1) -eq 0) { [System.IO.File]::SetAttributes($Folder, [System.IO.FileAttributes]($fa -bor 1)) }
}

function Restore-IconState {
    $bk = $null
    if (Test-Path -LiteralPath $script:IconBackupFile) {
        $bk = Get-Content -LiteralPath $script:IconBackupFile -Raw | ConvertFrom-Json
    }

    foreach ($guid in $script:ClsidIcons.Keys) {
        $path = "$EXP\CLSID\$guid\DefaultIcon"
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $rec = $null
        if ($bk) { $rec = @($bk.Clsid) | Where-Object { $_.Path -eq $path } | Select-Object -First 1 }
        if ($rec -and $rec.Existed) {
            $k = Get-Item -LiteralPath $path
            foreach ($n in $k.GetValueNames()) {
                $nm = $n; if ($nm -eq '') { $nm = '(default)' }
                Remove-ItemProperty -LiteralPath $path -Name $nm -ErrorAction SilentlyContinue
            }
            foreach ($v in @($rec.Values)) {
                $nm = [string]$v.Name; if ($nm -eq '') { $nm = '(default)' }
                Set-Reg $path $nm ([string]$v.Value) 'String'
            }
        } else {
            $cur = [string](Get-Item -LiteralPath $path).GetValue('')
            if ($cur -like '*\Modern10\*') {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
                $parent = Split-Path -Path $path -Parent
                if ((Test-Path -LiteralPath $parent) -and
                    -not @(Get-ChildItem -LiteralPath $parent -ErrorAction SilentlyContinue) -and
                    ((Get-Item -LiteralPath $parent).ValueCount -eq 0)) {
                    Remove-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Remove-DriveIcons

    if ($bk) {
        foreach ($u in @($bk.UserFolders)) {
            try {
                $ini = Join-Path $u.Folder 'desktop.ini'
                if (Test-Path -LiteralPath $ini) { [System.IO.File]::SetAttributes($ini, [System.IO.FileAttributes]::Normal) }
                if ($u.IniExisted) {
                    Set-Content -LiteralPath $ini -Value ([string]$u.Content) -Encoding Unicode -NoNewline
                    [System.IO.File]::SetAttributes($ini, [System.IO.FileAttributes][int]$u.IniAttr)
                } else {
                    Remove-Item -LiteralPath $ini -Force -ErrorAction SilentlyContinue
                }
                if (Test-Path -LiteralPath $u.Folder) {
                    [System.IO.File]::SetAttributes($u.Folder, [System.IO.FileAttributes][int]$u.FolderAttr)
                }
            } catch { Write-Log "Could not restore $($u.Folder): $($_.Exception.Message)" }
        }
    }
    Remove-Item -LiteralPath $script:IconBackupFile -ErrorAction SilentlyContinue
}

# Explorer keeps rendered icons in cache files; they can only be deleted while Explorer is stopped.
function Clear-IconCache {
    $ex = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    Get-ChildItem -LiteralPath $ex -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'IconCache.db') -Force -ErrorAction SilentlyContinue
    Write-Log 'Icon cache cleared'
}

function Update-ShellIcons {
    # SHCNE_ASSOCCHANGED
    [M10Native]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
}

# ----------------------------------------------------------------------------
# Taskbar (edge: 0 left, 1 top, 2 right, 3 bottom)
# ----------------------------------------------------------------------------
$script:EdgeNames = @{ 0 = 'Left'; 1 = 'Top'; 2 = 'Right'; 3 = 'Bottom' }

function Set-TaskbarEdge([int]$Edge) {
    $changed = 0
    foreach ($k in 'StuckRects3', 'MMStuckRects3') {
        $p = "$EXP\$k"
        if (-not (Test-Path -LiteralPath $p)) { Write-Log "Key not found: $p"; continue }
        $item = Get-Item -LiteralPath $p
        foreach ($n in $item.GetValueNames()) {
            if ($item.GetValueKind($n) -ne 'Binary') { continue }
            if ($k -eq 'StuckRects3' -and $n -ne 'Settings') { continue }
            $b = [byte[]]$item.GetValue($n)
            if ($b.Length -gt 12) {
                $b[12] = [byte]$Edge
                Set-ItemProperty -LiteralPath $p -Name $n -Value $b -Type Binary
                $changed++
            }
        }
    }
    if ($changed -eq 0) { throw 'Taskbar layout key (StuckRects3) was not found or is empty.' }
}

function Get-TaskbarEdgeRegistry {
    try {
        $s = (Get-ItemProperty -LiteralPath "$EXP\StuckRects3" -ErrorAction Stop).Settings
        if ($s -and $s.Length -gt 12) { return [int]$s[12] }
    } catch { }
    return -1
}

function Write-TaskbarRegistry([int]$Edge, [int]$Small) {
    if ($Small -ge 0) { Set-Reg "$EXP\Advanced" 'TaskbarSmallIcons' $Small 'DWord' }
    Set-TaskbarEdge $Edge
}

function Test-TaskbarRegistry([int]$Edge, [int]$Small) {
    if ((Get-TaskbarEdgeRegistry) -ne $Edge) { return $false }
    if ($Small -ge 0) {
        $v = Get-ItemProperty -LiteralPath "$EXP\Advanced" -Name 'TaskbarSmallIcons' -ErrorAction SilentlyContinue
        if (-not $v -or [int]$v.TaskbarSmallIcons -ne $Small) { return $false }
    }
    return $true
}

# Measures the real, live taskbar on the primary monitor.
function Get-LiveTaskbar {
    $s = [System.Windows.Forms.Screen]::PrimaryScreen
    $b = $s.Bounds; $w = $s.WorkingArea
    if     ($w.Top -gt $b.Top)       { $e = 'Top';    $t = $w.Top - $b.Top }
    elseif ($w.Bottom -lt $b.Bottom) { $e = 'Bottom'; $t = $b.Bottom - $w.Bottom }
    elseif ($w.Left -gt $b.Left)     { $e = 'Left';   $t = $w.Left - $b.Left }
    elseif ($w.Right -lt $b.Right)   { $e = 'Right';  $t = $b.Right - $w.Right }
    else                             { $e = 'Unknown (auto-hide?)'; $t = 0 }
    return [pscustomobject]@{ Edge = $e; Thickness = $t }
}

function Stop-ExplorerShell {
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ((Get-Process -Name explorer -ErrorAction SilentlyContinue) -and $sw.Elapsed.TotalSeconds -lt 10) {
        Start-Sleep -Milliseconds 200
    }
}

function Start-ExplorerShell {
    # Give Windows a moment to respawn the shell by itself; start it only if it did not.
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue) -and $sw.Elapsed.TotalSeconds -lt 3) {
        Start-Sleep -Milliseconds 250
    }
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    $sw.Restart()
    while (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue) -and $sw.Elapsed.TotalSeconds -lt 10) {
        Start-Sleep -Milliseconds 250
    }
}

# Writes the taskbar registry, restarts Explorer, then verifies registry AND the live taskbar.
function Invoke-TaskbarApply {
    param([int]$Edge, [int]$Small, [bool]$Restart)

    Write-TaskbarRegistry $Edge $Small
    Send-SettingChange 'TraySettings'
    if (-not $Restart) {
        $script:Report['Taskbar'] = 'Saved - sign out and back in to apply'
        return
    }

    $expected = $script:EdgeNames[$Edge]
    $ok = $false
    for ($attempt = 1; $attempt -le 3 -and -not $ok; $attempt++) {
        Write-Step "Restarting Explorer to apply taskbar changes (attempt $attempt of 3)..."
        Stop-ExplorerShell
        if ($script:ClearIcons) { Clear-IconCache }
        Write-TaskbarRegistry $Edge $Small      # written while no shell is running
        Start-ExplorerShell
        Start-Sleep -Seconds 3
        $regOk = Test-TaskbarRegistry $Edge $Small
        $live = Get-LiveTaskbar
        Write-Log ("Attempt {0}: registryOk={1} live={2} thickness={3}px" -f $attempt, $regOk, $live.Edge, $live.Thickness)
        $ok = $regOk -and ($live.Edge -eq $expected -or $live.Edge -like 'Unknown*')
    }

    $live = Get-LiveTaskbar
    if ($ok) {
        $script:Report['Taskbar'] = ('OK - {0}, {1}px thick' -f $live.Edge, $live.Thickness)
        Write-Ok ("Taskbar is now at the {0} ({1}px)" -f $live.Edge.ToLower(), $live.Thickness)
    } else {
        $script:Report['Taskbar'] = ('Saved, but live taskbar is {0} - sign out and back in' -f $live.Edge)
        Write-Warn 'Settings were saved but Explorer did not pick them up. Sign out and back in.'
    }
}

# ----------------------------------------------------------------------------
# Image drawing
# ----------------------------------------------------------------------------
function Get-Col([string]$Hex, [int]$Alpha = 255) {
    $h = $Hex.TrimStart('#')
    return [System.Drawing.Color]::FromArgb($Alpha,
        [Convert]::ToInt32($h.Substring(0, 2), 16),
        [Convert]::ToInt32($h.Substring(2, 2), 16),
        [Convert]::ToInt32($h.Substring(4, 2), 16))
}

function Add-Glow($G, [single]$Cx, [single]$Cy, [single]$R, $Color) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddEllipse([single]($Cx - $R), [single]($Cy - $R * 0.85), [single](2 * $R), [single](2 * $R * 0.85))
    $br = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
    $br.CenterPoint = New-Object System.Drawing.PointF($Cx, $Cy)
    $br.CenterColor = $Color
    $br.SurroundColors = [System.Drawing.Color[]]@([System.Drawing.Color]::FromArgb(0, $Color.R, $Color.G, $Color.B))
    $bl = New-Object System.Drawing.Drawing2D.Blend(5)
    $bl.Factors = [single[]](0, 0.08, 0.35, 0.75, 1)
    $bl.Positions = [single[]](0, 0.25, 0.5, 0.75, 1)
    $br.Blend = $bl
    $G.FillPath($br, $path)
    $br.Dispose(); $path.Dispose()
}

function Add-Wave($G, [int]$W, [int]$H, [double]$Y0, [double]$Amp, [double]$Phase, $C1, $C2, $EdgeColor) {
    $n = 64
    $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    for ($i = 0; $i -le $n; $i++) {
        $t = $i / $n
        $x = $W * $t
        $y = $Y0 + $Amp * [Math]::Sin($t * 6.2832 * 0.9 + $Phase) + $Amp * 0.45 * [Math]::Sin($t * 6.2832 * 1.7 + $Phase * 1.3)
        $pts.Add((New-Object System.Drawing.PointF([single]$x, [single]$y)))
    }
    $arr = $pts.ToArray()
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddCurve($arr, 0.5)
    $path.AddLine([single]$W, [single]$H, [single]0, [single]$H)
    $path.CloseFigure()
    $rect = New-Object System.Drawing.RectangleF(0, [single]($Y0 - $Amp * 1.5), [single]$W, [single]($H - $Y0 + $Amp * 1.5))
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $C1, $C2, [single]90)
    $G.FillPath($br, $path)
    $pen = New-Object System.Drawing.Pen($EdgeColor, [single]([Math]::Max(2, $W / 900)))
    $G.DrawCurve($pen, $arr, 0.5)
    $pen.Dispose(); $br.Dispose(); $path.Dispose()
}

function New-GlassImage {
    param([string]$Path, [int]$W, [int]$H, [string]$Mode, [string]$Kind)

    $dark = ($Mode -eq 'Dark')
    $lock = ($Kind -eq 'Lock')

    if ($dark) {
        $bg1 = '#070B1F'; $bg2 = '#1B0F3D'
        $glows = @(
            @('#0A84FF', 0.20, 0.25, 0.42, 200),
            @('#7D3CFF', 0.78, 0.18, 0.40, 190),
            @('#FF2D95', 0.62, 0.92, 0.38, 150),
            @('#30D5C8', 0.10, 0.95, 0.28, 90),
            @('#5E5CE6', 0.50, 0.50, 0.50, 110)
        )
        $waves = @(
            @(0.62, 0.070, 0.6, '#8E7BFF', 110, '#1B0F4F', 40),
            @(0.74, 0.060, 2.1, '#3C9CFF', 100, '#0B1A5C', 30),
            @(0.86, 0.045, 3.7, '#FF5FB0', 90, '#2A0A44', 30)
        )
        $edge = Get-Col '#FFFFFF' 55
        $grain = 3
    } else {
        $bg1 = '#EAF1FF'; $bg2 = '#FDEFF6'
        $glows = @(
            @('#5AB0FF', 0.20, 0.25, 0.42, 210),
            @('#B79CFF', 0.78, 0.18, 0.40, 200),
            @('#FF9CC4', 0.62, 0.92, 0.38, 190),
            @('#FFC999', 0.10, 0.95, 0.30, 170),
            @('#FFFFFF', 0.50, 0.45, 0.45, 120)
        )
        $waves = @(
            @(0.62, 0.070, 0.6, '#FFFFFF', 170, '#CFE0FF', 60),
            @(0.74, 0.060, 2.1, '#FFD6EA', 150, '#E3D6FF', 50),
            @(0.86, 0.045, 3.7, '#FFFFFF', 190, '#BFD8FF', 70)
        )
        $edge = Get-Col '#FFFFFF' 210
        $grain = 2
    }

    $bmp = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.CompositingQuality = 'HighQuality'

    $rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
    $base = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, (Get-Col $bg1), (Get-Col $bg2), [single]45)
    $g.FillRectangle($base, $rect)
    $base.Dispose()

    foreach ($gl in $glows) {
        $cx = $gl[1]; if ($lock) { $cx = 1 - $gl[1] }
        Add-Glow $g ([single]($cx * $W)) ([single]($gl[2] * $H)) ([single]($gl[3] * $W)) (Get-Col $gl[0] $gl[4])
    }

    foreach ($wv in $waves) {
        $y0 = $wv[0]; $ph = $wv[2]
        if ($lock) { $y0 = $y0 - 0.06; $ph = $ph + 1.4 }
        Add-Wave $g $W $H ($y0 * $H) ($wv[1] * $H) $ph (Get-Col $wv[3] $wv[4]) (Get-Col $wv[5] $wv[6]) $edge
    }

    if ($lock -and $dark) {
        $ov = New-Object System.Drawing.SolidBrush((Get-Col '#000000' 45))
        $g.FillRectangle($ov, $rect)
        $ov.Dispose()
    }

    $g.Dispose()
    [M10Native]::AddGrain($bmp, $grain)
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

# ----------------------------------------------------------------------------
# Banner
# ----------------------------------------------------------------------------
try { Clear-Host } catch { }
Write-Host ''
Write-Host '  Modern 10 v1.2  -  glassy, macOS-inspired look for Windows 10' -ForegroundColor Cyan
Write-Host '  No installs. Built-in settings only.' -ForegroundColor DarkGray
Write-Host ''
Write-Log '================ Modern 10 run started ================'

try {
    $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
    Write-Log "Windows build $build, PowerShell $($PSVersionTable.PSVersion)"
    if ($build -ge 22000) {
        Write-Warn "Windows 11 detected (build $build). Modern 10 is made for Windows 10."
    }
} catch { }

# ----------------------------------------------------------------------------
# RESTORE
# ----------------------------------------------------------------------------
if ($Restore) {
    Write-Host '  Restoring original settings...' -ForegroundColor Cyan
    $script:OldWall = ''

    # Machine-level overrides first (one UAC prompt), before Explorer is stopped
    Invoke-Stage 'Remove machine overrides' {
        if ((Test-LockOverridesPresent) -or (Test-FolderIconsMachine)) {
            $code = Invoke-SelfElevated @('-InternalMachineCleanup')
            if ($code -ne 0) { throw 'Elevated cleanup failed (UAC declined?).' }
            Write-Ok 'Machine-level lock screen / folder icon overrides removed.'
        }
    }

    if (-not $NoRestartExplorer) { Stop-ExplorerShell }

    Invoke-Stage 'Restore settings' {
        if (Test-Path -LiteralPath $script:BackupFile) {
            $rows = Get-Content -LiteralPath $script:BackupFile -Raw | ConvertFrom-Json
            foreach ($r in $rows) {
                if ($r.Exists) {
                    switch ($r.Kind) {
                        'DWord'  { Set-Reg $r.Path $r.Name ([int]$r.Value) 'DWord' }
                        'Binary' { Set-Reg $r.Path $r.Name ([byte[]]$r.Value) 'Binary' }
                        default  { Set-Reg $r.Path $r.Name ([string]$r.Value) 'String' }
                    }
                    if ($r.Name -eq 'Wallpaper') { $script:OldWall = [string]$r.Value }
                } else {
                    Remove-ItemProperty -LiteralPath $r.Path -Name $r.Name -ErrorAction SilentlyContinue
                }
            }
            Write-Ok 'User settings restored from backup.'
        } else {
            Write-Warn 'No backup found - applying Windows defaults for the taskbar.'
            Set-Reg "$EXP\Advanced" 'TaskbarSmallIcons' 0 'DWord'
            Set-Reg "$EXP\Advanced" 'TaskbarGlomLevel' 0 'DWord'
            Set-TaskbarEdge 3
        }
        $e = Get-TaskbarEdgeRegistry
        if ($e -ge 0) { Set-TaskbarEdge $e }   # keep multi-monitor taskbars in sync
    }

    Invoke-Stage 'Restore icons' {
        Restore-IconState
        Write-Ok 'Icons restored.'
    }

    if (-not $NoRestartExplorer) { Clear-IconCache; Start-ExplorerShell }
    Update-ShellIcons

    Invoke-Stage 'Restore wallpaper' {
        [void][M10Native]::SystemParametersInfo(0x14, 0, [string]$script:OldWall, 3)
    }

    Write-Step 'Pick your lock screen picture again in Settings > Personalization > Lock screen.'

    foreach ($f in 'wallpaper-dark.png', 'wallpaper-light.png') {
        Remove-Item -LiteralPath (Join-Path $script:DataDir $f) -ErrorAction SilentlyContinue
    }
    Get-ChildItem -LiteralPath $script:DataDir -Filter 'lockscreen-*.png' -ErrorAction SilentlyContinue |
        Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $script:DataDir -Directory -Filter 'icons-*' -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:BackupFile -ErrorAction SilentlyContinue
    Send-SettingChange

    Write-Host ''
    Write-Ok "Restore finished. Log: $($script:LogFile)"
    if (-not $NoPause) { Read-Host '  Press Enter to close' | Out-Null }
    exit 0
}

# ----------------------------------------------------------------------------
# Questions
# ----------------------------------------------------------------------------
if (-not $Theme) {
    $c = Read-Choice 'Choose a theme:' @('Dark  (deep indigo glass)', 'Light (soft pastel glass)') 1
    $Theme = @('Dark', 'Light')[$c - 1]
}
if (-not $TaskbarPosition) {
    $c = Read-Choice 'Where should the taskbar go?' @(
        'Top    - like the macOS menu bar',
        'Bottom - the Windows default'
    ) 1
    $TaskbarPosition = @('Top', 'Bottom')[$c - 1]
}
if (-not $IconSize) {
    $c = Read-Choice 'Choose the taskbar icon size:' @(
        'Small   - 16px icons, slim bar (closest to a macOS menu bar)',
        'Default - 32px icons, standard height',
        'Keep    - leave my current size'
    ) 1
    $IconSize = @('Small', 'Default', 'Keep')[$c - 1]
}
if ($NoIcons) { $Icons = 'No' }
if (-not $Icons) {
    $c = Read-Choice 'Replace system, drive and folder icons with macOS-style icons?' @(
        'Yes - This PC, drives, Recycle Bin, folders (they are drawn locally)',
        'No  - leave icons alone'
    ) 1
    $Icons = @('Yes', 'No')[$c - 1]
}
$edgeValue = 1
if ($TaskbarPosition -eq 'Bottom') { $edgeValue = 3 }

Write-Host ''
Write-Host "  Applying: $Theme theme, taskbar = $($TaskbarPosition.ToLower()), icon size = $IconSize, icons = $Icons" -ForegroundColor Cyan
Write-Host ''
Write-Log "Options: Theme=$Theme Taskbar=$TaskbarPosition IconSize=$IconSize Icons=$Icons"

# ----------------------------------------------------------------------------
# Stage 1 - backup
# ----------------------------------------------------------------------------
Invoke-Stage 'Backup' { Save-Backup }

# ----------------------------------------------------------------------------
# Stage 2 - theme, accent, taskbar tidy-up (registry only)
# ----------------------------------------------------------------------------
Invoke-Stage 'Theme and glass' {
    $light = 0; if ($Theme -eq 'Light') { $light = 1 }
    $pers = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-Reg $pers 'AppsUseLightTheme'    $light 'DWord'
    Set-Reg $pers 'SystemUsesLightTheme' $light 'DWord'
    Set-Reg $pers 'EnableTransparency'   1      'DWord'
    Set-Reg $pers 'ColorPrevalence'      0      'DWord'
    if ($Theme -eq 'Dark') { $acc = Get-AccentDword 10 132 255 } else { $acc = Get-AccentDword 0 122 255 }
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'AccentColor'     $acc 'DWord'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorPrevalence' 0    'DWord'
    Set-Reg "$EXP\Accent" 'AccentColorMenu' $acc 'DWord'
    Set-Reg "$EXP\Accent" 'StartColorMenu'  $acc 'DWord'
    Write-Ok "$Theme mode, transparency and blue accent set"
}

Invoke-Stage 'Taskbar tidy-up' {
    $adv = "$EXP\Advanced"
    Set-Reg $adv 'TaskbarGlomLevel'    0 'DWord'
    Set-Reg $adv 'ShowTaskViewButton'  0 'DWord'
    Set-Reg $adv 'ShowCortanaButton'   0 'DWord'
    Set-Reg $adv 'ListviewAlphaSelect' 1 'DWord'
    Set-Reg $adv 'ListviewShadow'      1 'DWord'
    Set-Reg $adv 'TaskbarAnimations'   1 'DWord'
    Set-Reg "$adv\People" 'PeopleBand' 0 'DWord'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1 'DWord'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds'  'ShellFeedsTaskbarViewMode' 2 'DWord'
    Write-Ok 'Taskbar decluttered (icons only, search as icon)'
}

# ----------------------------------------------------------------------------
# Stage 3 - wallpaper
# ----------------------------------------------------------------------------
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$W = [int]$b.Width; $H = [int]$b.Height
$tag = $Theme.ToLower()

if (-not $NoWallpaper) {
    Invoke-Stage 'Wallpaper' {
        Write-Step "Drawing wallpaper ($W x $H)..."
        $wp = Join-Path $script:DataDir "wallpaper-$tag.png"
        New-GlassImage -Path $wp -W $W -H $H -Mode $Theme -Kind 'Wallpaper'
        Set-Reg 'HKCU:\Control Panel\Desktop' 'WallpaperStyle' '10' 'String'
        Set-Reg 'HKCU:\Control Panel\Desktop' 'TileWallpaper'  '0'  'String'
        if (-not [M10Native]::SystemParametersInfo(0x14, 0, $wp, 3)) { throw 'SystemParametersInfo refused the wallpaper.' }
        Write-Ok 'Wallpaper applied'
    }
}

# ----------------------------------------------------------------------------
# Stage 4 - lock screen: per-user WinRT API first, machine-level fallback second
# ----------------------------------------------------------------------------
if (-not $NoLockScreen) {
    Invoke-Stage 'Lock screen' {
        Write-Step "Drawing lock screen ($W x $H)..."
        # New file name every run so Windows cannot serve a cached copy
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $lp = Join-Path $script:DataDir "lockscreen-$tag-$stamp.png"
        New-GlassImage -Path $lp -W $W -H $H -Mode $Theme -Kind 'Lock'

        # Leftovers from the older registry-based method would block the per-user setting
        if (Test-LockOverridesPresent) {
            Write-Step 'Removing an older Modern 10 lock screen override (UAC prompt)...'
            [void](Invoke-SelfElevated @('-InternalLockRemove'))
        }

        $done = $false
        try {
            $applied = Set-LockScreenImageUser $lp
            Write-Ok 'Lock screen applied via the Windows lock screen API'
            Write-Log "LockScreen.OriginalImageFile = $applied"
            $script:Report['Lock screen'] = 'OK - per-user API'
            $done = $true
        } catch {
            Write-Warn "Per-user API failed: $($_.Exception.Message)"
        }

        if (-not $done) {
            Write-Step 'Trying the machine-level method (UAC prompt)...'
            $code = Invoke-SelfElevated @('-InternalLockImage', ('"{0}"' -f $lp))
            if ($code -ne 0) { throw "Machine-level method failed (exit code $code). See the log." }
            Write-Ok 'Lock screen applied via machine-level settings'
            $script:Report['Lock screen'] = 'OK - machine-level (set Background to Picture if unchanged)'
        }

        Get-ChildItem -LiteralPath $script:DataDir -Filter 'lockscreen-*.png' |
            Where-Object { $_.FullName -ne $lp } | Remove-Item -ErrorAction SilentlyContinue
        Write-Step 'Preview it with Win+L.'
    }
}

# ----------------------------------------------------------------------------
# Stage 4b - system, drive and folder icons (drawn locally, written as .ico files)
# ----------------------------------------------------------------------------
$iconDir = Join-Path $script:DataDir "icons-$tag"
if ($Icons -eq 'Yes') {
    Invoke-Stage 'Icons' {
        Write-Step 'Drawing 15 icons at 7 sizes each...'
        New-M10IconSet -Dir $iconDir -Theme $Theme

        $userFolders = @()
        if (-not $NoUserFolderIcons) { $userFolders = @(Get-UserFolderList) }
        Save-IconBackup $userFolders

        Set-SystemIcons $iconDir
        Write-Ok 'This PC, Recycle Bin, User, Network and Control Panel icons set'
        $n = Set-DriveIcons $iconDir
        Write-Ok "Drive icon set on $n fixed drive(s)"

        $done = 0
        foreach ($u in $userFolders) {
            try { Set-FolderIconIni $u.Path (Join-Path $iconDir "$($u.Kind).ico"); $done++ }
            catch { Write-Warn "Skipped $($u.Kind): $($_.Exception.Message)" }
        }
        if ($userFolders.Count -gt 0) { Write-Ok "User folder icons set ($done of $($userFolders.Count))" }

        $script:ClearIcons = $true
        Update-ShellIcons
        $script:Report['Icons'] = "OK - system, drive and $done user folder icon(s)"
    }

    if (-not $NoFolderIcons) {
        Invoke-Stage 'Folder icon' {
            Write-Step 'Setting the generic folder icon (a UAC prompt will appear)...'
            $code = Invoke-SelfElevated @(
                '-InternalFolderIcon', ('"{0}"' -f (Join-Path $iconDir 'Folder.ico')),
                '-InternalFolderIconOpen', ('"{0}"' -f (Join-Path $iconDir 'FolderOpen.ico')))
            if ($code -ne 0) { throw "Needs admin rights (exit code $code). Run again and accept the prompt, or use -NoFolderIcons." }
            Write-Ok 'Generic folder icon set'
            $script:Report['Folder icon'] = 'OK'
        }
    }
}

# ----------------------------------------------------------------------------
# Stage 5 - taskbar position + icon size, restart Explorer, verify
#           (runs last and on its own, so earlier failures can never skip it)
# ----------------------------------------------------------------------------
Invoke-Stage 'Taskbar' {
    $small = -1
    if ($IconSize -eq 'Small')   { $small = 1 }
    if ($IconSize -eq 'Default') { $small = 0 }
    Invoke-TaskbarApply -Edge $edgeValue -Small $small -Restart (-not $NoRestartExplorer)
}
Send-SettingChange

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
Write-Host ''
Write-Host '  Summary' -ForegroundColor Cyan
foreach ($k in $script:Report.Keys) {
    $v = [string]$script:Report[$k]
    $colour = 'Green'; if ($v -like 'FAILED*' -or $v -like 'Saved*') { $colour = 'Yellow' }
    Write-Host ('    {0,-18} {1}' -f $k, $v) -ForegroundColor $colour
    Write-Log "SUMMARY $k = $v"
}
Write-Host ''
Write-Host "  Log file : $script:LogFile" -ForegroundColor DarkGray
Write-Host '  Undo     : .\Modern10-Restore.ps1' -ForegroundColor DarkGray
if (-not $NoPause) { Read-Host '  Press Enter to close' | Out-Null }
