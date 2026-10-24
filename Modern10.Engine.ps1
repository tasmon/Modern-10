# Modern10.Engine.ps1  -  the working part of Modern 10 (no console, no prompts).
# Dot-sourced by Modern10.GUI.ps1. It only defines functions; nothing runs until the GUI calls
# Invoke-M10Apply or Invoke-M10Restore.
#
# Developer: Tasmon Islam

$script:M10Root      = $PSScriptRoot
$script:M10Version   = '2.0'
$script:M10Developer = 'Tasmon Islam'
$script:DataDir      = Join-Path $env:ProgramData 'Modern10'
$script:BackupFile   = Join-Path $script:DataDir 'backup.json'
$script:IconBackupFile = Join-Path $script:DataDir 'icons-backup.json'
$script:LogFile      = Join-Path $script:DataDir 'modern10.log'
$script:Report       = [ordered]@{}
$script:ClearIcons   = $false
$EXP = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$script:EXPSUB = 'Software\Microsoft\Windows\CurrentVersion\Explorer'

. (Join-Path $script:M10Root 'Modern10.Icons.ps1')

# ----------------------------------------------------------------------------
# Logging. Lines go to the log file and, when the GUI supplied one, to $M10Queue.
# ----------------------------------------------------------------------------
function Write-M10([string]$Level, [string]$Text) {
    $tag = '>'
    if ($Level -eq 'ok') { $tag = '+' } elseif ($Level -eq 'warn') { $tag = '!' } elseif ($Level -eq 'err') { $tag = 'x' }
    try {
        Add-Content -LiteralPath $script:LogFile -Encoding UTF8 `
            -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1} {2}' -f (Get-Date), $tag, $Text)
    } catch { }
    if ($global:M10Queue) { $global:M10Queue.Enqueue(('{0}|{1}' -f $Level, $Text)) }
}
function Write-Step([string]$Text) { Write-M10 'step' $Text }
function Write-Ok([string]$Text)   { Write-M10 'ok'   $Text }
function Write-Warn([string]$Text) { Write-M10 'warn' $Text }

# ----------------------------------------------------------------------------
# Native helpers (compiled on first use)
# ----------------------------------------------------------------------------
function Initialize-M10Native {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    try { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null } catch { }
    if (-not ('M10Native' -as [type])) {
Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition @'
using System;
using System.Text;
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

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SystemParametersInfo", SetLastError = true)]
    public static extern bool SystemParametersInfoGet(int uAction, int uParam, StringBuilder lpvParam, int fuWinIni);

    public static string GetWallpaper()
    {
        StringBuilder sb = new StringBuilder(520);
        SystemParametersInfoGet(0x73, 520, sb, 0);
        return sb.ToString();
    }

    // Very light monochrome grain so smooth gradients do not show banding.
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

[StructLayout(LayoutKind.Sequential)]
public struct M10RECT { public int Left; public int Top; public int Right; public int Bottom; }

[ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IM10DesktopWallpaper
{
    void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
    [return: MarshalAs(UnmanagedType.LPWStr)]
    string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
    [return: MarshalAs(UnmanagedType.LPWStr)]
    string GetMonitorDevicePathAt(uint monitorIndex);
    uint GetMonitorDevicePathCount();
    void GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID, out M10RECT displayRect);
    void SetBackgroundColor(uint color);
    uint GetBackgroundColor();
    void SetPosition(int position);
    int GetPosition();
    void SetSlideshow(IntPtr items);
    IntPtr GetSlideshow();
    void SetSlideshowOptions(int options, uint slideshowTick);
    void GetSlideshowOptions(out int options, out uint slideshowTick);
    void AdvanceSlideshow([MarshalAs(UnmanagedType.LPWStr)] string monitorID, int direction);
    int GetStatus();
    [return: MarshalAs(UnmanagedType.Bool)]
    bool Enable();
}

[ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")]
public class M10DesktopWallpaperClass { }

public static class M10Wall
{
    // Sets the wallpaper on every monitor through the same COM object the Settings app uses ("Fill" position).
    // Returns an empty string on success, otherwise the error text.
    public static string Set(string path)
    {
        try
        {
            IM10DesktopWallpaper dw = (IM10DesktopWallpaper)new M10DesktopWallpaperClass();
            dw.SetPosition(4);
            dw.SetWallpaper(null, path);
            return "";
        }
        catch (Exception e) { return e.Message; }
    }
}
'@
    }
    [void][M10Native]::SetProcessDPIAware()
}

# ----------------------------------------------------------------------------
# Registry helpers. Icon keys are written with the .NET registry API so that the
# unnamed "(Default)" value is really set (New-ItemProperty -Name '(default)' would
# create a value literally called "(default)", which Explorer ignores).
# ----------------------------------------------------------------------------
function Set-M10Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Set-M10StringValue([string]$SubKey, [string]$Name, [string]$Value) {
    $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($SubKey)
    try { $k.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::String) } finally { $k.Close() }
}

function Get-M10StringValue([string]$SubKey, [string]$Name) {
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SubKey)
    if (-not $k) { return $null }
    try { return $k.GetValue($Name, $null) } finally { $k.Close() }
}

function Get-M10AccentDword([int]$R, [int]$G, [int]$B) {
    # Accent colours are stored as ABGR in a DWORD (signed Int32 in PowerShell)
    return [int]((0xFF -shl 24) -bor ($B -shl 16) -bor ($G -shl 8) -bor $R)
}

function Send-M10SettingChange([string]$Area = 'ImmersiveColorSet') {
    $r = [UIntPtr]::Zero
    [void][M10Native]::SendMessageTimeout([IntPtr]0xFFFF, 0x1A, [UIntPtr]::Zero, $Area, 2, 2000, [ref]$r)
}

function Invoke-M10Stage {
    param([string]$Name, [scriptblock]$Action)
    try {
        & $Action
        if (-not $script:Report.Contains($Name)) { $script:Report[$Name] = 'OK' }
    } catch {
        $msg = $_.Exception.Message
        Write-Warn "$Name failed: $msg"
        Write-M10 'step' ("STAGE FAILED: $Name`r`n" + ($_ | Out-String))
        $script:Report[$Name] = "FAILED - $msg"
    }
}

# ----------------------------------------------------------------------------
# Elevated helper: one small script that is the only thing that runs as admin.
# ----------------------------------------------------------------------------
function Test-M10IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-M10Elevated([string]$Action, [string]$Theme = 'Dark', [string]$LockFile = '', [string]$IconTheme = 'Glass') {
    $helper = Join-Path $script:M10Root 'Modern10.Elevated.ps1'
    if (-not (Test-Path -LiteralPath $helper)) { throw "Helper not found: $helper" }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f $helper),
           '-Action', $Action, '-Theme', $Theme, '-IconTheme', $IconTheme)
    if ($LockFile) { $a += @('-LockFile', $LockFile) }
    try {
        if (Test-M10IsAdmin) {
            $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Wait -PassThru -WindowStyle Hidden
        } else {
            $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs -Wait -PassThru
        }
    } catch {
        throw 'Administrator permission was not granted (UAC prompt declined).'
    }
    return $p.ExitCode
}

$script:CspKey        = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
$script:PolKey        = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
$script:ShellIconsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons'
$script:DriveIconsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons'

# True only if a machine-level value points at a Modern 10 file (never touches someone else's override).
function Test-M10MachineOverrides {
    foreach ($pair in @(@($script:CspKey, 'LockScreenImagePath'), @($script:PolKey, 'LockScreenImage'),
                        @($script:ShellIconsKey, '3'), @($script:ShellIconsKey, '4'))) {
        $v = Get-ItemProperty -LiteralPath $pair[0] -Name $pair[1] -ErrorAction SilentlyContinue
        if ($v -and ([string]$v.($pair[1])) -like '*\Modern10\*') { return $true }
    }
    if (Test-Path -LiteralPath $script:DriveIconsKey) {
        foreach ($sub in @(Get-ChildItem -LiteralPath $script:DriveIconsKey -ErrorAction SilentlyContinue)) {
            $di = Join-Path $sub.PSPath 'DefaultIcon'
            if (Test-Path -LiteralPath $di) {
                $cur = [string](Get-Item -LiteralPath $di).GetValue('')
                if ($cur -like '*\Modern10\*') { return $true }
            }
        }
    }
    return $false
}

function Test-M10LockOverride {
    foreach ($pair in @(@($script:CspKey, 'LockScreenImagePath'), @($script:PolKey, 'LockScreenImage'))) {
        $v = Get-ItemProperty -LiteralPath $pair[0] -Name $pair[1] -ErrorAction SilentlyContinue
        if ($v -and ([string]$v.($pair[1])) -like '*\Modern10\*') { return $true }
    }
    return $false
}

# ----------------------------------------------------------------------------
# Lock screen - per-user WinRT API (the same call Settings uses; no admin)
# ----------------------------------------------------------------------------
function Set-M10LockScreenUser([string]$Path) {
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
# Backup of every plain registry value Modern 10 touches
# ----------------------------------------------------------------------------
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
    @{ P = "$EXP\Wallpapers"; N = 'BackgroundType' },
    @{ P = 'HKCU:\Control Panel\Desktop'; N = 'Wallpaper' },
    @{ P = 'HKCU:\Control Panel\Desktop'; N = 'WallpaperStyle' },
    @{ P = 'HKCU:\Control Panel\Desktop'; N = 'TileWallpaper' }
)

function Save-M10Backup {
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
# Icons
#   * Shell-namespace icons (This PC, its folders, User, Network, Control Panel, Recycle Bin):
#       HKCU\Software\Classes\CLSID\{guid}\DefaultIcon      <- what File Explorer's "This PC" view reads
#       HKCU\...\Explorer\CLSID\{guid}\DefaultIcon          <- what the desktop-icon settings read
#   * Drives: HKCU\Software\Classes\Applications\Explorer.exe\Drives\<letter>\DefaultIcon
#   * Folders inside the profile: IconResource= in desktop.ini
#   * (admin, one UAC prompt) generic folder icon + HKLM drive icons
# ----------------------------------------------------------------------------
# guid -> icon kind. Both the new (1709+) and the legacy GUID of each This PC folder are covered.
$script:ClsidIcons = @(
    @('{20D04FE0-3AEA-1069-A2D8-08002B30309D}', 'ThisPC'),
    @('{59031a47-3f72-44a7-89c5-5595fe6b30ee}', 'User'),
    @('{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}', 'Network'),
    @('{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}', 'ControlPanel'),
    @('{645FF040-5081-101B-9F08-00AA002F954E}', 'Recycle'),
    @('{679f85cb-0220-4080-b29b-5540cc05aab6}', 'QuickAccess'),
    @('{031E4825-7B94-4dc3-B131-E946B44C8DD5}', 'Libraries'),
    @('{018D5C66-4533-4307-9B53-224DE2ED1FE6}', 'OneDrive'),
    @('{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}', 'Objects3D'),
    @('{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}', 'Desktop'),
    @('{d3162b92-9365-467a-956b-92703aca08af}', 'Documents'),
    @('{A8CDFF1C-4878-43be-B5FD-F8091C1C60D0}', 'Documents'),
    @('{088e3905-0323-4b02-9826-5d99428e115f}', 'Downloads'),
    @('{374DE290-123F-4565-9164-39C4925E467B}', 'Downloads'),
    @('{3dfdf296-dbec-4fb4-81d1-6a3438bcf4de}', 'Music'),
    @('{1CF1260C-4DD0-4ebb-811F-33C572699FDE}', 'Music'),
    @('{24ad3ad4-a569-4530-98e1-ab02f9417aa8}', 'Pictures'),
    @('{3ADD1653-EB32-4cb0-BBD6-DFD23DF6AD53}', 'Pictures'),
    @('{f86fa3ab-70d2-4fc7-9c99-fcbf05467f3a}', 'Videos'),
    @('{A0953C92-50DC-43bf-BE83-3742FED03C9C}', 'Videos')
)
# Per-user class-level overrides: every folder, every drive and every ZIP archive in File Explorer.
$script:ExtraIconKeys = @(
    @('Software\Classes\Folder\DefaultIcon', 'Folder'),
    @('Software\Classes\Directory\DefaultIcon', 'Folder'),
    @('Software\Classes\Drive\DefaultIcon', 'Drive'),
    @('Software\Classes\CompressedFolder\DefaultIcon', 'Archive')
)
$script:FolderClsidKinds = @('Objects3D', 'Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')
$script:DrivesSub = 'Software\Classes\Applications\Explorer.exe\Drives'

function Get-M10FixedDriveLetters {
    $letters = @()
    try {
        foreach ($d in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) { $letters += $d.DeviceID.Substring(0, 1) }
    } catch {
        foreach ($d in [System.IO.DriveInfo]::GetDrives()) { if ($d.DriveType -eq 'Fixed') { $letters += $d.Name.Substring(0, 1) } }
    }
    return $letters
}

# Every registry key (relative to HKCU) that Modern 10 may write for icons.
function Get-M10IconKeyList([bool]$Folders = $true) {
    $list = @()
    foreach ($c in $script:ClsidIcons) {
        if ((-not $Folders) -and ($script:FolderClsidKinds -contains $c[1])) { continue }
        $list += [pscustomobject]@{ Sub = ('Software\Classes\CLSID\{0}\DefaultIcon' -f $c[0]); Kind = $c[1] }
        $list += [pscustomobject]@{ Sub = ('{0}\CLSID\{1}\DefaultIcon' -f $script:EXPSUB, $c[0]); Kind = $c[1] }
    }
    foreach ($e in $script:ExtraIconKeys) { $list += [pscustomobject]@{ Sub = $e[0]; Kind = $e[1] } }
    return $list
}

function Get-M10KeySnapshot([string]$SubKey) {
    $root = [Microsoft.Win32.Registry]::CurrentUser
    $cut = $SubKey.LastIndexOf('\')
    $parent = $SubKey.Substring(0, $cut)
    $parentKey = $root.OpenSubKey($parent)
    $parentExisted = [bool]$parentKey
    if ($parentKey) { $parentKey.Close() }

    $existed = $false; $vals = @()
    $k = $root.OpenSubKey($SubKey)
    if ($k) {
        $def = [string]$k.GetValue('', '')
        # A value that already points at Modern 10 is ours, not the user's original.
        if ($def -notlike '*\Modern10\*') {
            $existed = $true
            foreach ($n in $k.GetValueNames()) {
                $vals += [pscustomobject]@{
                    Name = $n; Kind = [string]$k.GetValueKind($n)
                    Data = [string]$k.GetValue($n, $null, 'DoNotExpandEnvironmentNames')
                }
            }
        }
        $k.Close()
    }
    return [pscustomobject]@{ SubKey = $SubKey; Existed = $existed; ParentExisted = $parentExisted; Values = @($vals) }
}

function Restore-M10KeySnapshot($Snap) {
    $root = [Microsoft.Win32.Registry]::CurrentUser
    if ($Snap.Existed) {
        $k = $root.CreateSubKey($Snap.SubKey)
        try {
            foreach ($n in @($k.GetValueNames())) { $k.DeleteValue($n, $false) }
            foreach ($v in @($Snap.Values)) {
                $kind = [Microsoft.Win32.RegistryValueKind]::String
                if ([string]$v.Kind -eq 'ExpandString') { $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString }
                $k.SetValue([string]$v.Name, [string]$v.Data, $kind)
            }
        } finally { $k.Close() }
    } else {
        $root.DeleteSubKeyTree($Snap.SubKey, $false)
        if (-not $Snap.ParentExisted) {
            $parent = $Snap.SubKey.Substring(0, $Snap.SubKey.LastIndexOf('\'))
            $pk = $root.OpenSubKey($parent)
            if ($pk) {
                $empty = ($pk.SubKeyCount -eq 0 -and $pk.ValueCount -eq 0)
                $pk.Close()
                if ($empty) { $root.DeleteSubKeyTree($parent, $false) }
            }
        }
    }
}

function Get-M10UserFolderList {
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
    $map['Objects3D'] = Join-Path $env:USERPROFILE '3D Objects'

    $list = @()
    foreach ($k in $map.Keys) {
        $path = $map[$k]
        if ($path -and (Test-Path -LiteralPath $path -PathType Container)) {
            $list += [pscustomobject]@{ Kind = $k; Path = $path }
        }
    }
    return $list
}

function Save-M10IconBackup($UserFolders) {
    $oldFolders = @()
    if (Test-Path -LiteralPath $script:IconBackupFile) {
        try {
            $old = Get-Content -LiteralPath $script:IconBackupFile -Raw | ConvertFrom-Json
            if ($old.Version -ge 2) { return }          # a v2 backup already holds the originals
            $oldFolders = @($old.UserFolders)           # v1 backup: keep its folder records
        } catch { }
    }

    $keys = foreach ($kk in (Get-M10IconKeyList $true)) { Get-M10KeySnapshot $kk.Sub }

    $folders = @($oldFolders)
    foreach ($u in $UserFolders) {
        if (@($folders | Where-Object { $_.Folder -eq $u.Path }).Count -gt 0) { continue }
        $ini = Join-Path $u.Path 'desktop.ini'
        $has = Test-Path -LiteralPath $ini -PathType Leaf
        $content = ''; $iattr = 0
        if ($has) {
            $i = Get-Item -LiteralPath $ini -Force
            $iattr = [int]$i.Attributes
            $content = [string](Get-Content -LiteralPath $ini -Raw)
            # drop a leftover Modern 10 IconResource line so we never "restore" our own icon
            $content = [regex]::Replace($content, '(?im)^\s*IconResource\s*=.*\\Modern10\\.*\r?\n?', '')
        }
        $folders += [pscustomobject]@{
            Folder = $u.Path; IniExisted = $has; Content = $content; IniAttr = $iattr
            FolderAttr = [int](Get-Item -LiteralPath $u.Path -Force).Attributes
        }
    }

    [pscustomobject]@{ Version = 2; Keys = @($keys); UserFolders = @($folders | Where-Object { $_ }) } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:IconBackupFile -Encoding UTF8
    Write-M10 'step' "Icon backup saved: $($script:IconBackupFile)"
}

# Writes every shell-namespace icon and returns how many entries were written.
function Set-M10SystemIcons([string]$Dir, [bool]$Folders) {
    $n = 0
    foreach ($c in $script:ClsidIcons) {
        if ((-not $Folders) -and ($script:FolderClsidKinds -contains $c[1])) { continue }
        $guid = $c[0]; $kind = $c[1]
        $subs = @(('Software\Classes\CLSID\{0}\DefaultIcon' -f $guid), ('{0}\CLSID\{1}\DefaultIcon' -f $script:EXPSUB, $guid))
        foreach ($sub in $subs) {
            if ($kind -eq 'Recycle') {
                Set-M10StringValue $sub ''      ('{0},0' -f (Join-Path $Dir 'RecycleEmpty.ico'))
                Set-M10StringValue $sub 'empty' ('{0},0' -f (Join-Path $Dir 'RecycleEmpty.ico'))
                Set-M10StringValue $sub 'full'  ('{0},0' -f (Join-Path $Dir 'RecycleFull.ico'))
            } else {
                Set-M10StringValue $sub '' ('{0},0' -f (Join-Path $Dir ($kind + '.ico')))
            }
            $n++
        }
    }
    foreach ($e in $script:ExtraIconKeys) {
        Set-M10StringValue $e[0] '' ('{0},0' -f (Join-Path $Dir ($e[1] + '.ico')))
        $n++
    }
    return $n
}

function Set-M10DriveIcons([string]$Dir) {
    $ico = '{0},0' -f (Join-Path $Dir 'Drive.ico')
    $count = 0
    foreach ($letter in (Get-M10FixedDriveLetters)) {
        Set-M10StringValue ('{0}\{1}\DefaultIcon' -f $script:DrivesSub, $letter) '' $ico
        $count++
    }
    return $count
}

function Remove-M10DriveIcons {
    $root = [Microsoft.Win32.Registry]::CurrentUser
    $dk = $root.OpenSubKey($script:DrivesSub)
    if (-not $dk) { return }
    $names = @($dk.GetSubKeyNames()); $dk.Close()
    foreach ($n in $names) {
        $sub = '{0}\{1}\DefaultIcon' -f $script:DrivesSub, $n
        $cur = [string](Get-M10StringValue $sub '')
        if ($cur -like '*\Modern10\*') { $root.DeleteSubKeyTree(('{0}\{1}' -f $script:DrivesSub, $n), $false) }
    }
}

function Set-M10FolderIconIni([string]$Folder, [string]$Ico) {
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

# Reads everything back and reports how many icon entries really are in place.
function Test-M10IconsApplied([string]$Dir, [bool]$Folders) {
    $bad = @(); $ok = 0
    foreach ($c in $script:ClsidIcons) {
        if ((-not $Folders) -and ($script:FolderClsidKinds -contains $c[1])) { continue }
        $file = $c[1]; if ($file -eq 'Recycle') { $file = 'RecycleEmpty' }
        $want = '{0},0' -f (Join-Path $Dir ($file + '.ico'))
        foreach ($sub in @(('Software\Classes\CLSID\{0}\DefaultIcon' -f $c[0]), ('{0}\CLSID\{1}\DefaultIcon' -f $script:EXPSUB, $c[0]))) {
            if ([string](Get-M10StringValue $sub '') -eq $want) { $ok++ } else { $bad += $sub }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $Dir ($file + '.ico')))) { $bad += "missing file $file.ico" }
    }
    foreach ($e in $script:ExtraIconKeys) {
        $want = '{0},0' -f (Join-Path $Dir ($e[1] + '.ico'))
        if ([string](Get-M10StringValue $e[0] '') -eq $want) { $ok++ } else { $bad += $e[0] }
    }
    foreach ($letter in (Get-M10FixedDriveLetters)) {
        $want = '{0},0' -f (Join-Path $Dir 'Drive.ico')
        if ([string](Get-M10StringValue ('{0}\{1}\DefaultIcon' -f $script:DrivesSub, $letter) '') -eq $want) { $ok++ } else { $bad += "drive $letter" }
    }
    foreach ($b in $bad) { Write-Warn "Icon entry not in place: $b" }
    Write-Step "Icon registry check: $ok entries verified, $($bad.Count) problem(s)."
    return $bad.Count
}

function Restore-M10IconState {
    $bk = $null
    if (Test-Path -LiteralPath $script:IconBackupFile) {
        try { $bk = Get-Content -LiteralPath $script:IconBackupFile -Raw | ConvertFrom-Json } catch { }
    }
    $snaps = @()
    if ($bk -and $bk.Version -ge 2) { $snaps = @($bk.Keys) }

    foreach ($kk in (Get-M10IconKeyList $true)) {
        $snap = @($snaps | Where-Object { $_.SubKey -eq $kk.Sub }) | Select-Object -First 1
        if ($snap) {
            Restore-M10KeySnapshot $snap
        } else {
            $cur = [string](Get-M10StringValue $kk.Sub '')
            if ($cur -like '*\Modern10\*') {
                $snap2 = [pscustomobject]@{ SubKey = $kk.Sub; Existed = $false; ParentExisted = $false; Values = @() }
                Restore-M10KeySnapshot $snap2
            }
        }
    }
    Remove-M10DriveIcons

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
            } catch { Write-M10 'step' "Could not restore $($u.Folder): $($_.Exception.Message)" }
        }
    }
    Remove-Item -LiteralPath $script:IconBackupFile -ErrorAction SilentlyContinue
}

# Explorer keeps rendered icons in cache files; they can only be deleted while Explorer is stopped.
function Clear-M10IconCache {
    $ex = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    Get-ChildItem -LiteralPath $ex -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'IconCache.db') -Force -ErrorAction SilentlyContinue
    Write-M10 'step' 'Icon cache cleared'
}

function Update-M10ShellIcons {
    # SHCNE_ASSOCCHANGED, SHCNF_IDLIST | SHCNF_FLUSH
    [M10Native]::SHChangeNotify(0x08000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
    try { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\ie4uinit.exe') -ArgumentList '-show' -WindowStyle Hidden -Wait } catch { }
}

# ----------------------------------------------------------------------------
# Taskbar (edge: 0 left, 1 top, 2 right, 3 bottom;  behaviour: auto-hide flag = bit 0 of byte 8)
# ----------------------------------------------------------------------------
$script:EdgeNames = @{ 0 = 'Left'; 1 = 'Top'; 2 = 'Right'; 3 = 'Bottom' }

# AutoHide: -1 keep, 0 always visible, 1 auto-hide
function Set-M10TaskbarLayout([int]$Edge, [int]$AutoHide = -1) {
    $changed = 0
    foreach ($k in 'StuckRects3', 'MMStuckRects3') {
        $p = "$EXP\$k"
        if (-not (Test-Path -LiteralPath $p)) { Write-M10 'step' "Key not found: $p"; continue }
        $item = Get-Item -LiteralPath $p
        foreach ($n in $item.GetValueNames()) {
            if ($item.GetValueKind($n) -ne 'Binary') { continue }
            if ($k -eq 'StuckRects3' -and $n -ne 'Settings') { continue }
            $b = [byte[]]$item.GetValue($n)
            if ($b.Length -gt 12) {
                if ($Edge -ge 0) { $b[12] = [byte]$Edge }
                if ($AutoHide -ge 0) { $b[8] = [byte](($b[8] -band 0xFE) -bor $AutoHide) }
                Set-ItemProperty -LiteralPath $p -Name $n -Value $b -Type Binary
                $changed++
            }
        }
    }
    if ($changed -eq 0) { throw 'Taskbar layout key (StuckRects3) was not found or is empty.' }
}

function Get-M10TaskbarRegistry {
    try {
        $s = (Get-ItemProperty -LiteralPath "$EXP\StuckRects3" -ErrorAction Stop).Settings
        if ($s -and $s.Length -gt 12) { return [pscustomobject]@{ Edge = [int]$s[12]; AutoHide = ([int]$s[8] -band 1) } }
    } catch { }
    return [pscustomobject]@{ Edge = -1; AutoHide = -1 }
}

function Write-M10TaskbarRegistry([int]$Edge, [int]$Small, [int]$AutoHide) {
    if ($Small -ge 0) { Set-M10Reg "$EXP\Advanced" 'TaskbarSmallIcons' $Small 'DWord' }
    Set-M10TaskbarLayout $Edge $AutoHide
}

function Test-M10TaskbarRegistry([int]$Edge, [int]$Small, [int]$AutoHide) {
    $r = Get-M10TaskbarRegistry
    if ($r.Edge -ne $Edge) { return $false }
    if ($AutoHide -ge 0 -and $r.AutoHide -ne $AutoHide) { return $false }
    if ($Small -ge 0) {
        $v = Get-ItemProperty -LiteralPath "$EXP\Advanced" -Name 'TaskbarSmallIcons' -ErrorAction SilentlyContinue
        if (-not $v -or [int]$v.TaskbarSmallIcons -ne $Small) { return $false }
    }
    return $true
}

# Measures the real, live taskbar on the primary monitor.
function Get-M10LiveTaskbar {
    $s = [System.Windows.Forms.Screen]::PrimaryScreen
    $b = $s.Bounds; $w = $s.WorkingArea
    if     ($w.Top -gt $b.Top)       { $e = 'Top';    $t = $w.Top - $b.Top }
    elseif ($w.Bottom -lt $b.Bottom) { $e = 'Bottom'; $t = $b.Bottom - $w.Bottom }
    elseif ($w.Left -gt $b.Left)     { $e = 'Left';   $t = $w.Left - $b.Left }
    elseif ($w.Right -lt $b.Right)   { $e = 'Right';  $t = $b.Right - $w.Right }
    else                             { $e = 'Unknown (auto-hide?)'; $t = 0 }
    return [pscustomobject]@{ Edge = $e; Thickness = $t }
}

function Stop-M10Explorer {
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ((Get-Process -Name explorer -ErrorAction SilentlyContinue) -and $sw.Elapsed.TotalSeconds -lt 10) {
        Start-Sleep -Milliseconds 200
    }
}

function Start-M10Explorer {
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

# Writes the taskbar registry, restarts Explorer (clearing the icon cache), verifies registry AND live taskbar.
function Invoke-M10TaskbarApply {
    param([int]$Edge, [int]$Small, [int]$AutoHide, [bool]$Restart)

    Write-M10TaskbarRegistry $Edge $Small $AutoHide
    Send-M10SettingChange 'TraySettings'
    if (-not $Restart) {
        $script:Report['Taskbar'] = 'Saved - sign out and back in to apply'
        if ($script:ClearIcons) { $script:Report['Icons'] = "$($script:Report['Icons']) - sign out/in or restart Explorer to see them" }
        return
    }

    $expected = $script:EdgeNames[$Edge]
    $ok = $false
    for ($attempt = 1; $attempt -le 3 -and -not $ok; $attempt++) {
        Write-Step "Restarting Explorer (attempt $attempt of 3)..."
        Stop-M10Explorer
        if ($script:ClearIcons) { Clear-M10IconCache }
        Write-M10TaskbarRegistry $Edge $Small $AutoHide      # written while no shell is running
        Start-M10Explorer
        Start-Sleep -Seconds 3
        $regOk = Test-M10TaskbarRegistry $Edge $Small $AutoHide
        $live = Get-M10LiveTaskbar
        Write-M10 'step' ("Attempt {0}: registryOk={1} live={2} thickness={3}px" -f $attempt, $regOk, $live.Edge, $live.Thickness)
        $ok = $regOk -and ($live.Edge -eq $expected -or $live.Edge -like 'Unknown*')
    }
    if ($script:ClearIcons) { Update-M10ShellIcons }

    $live = Get-M10LiveTaskbar
    if ($ok) {
        $script:Report['Taskbar'] = ('OK - {0}, {1}px thick' -f $live.Edge, $live.Thickness)
        Write-Ok ("Taskbar is now at the {0} ({1}px)" -f $live.Edge.ToLower(), $live.Thickness)
    } else {
        $script:Report['Taskbar'] = ('Saved, but live taskbar is {0} - sign out and back in' -f $live.Edge)
        Write-Warn 'Settings were saved but Explorer did not pick them up. Sign out and back in.'
    }
}

# ----------------------------------------------------------------------------
# Wallpaper and lock screen artwork: soft "aurora" glows on a deep gradient
# ----------------------------------------------------------------------------
function Get-M10Col([string]$Hex, [int]$Alpha = 255) {
    $h = $Hex.TrimStart('#')
    return [System.Drawing.Color]::FromArgb($Alpha,
        [Convert]::ToInt32($h.Substring(0, 2), 16),
        [Convert]::ToInt32($h.Substring(2, 2), 16),
        [Convert]::ToInt32($h.Substring(4, 2), 16))
}

function Add-M10Glow($G, [single]$Cx, [single]$Cy, [single]$R, $Color) {
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

# name -> definition. Glows: colour, x, y, radius (fractions of the width), alpha. Waves: y, amplitude, phase, c1, a1, c2, a2.
$script:M10WallpaperStyles = @('Aurora', 'Waves', 'Sunset', 'Ocean', 'Emerald', 'Graphite', 'Nebula', 'Rose', 'Midnight', 'Citrus', 'Arctic', 'Dunes', 'Lagoon')
function Get-M10WallpaperStyleNames { return $script:M10WallpaperStyles }

function Get-M10WallpaperStyleDef([string]$Style, [string]$Mode) {
    $dk = ($Mode -eq 'Dark')
    switch ($Style) {
        'Waves' {
            if ($dk) { return @{ Bg = @('#070B1F', '#1B0F3D'); Grain = 3; Edge = 55
                Glows = @(@('#0A84FF', 0.20, 0.25, 0.42, 200), @('#7D3CFF', 0.78, 0.18, 0.40, 190), @('#FF2D95', 0.62, 0.92, 0.38, 150), @('#30D5C8', 0.10, 0.95, 0.28, 90), @('#5E5CE6', 0.50, 0.50, 0.50, 110))
                Waves = @(@(0.62, 0.070, 0.6, '#8E7BFF', 110, '#1B0F4F', 40), @(0.74, 0.060, 2.1, '#3C9CFF', 100, '#0B1A5C', 30), @(0.86, 0.045, 3.7, '#FF5FB0', 90, '#2A0A44', 30)) } }
            return @{ Bg = @('#EAF1FF', '#FDEFF6'); Grain = 2; Edge = 210
                Glows = @(@('#5AB0FF', 0.20, 0.25, 0.42, 210), @('#B79CFF', 0.78, 0.18, 0.40, 200), @('#FF9CC4', 0.62, 0.92, 0.38, 190), @('#FFC999', 0.10, 0.95, 0.30, 170), @('#FFFFFF', 0.50, 0.45, 0.45, 120))
                Waves = @(@(0.62, 0.070, 0.6, '#FFFFFF', 170, '#CFE0FF', 60), @(0.74, 0.060, 2.1, '#FFD6EA', 150, '#E3D6FF', 50), @(0.86, 0.045, 3.7, '#FFFFFF', 190, '#BFD8FF', 70)) }
        }
        'Sunset' {
            if ($dk) { return @{ Bg = @('#1A0B2E', '#2B0F2E'); Grain = 3; Edge = 0; Waves = @()
                Glows = @(@('#7D3CFF', 0.20, 0.25, 0.50, 200), @('#FF6B3D', 0.80, 0.85, 0.50, 210), @('#FF2D95', 0.45, 0.97, 0.45, 190), @('#FFB36B', 0.92, 0.55, 0.30, 110), @('#0B0618', 0.03, 0.02, 0.40, 200)) } }
            return @{ Bg = @('#FFF1E6', '#FDE8F4'); Grain = 2; Edge = 0; Waves = @()
                Glows = @(@('#C3A2FF', 0.20, 0.25, 0.50, 190), @('#FFB07A', 0.80, 0.85, 0.50, 215), @('#FF9CC4', 0.45, 0.97, 0.45, 200), @('#FFD9B8', 0.92, 0.50, 0.30, 160), @('#FFFFFF', 0.30, 0.55, 0.35, 120)) }
        }
        'Ocean' {
            if ($dk) { return @{ Bg = @('#041428', '#06263A'); Grain = 3; Edge = 0; Waves = @()
                Glows = @(@('#0A84FF', 0.25, 0.30, 0.50, 205), @('#30D5C8', 0.72, 0.15, 0.38, 165), @('#1B4DB0', 0.60, 0.85, 0.50, 200), @('#021018', 0.02, 0.98, 0.45, 230)) } }
            return @{ Bg = @('#E6F6FF', '#E9F0FF'); Grain = 2; Edge = 0; Waves = @()
                Glows = @(@('#7DD3FF', 0.25, 0.30, 0.50, 205), @('#8EE8DC', 0.72, 0.15, 0.38, 170), @('#8FB3FF', 0.60, 0.85, 0.50, 195), @('#FFFFFF', 0.40, 0.55, 0.40, 130)) }
        }
        'Emerald' {
            if ($dk) { return @{ Bg = @('#06130F', '#0A1F1A'); Grain = 3; Edge = 0; Waves = @()
                Glows = @(@('#1FBF8F', 0.25, 0.30, 0.50, 185), @('#2A7F5A', 0.80, 0.75, 0.50, 200), @('#6FD6A0', 0.60, 0.05, 0.30, 110), @('#02080A', 0.03, 0.99, 0.45, 230)) } }
            return @{ Bg = @('#EAF8F1', '#F3FBF6'); Grain = 2; Edge = 0; Waves = @()
                Glows = @(@('#8FE0BD', 0.25, 0.30, 0.50, 200), @('#B7EBCB', 0.80, 0.75, 0.50, 200), @('#CFF3E4', 0.60, 0.05, 0.30, 160), @('#FFFFFF', 0.40, 0.55, 0.40, 130)) }
        }
        'Graphite' {
            if ($dk) { return @{ Bg = @('#121316', '#1C1E24'); Grain = 3; Edge = 0; Waves = @()
                Glows = @(@('#3A4A6B', 0.25, 0.30, 0.50, 170), @('#5A5F70', 0.80, 0.70, 0.50, 120), @('#2B3350', 0.60, 0.10, 0.35, 140), @('#0A0B0D', 0.03, 0.99, 0.50, 230)) } }
            return @{ Bg = @('#F2F3F5', '#E6E8EC'); Grain = 2; Edge = 0; Waves = @()
                Glows = @(@('#B8C2D8', 0.25, 0.30, 0.50, 190), @('#D5D9E2', 0.80, 0.70, 0.50, 170), @('#C9CFDB', 0.60, 0.10, 0.35, 150), @('#FFFFFF', 0.40, 0.60, 0.40, 140)) }
        }
        'Nebula' {
            if ($dk) { return @{ Bg = @('#0B0620', '#1E0A33'); Grain = 3; Edge = 0; Waves = @()
                Glows = @(@('#B03CFF', 0.25, 0.3, 0.5, 200), @('#FF3CA8', 0.75, 0.2, 0.38, 170), @('#3C5CFF', 0.6, 0.85, 0.5, 190), @('#0A0418', 0.03, 0.98, 0.45, 230)) } }
            return @{ Bg = @('#F4EAFF', '#FFE9F6'); Grain = 2; Edge = 0; Waves = @()
                Glows = @(@('#D1A3FF', 0.25, 0.3, 0.5, 200), @('#FFA3D1', 0.75, 0.2, 0.38, 190), @('#A3B8FF', 0.6, 0.85, 0.5, 190), @('#FFFFFF', 0.4, 0.55, 0.4, 130)) }
        }
        'Rose' {
            if ($dk) { return @{ Bg = @('#1F0B16', '#2E1022'); Grain = 3; Edge = 0; Waves = @()
                Glows = @(@('#FF5FA0', 0.22, 0.3, 0.5, 170), @('#C23C7A', 0.8, 0.8, 0.5, 190), @('#FFA3C4', 0.6, 0.05, 0.3, 100), @('#0F0509', 0.03, 0.99, 0.45, 230)) } }
            return @{ Bg = @('#FFEFF4', '#FFE3EC'); Grain = 2; Edge = 0; Waves = @()
                Glows = @(@('#FFB3CF', 0.22, 0.3, 0.5, 200), @('#FFC9DC', 0.8, 0.8, 0.5, 200), @('#FFD9E6', 0.6, 0.05, 0.3, 170), @('#FFFFFF', 0.4, 0.55, 0.4, 130)) }
        }
        'Midnight' {
            if ($dk) { return @{ Bg = @('#05070F', '#0B1226'); Grain = 3; Edge = 0; Waves = @()
                Glows = @(@('#1F3A8A', 0.25, 0.3, 0.5, 190), @('#0E7490', 0.78, 0.75, 0.45, 150), @('#312E81', 0.55, 0.1, 0.35, 150), @('#02030A', 0.03, 0.99, 0.5, 235)) } }
            return @{ Bg = @('#E9EDF8', '#DCE3F4'); Grain = 2; Edge = 0; Waves = @()
                Glows = @(@('#A9B9E8', 0.25, 0.3, 0.5, 200), @('#A5D8E6', 0.78, 0.75, 0.45, 180), @('#C0BEF0', 0.55, 0.1, 0.35, 170), @('#FFFFFF', 0.4, 0.55, 0.4, 130)) }
        }
        'Citrus' {
            if ($dk) { return @{ Bg = @('#101A06', '#1B2606'); Grain = 3; Edge = 0; Waves = @()
                Glows = @(@('#A3E635', 0.25, 0.3, 0.5, 150), @('#FACC15', 0.8, 0.75, 0.45, 150), @('#22C55E', 0.6, 0.08, 0.3, 120), @('#060A02', 0.03, 0.99, 0.5, 230)) } }
            return @{ Bg = @('#F7FFE6', '#FFFBE0'); Grain = 2; Edge = 0; Waves = @()
                Glows = @(@('#D4F58A', 0.25, 0.3, 0.5, 200), @('#FFE98A', 0.8, 0.75, 0.45, 200), @('#B8F0A8', 0.6, 0.08, 0.3, 170), @('#FFFFFF', 0.4, 0.55, 0.4, 130)) }
        }
        'Arctic' {
            if ($dk) { return @{ Bg = @('#0A1620', '#10222F'); Grain = 3; Edge = 0; Waves = @()
                Glows = @(@('#7DD3FC', 0.25, 0.3, 0.5, 130), @('#A5F3FC', 0.78, 0.2, 0.35, 110), @('#38BDF8', 0.6, 0.85, 0.5, 140), @('#040B10', 0.03, 0.99, 0.5, 230)) } }
            return @{ Bg = @('#F0FAFF', '#E4F3FB'); Grain = 2; Edge = 0; Waves = @()
                Glows = @(@('#C2EBFF', 0.25, 0.3, 0.5, 200), @('#DDF8FF', 0.78, 0.2, 0.35, 190), @('#B3DDF5', 0.6, 0.85, 0.5, 190), @('#FFFFFF', 0.4, 0.55, 0.4, 140)) }
        }
        'Dunes' {
            if ($dk) { return @{ Bg = @('#1A0F08', '#2B1A0E'); Grain = 3; Edge = 40; Waves = @(@(0.7, 0.06, 0.8, '#B45309', 90, '#3B1E0B', 40), @(0.84, 0.05, 2.6, '#92400E', 100, '#2A1608', 40))
                Glows = @(@('#F59E0B', 0.25, 0.3, 0.5, 150), @('#C2410C', 0.8, 0.8, 0.5, 170), @('#FDBA74', 0.6, 0.05, 0.3, 100), @('#0A0502', 0.03, 0.99, 0.5, 230)) } }
            return @{ Bg = @('#FFF4E5', '#FFE8D0'); Grain = 2; Edge = 160; Waves = @(@(0.7, 0.06, 0.8, '#FFE0B0', 150, '#FFD0A0', 60), @(0.84, 0.05, 2.6, '#FFC99A', 150, '#FFEAD0', 60))
                Glows = @(@('#FFD099', 0.25, 0.3, 0.5, 200), @('#FFB98A', 0.8, 0.8, 0.5, 200), @('#FFE3B8', 0.6, 0.05, 0.3, 170), @('#FFFFFF', 0.4, 0.55, 0.4, 130)) }
        }
        'Lagoon' {
            if ($dk) { return @{ Bg = @('#021A1A', '#06292F'); Grain = 3; Edge = 40; Waves = @(@(0.66, 0.06, 0.5, '#2DD4BF', 90, '#06403F', 40), @(0.8, 0.05, 2.3, '#38BDF8', 90, '#06324A', 40))
                Glows = @(@('#14B8A6', 0.25, 0.3, 0.5, 170), @('#0EA5E9', 0.78, 0.2, 0.38, 150), @('#115E59', 0.6, 0.85, 0.5, 180), @('#010C0C', 0.03, 0.99, 0.5, 230)) } }
            return @{ Bg = @('#E6FFFA', '#E3F6FF'); Grain = 2; Edge = 160; Waves = @(@(0.66, 0.06, 0.5, '#FFFFFF', 170, '#B6F2E6', 60), @(0.8, 0.05, 2.3, '#E0F7FF', 160, '#B8E4F8', 60))
                Glows = @(@('#99F6E4', 0.25, 0.3, 0.5, 200), @('#BAE6FD', 0.78, 0.2, 0.38, 190), @('#A7F3D0', 0.6, 0.85, 0.5, 190), @('#FFFFFF', 0.4, 0.55, 0.4, 130)) }
        }
        default {
            # Aurora: deep navy and violet with a blue, a teal and a purple light
            if ($dk) { return @{ Bg = @('#09112E', '#170C32'); Grain = 3; Edge = 0; Waves = @()
                Glows = @(@('#2650BE', 0.24, 0.30, 0.50, 225), @('#27769A', 0.56, 0.05, 0.34, 185), @('#7F30B2', 0.82, 0.74, 0.50, 225), @('#3D1B6C', 0.58, 0.42, 0.34, 150), @('#0B0822', 0.03, 0.99, 0.46, 235), @('#1B103C', 0.98, 0.04, 0.30, 160)) } }
            return @{ Bg = @('#EAF1FF', '#FBEFF7'); Grain = 2; Edge = 0; Waves = @()
                Glows = @(@('#7DB8FF', 0.24, 0.30, 0.50, 215), @('#A5E1EA', 0.56, 0.05, 0.34, 170), @('#C3A2FF', 0.82, 0.74, 0.50, 215), @('#FFB7D5', 0.58, 0.45, 0.34, 140), @('#FFD9B8', 0.03, 0.99, 0.40, 190), @('#FFFFFF', 0.98, 0.04, 0.30, 150)) }
        }
    }
}

function Add-M10Wave($G, [int]$W, [int]$H, [double]$Y0, [double]$Amp, [double]$Phase, $C1, $C2, $EdgeColor) {
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

# Returns a System.Drawing.Bitmap (the caller disposes it).
function New-M10GlassBitmap {
    param([int]$W, [int]$H, [string]$Mode, [string]$Kind, [string]$Style = 'Aurora', [bool]$Grain = $true)

    $dark = ($Mode -eq 'Dark')
    $lock = ($Kind -eq 'Lock')
    $def = Get-M10WallpaperStyleDef $Style $Mode

    $bmp = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.CompositingQuality = 'HighQuality'

    $rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
    $base = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, (Get-M10Col $def.Bg[0]), (Get-M10Col $def.Bg[1]), [single]45)
    $g.FillRectangle($base, $rect)
    $base.Dispose()

    foreach ($gl in $def.Glows) {
        $cx = $gl[1]; $cy = $gl[2]
        if ($lock) { $cx = 1 - $cx; $cy = [Math]::Min(0.98, $cy + 0.04) }   # mirrored, so the lock screen differs from the wallpaper
        Add-M10Glow $g ([single]($cx * $W)) ([single]($cy * $H)) ([single]($gl[3] * $W)) (Get-M10Col $gl[0] $gl[4])
    }

    foreach ($wv in @($def.Waves)) {
        $y0 = $wv[0]; $ph = $wv[2]
        if ($lock) { $y0 = $y0 - 0.06; $ph = $ph + 1.4 }
        Add-M10Wave $g $W $H ($y0 * $H) ($wv[1] * $H) $ph (Get-M10Col $wv[3] $wv[4]) (Get-M10Col $wv[5] $wv[6]) (Get-M10Col '#FFFFFF' $def.Edge)
    }

    if ($lock -and $dark) {
        $ov = New-Object System.Drawing.SolidBrush((Get-M10Col '#000000' 40))
        $g.FillRectangle($ov, $rect)
        $ov.Dispose()
    }

    $g.Dispose()
    if ($Grain) { [M10Native]::AddGrain($bmp, [int]$def.Grain) }
    return , $bmp
}

function New-M10GlassImage {
    param([string]$Path, [int]$W, [int]$H, [string]$Mode, [string]$Kind, [string]$Style = 'Aurora')
    $bmp = New-M10GlassBitmap -W $W -H $H -Mode $Mode -Kind $Kind -Style $Style -Grain $true
    try { $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
}

# Sets the wallpaper in every way Windows understands, then reads it back.
function Set-M10Wallpaper([string]$Path) {
    Set-M10Reg 'HKCU:\Control Panel\Desktop' 'WallpaperStyle' '10' 'String'
    Set-M10Reg 'HKCU:\Control Panel\Desktop' 'TileWallpaper'  '0'  'String'
    Set-M10Reg "$EXP\Wallpapers" 'BackgroundType' 0 'DWord'          # 0 = picture (turns a slideshow off)

    foreach ($pol in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System',
                       'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System',
                       'HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop')) {
        $v = Get-ItemProperty -LiteralPath $pol -Name 'Wallpaper' -ErrorAction SilentlyContinue
        if ($v -and $v.Wallpaper) { Write-Warn "A policy sets the wallpaper ($pol). It can override this change." }
    }

    $themes = Join-Path $env:APPDATA 'Microsoft\Windows\Themes'
    Remove-Item -LiteralPath (Join-Path $themes 'TranscodedWallpaper') -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath (Join-Path $themes 'CachedFiles') -Force -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $err = [M10Wall]::Set($Path)
    if ($err) { Write-M10 'step' "Desktop wallpaper COM call: $err" }
    [void][M10Native]::SystemParametersInfo(0x14, 0, $Path, 3)
    Start-Sleep -Milliseconds 700

    $cur = [M10Native]::GetWallpaper()
    $reg = [string](Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper' -ErrorAction SilentlyContinue).Wallpaper
    Write-M10 'step' "Wallpaper check: system says '$cur', registry says '$reg'"
    if (($cur -ine $Path) -and ($reg -ine $Path)) {
        throw "Windows did not accept the wallpaper (it still reports '$cur')."
    }
}

# ----------------------------------------------------------------------------
# Build the options object the GUI passes in
# ----------------------------------------------------------------------------
function New-M10Options {
    return [ordered]@{
        Theme = 'Dark'; Position = 'Top'; IconSize = 'Small'; Behavior = 'Keep'
        WallpaperStyle = 'Aurora'; LockStyle = 'Match'; CustomWallpaper = ''; IconTheme = 'Glass'
        Wallpaper = $true; LockScreen = $true; RestartExplorer = $true
        SystemIcons = $true; FolderIcons = $true; ProfileIcons = $true; GenericFolder = $true
    }
}

# ----------------------------------------------------------------------------
# APPLY
# ----------------------------------------------------------------------------
function Invoke-M10Apply($Opt) {
    $ErrorActionPreference = 'Stop'
    $script:Report = [ordered]@{}
    $script:ClearIcons = $false
    Initialize-M10Native

    $Theme = [string]$Opt.Theme
    $tag = $Theme.ToLower()
    $edgeValue = 1; if ($Opt.Position -eq 'Bottom') { $edgeValue = 3 }
    $small = -1; if ($Opt.IconSize -eq 'Small') { $small = 1 } elseif ($Opt.IconSize -eq 'Default') { $small = 0 }
    $autoHide = -1; if ($Opt.Behavior -eq 'AutoHide') { $autoHide = 1 } elseif ($Opt.Behavior -eq 'Show') { $autoHide = 0 }

    Write-M10 'step' '================ Modern 10 run started ================'
    try {
        $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
        Write-M10 'step' "Windows build $build, PowerShell $($PSVersionTable.PSVersion)"
        if ($build -ge 22000) { Write-Warn "Windows 11 detected (build $build). Modern 10 is made for Windows 10." }
    } catch { }
    Write-Step ("Applying: {0} theme, taskbar {1}, icon size {2}, behaviour {3}" -f $Theme, $Opt.Position.ToLower(), $Opt.IconSize, $Opt.Behavior)

    Invoke-M10Stage 'Backup' { Save-M10Backup }

    Invoke-M10Stage 'Theme and glass' {
        $light = 0; if ($Theme -eq 'Light') { $light = 1 }
        $pers = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        Set-M10Reg $pers 'AppsUseLightTheme'    $light 'DWord'
        Set-M10Reg $pers 'SystemUsesLightTheme' $light 'DWord'
        Set-M10Reg $pers 'EnableTransparency'   1      'DWord'
        Set-M10Reg $pers 'ColorPrevalence'      0      'DWord'
        if ($Theme -eq 'Dark') { $acc = Get-M10AccentDword 10 132 255 } else { $acc = Get-M10AccentDword 0 122 255 }
        Set-M10Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'AccentColor'     $acc 'DWord'
        Set-M10Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorPrevalence' 0    'DWord'
        Set-M10Reg "$EXP\Accent" 'AccentColorMenu' $acc 'DWord'
        Set-M10Reg "$EXP\Accent" 'StartColorMenu'  $acc 'DWord'
        Write-Ok "$Theme mode, transparency and blue accent set"
    }

    Invoke-M10Stage 'Taskbar tidy-up' {
        $adv = "$EXP\Advanced"
        Set-M10Reg $adv 'TaskbarGlomLevel'    0 'DWord'
        Set-M10Reg $adv 'ShowTaskViewButton'  0 'DWord'
        Set-M10Reg $adv 'ShowCortanaButton'   0 'DWord'
        Set-M10Reg $adv 'ListviewAlphaSelect' 1 'DWord'
        Set-M10Reg $adv 'ListviewShadow'      1 'DWord'
        Set-M10Reg $adv 'TaskbarAnimations'   1 'DWord'
        Set-M10Reg "$adv\People" 'PeopleBand' 0 'DWord'
        Set-M10Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1 'DWord'
        Set-M10Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds'  'ShellFeedsTaskbarViewMode' 2 'DWord'
        Write-Ok 'Taskbar decluttered (icons only, search as icon)'
    }

    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $W = [int]$b.Width; $H = [int]$b.Height

    $style = [string]$Opt.WallpaperStyle
    if (-not $style) { $style = 'Aurora' }
    $script:WallpaperFile = $null

    if ($Opt.Wallpaper) {
        Invoke-M10Stage 'Wallpaper' {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            if ($style -eq 'Custom') {
                $src = [string]$Opt.CustomWallpaper
                if (-not $src -or -not (Test-Path -LiteralPath $src)) { throw 'The chosen wallpaper image was not found.' }
                $wp = Join-Path $script:DataDir ('wallpaper-custom-{0}{1}' -f $stamp, [System.IO.Path]::GetExtension($src))
                Copy-Item -LiteralPath $src -Destination $wp -Force
                Write-Step 'Using your own image as the wallpaper...'
            } else {
                Write-Step "Drawing the $style wallpaper ($W x $H)..."
                $wp = Join-Path $script:DataDir ('wallpaper-{0}-{1}-{2}.png' -f $tag, $style.ToLower(), $stamp)
                New-M10GlassImage -Path $wp -W $W -H $H -Mode $Theme -Kind 'Wallpaper' -Style $style
            }
            Set-M10Wallpaper $wp
            $script:WallpaperFile = $wp
            Get-ChildItem -LiteralPath $script:DataDir -Filter 'wallpaper-*' -File |
                Where-Object { $_.FullName -ne $wp } | Remove-Item -ErrorAction SilentlyContinue
            Write-Ok "Wallpaper applied ($style)"
            $script:Report['Wallpaper'] = "OK - $style"
        }
    }

    if ($Opt.LockScreen) {
        Invoke-M10Stage 'Lock screen' {
            Write-Step "Drawing the lock screen ($W x $H)..."
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $lockName = "lockscreen-$tag-$stamp.png"
            $lp = Join-Path $script:DataDir $lockName
            $lockStyle = [string]$Opt.LockStyle
            if (-not $lockStyle -or $lockStyle -eq 'Match') { $lockStyle = $style }
            if ($lockStyle -eq 'Custom' -and $Opt.CustomWallpaper -and (Test-Path -LiteralPath ([string]$Opt.CustomWallpaper))) {
                $bytes = [System.IO.File]::ReadAllBytes([string]$Opt.CustomWallpaper)
                $ms = New-Object System.IO.MemoryStream(, $bytes)
                $img = [System.Drawing.Image]::FromStream($ms)
                try { $img.Save($lp, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $img.Dispose(); $ms.Dispose() }
            } else {
                if ($lockStyle -eq 'Custom') { $lockStyle = 'Aurora' }
                New-M10GlassImage -Path $lp -W $W -H $H -Mode $Theme -Kind 'Lock' -Style $lockStyle
            }

            if (Test-M10LockOverride) {
                Write-Step 'Removing an older Modern 10 lock screen override (UAC prompt)...'
                try { [void](Invoke-M10Elevated 'RemoveLock') } catch { Write-Warn $_.Exception.Message }
            }

            $done = $false
            try {
                $applied = Set-M10LockScreenUser $lp
                Write-Ok 'Lock screen applied via the Windows lock screen API'
                Write-M10 'step' "LockScreen.OriginalImageFile = $applied"
                $script:Report['Lock screen'] = 'OK - per-user API'
                $done = $true
            } catch {
                Write-Warn "Per-user API failed: $($_.Exception.Message)"
            }
            if (-not $done) {
                Write-Step 'Trying the machine-level method (UAC prompt)...'
                $code = Invoke-M10Elevated 'SetLock' $Theme $lockName
                if ($code -ne 0) { throw "Machine-level method failed (exit code $code). See the log." }
                Write-Ok 'Lock screen applied via machine-level settings'
                $script:Report['Lock screen'] = 'OK - machine-level (set Background to Picture if unchanged)'
            }
            Get-ChildItem -LiteralPath $script:DataDir -Filter 'lockscreen-*.png' |
                Where-Object { $_.FullName -ne $lp } | Remove-Item -ErrorAction SilentlyContinue
            Write-Step 'Preview it with Win+L.'
        }
    }

    $itag = ([string]$Opt.IconTheme).ToLower(); if (-not $itag) { $itag = 'glass' }
    $iconTheme = [string]$Opt.IconTheme; if (-not $iconTheme) { $iconTheme = 'Glass' }
    $iconDir = Join-Path $script:DataDir "icons-$tag-$itag"
    if ($Opt.SystemIcons) {
        Invoke-M10Stage 'Icons' {
            Write-Step ('Drawing the {0} icon theme: {1} icons at 7 sizes each (this takes a few seconds)...' -f $iconTheme, $script:M10IconKinds.Count)
            New-M10IconSet -Dir $iconDir -Theme $Theme -IconTheme $iconTheme

            $userFolders = @()
            if ($Opt.ProfileIcons) { $userFolders = @(Get-M10UserFolderList) }
            Save-M10IconBackup $userFolders

            $n = Set-M10SystemIcons $iconDir ([bool]$Opt.FolderIcons)
            Write-Ok "Shell icons written ($n registry entries): This PC, its folders, Quick access, Libraries, OneDrive, Recycle Bin, every folder, every drive and ZIP files"
            $nd = Set-M10DriveIcons $iconDir
            Write-Ok "Drive icon set on $nd fixed drive(s)"

            $done = 0
            foreach ($u in $userFolders) {
                try { Set-M10FolderIconIni $u.Path (Join-Path $iconDir "$($u.Kind).ico"); $done++ }
                catch { Write-Warn "Skipped $($u.Kind) folder: $($_.Exception.Message)" }
            }
            if ($userFolders.Count -gt 0) { Write-Ok "Profile folder icons set ($done of $($userFolders.Count))" }

            $problems = Test-M10IconsApplied $iconDir ([bool]$Opt.FolderIcons)
            $script:ClearIcons = $true
            Update-M10ShellIcons
            if ($problems -eq 0) { $script:Report['Icons'] = "OK - $n shell entries, $nd drive(s), $done profile folder(s)" }
            else { $script:Report['Icons'] = "Written, but $problems entr(y/ies) could not be verified - see the log" }
        }

        if ($Opt.GenericFolder) {
            Invoke-M10Stage 'Machine icons' {
                Write-Step 'Setting the generic folder icon and drive icons for all users (a UAC prompt will appear)...'
                $code = Invoke-M10Elevated 'SetMachineIcons' $Theme '' $iconTheme
                if ($code -ne 0) { throw "Needs admin rights (exit code $code). Apply again and accept the prompt, or untick the generic folder icon." }
                Write-Ok 'Generic folder icon and machine drive icons set'
                $script:Report['Machine icons'] = 'OK'
            }
        }
    }

    Invoke-M10Stage 'Taskbar' {
        Invoke-M10TaskbarApply -Edge $edgeValue -Small $small -AutoHide $autoHide -Restart ([bool]$Opt.RestartExplorer)
    }
    if ($Opt.Wallpaper -and $script:WallpaperFile -and $Opt.RestartExplorer) {
        try {
            $cur = [M10Native]::GetWallpaper()
            if ($cur -ine $script:WallpaperFile) {
                Write-Step 'Explorer restarted; setting the wallpaper again...'
                Set-M10Wallpaper $script:WallpaperFile
            }
        } catch { Write-Warn ('Wallpaper check: ' + $_.Exception.Message); $script:Report['Wallpaper'] = 'FAILED - ' + $_.Exception.Message }
    }
    Send-M10SettingChange

    Write-M10 'step' 'Summary'
    foreach ($k in $script:Report.Keys) {
        $v = [string]$script:Report[$k]
        $lvl = 'ok'; if ($v -like 'FAILED*' -or $v -like 'Saved*' -or $v -like 'Written*') { $lvl = 'warn' }
        Write-M10 $lvl ('{0,-14} {1}' -f $k, $v)
    }
    Write-M10 'done' "Finished. Log: $($script:LogFile)"
}

# ----------------------------------------------------------------------------
# RESTORE
# ----------------------------------------------------------------------------
function Invoke-M10Restore($Opt) {
    $ErrorActionPreference = 'Stop'
    $script:Report = [ordered]@{}
    Initialize-M10Native
    $restart = $true
    if ($Opt -and $Opt.Contains('RestartExplorer')) { $restart = [bool]$Opt.RestartExplorer }
    $script:OldWall = ''
    Write-M10 'step' '================ Modern 10 restore started ================'
    Write-Step 'Restoring original settings...'

    Invoke-M10Stage 'Remove machine overrides' {
        if (Test-M10MachineOverrides) {
            $code = Invoke-M10Elevated 'Cleanup'
            if ($code -ne 0) { throw 'Elevated cleanup failed (UAC declined?).' }
            Write-Ok 'Machine-level lock screen, folder and drive icon overrides removed.'
        }
    }

    if ($restart) { Stop-M10Explorer }

    Invoke-M10Stage 'Restore settings' {
        if (Test-Path -LiteralPath $script:BackupFile) {
            $rows = Get-Content -LiteralPath $script:BackupFile -Raw | ConvertFrom-Json
            foreach ($r in $rows) {
                if ($r.Exists) {
                    switch ($r.Kind) {
                        'DWord'  { Set-M10Reg $r.Path $r.Name ([int]$r.Value) 'DWord' }
                        'Binary' { Set-M10Reg $r.Path $r.Name ([byte[]]$r.Value) 'Binary' }
                        default  { Set-M10Reg $r.Path $r.Name ([string]$r.Value) 'String' }
                    }
                    if ($r.Name -eq 'Wallpaper') { $script:OldWall = [string]$r.Value }
                } else {
                    Remove-ItemProperty -LiteralPath $r.Path -Name $r.Name -ErrorAction SilentlyContinue
                }
            }
            Write-Ok 'User settings restored from backup.'
        } else {
            Write-Warn 'No backup found - applying Windows defaults for the taskbar.'
            Set-M10Reg "$EXP\Advanced" 'TaskbarSmallIcons' 0 'DWord'
            Set-M10Reg "$EXP\Advanced" 'TaskbarGlomLevel' 0 'DWord'
            Set-M10TaskbarLayout 3 0
        }
        $e = Get-M10TaskbarRegistry
        if ($e.Edge -ge 0) { Set-M10TaskbarLayout -Edge $e.Edge -AutoHide -1 }   # keep multi-monitor taskbars in sync
    }

    Invoke-M10Stage 'Restore icons' {
        Restore-M10IconState
        Write-Ok 'Icons restored.'
    }

    if ($restart) { Clear-M10IconCache; Start-M10Explorer }
    Update-M10ShellIcons

    Invoke-M10Stage 'Restore wallpaper' {
        [void][M10Native]::SystemParametersInfo(0x14, 0, [string]$script:OldWall, 3)
    }

    Write-Step 'Pick your lock screen picture again in Settings > Personalization > Lock screen.'

    Get-ChildItem -LiteralPath $script:DataDir -Filter 'wallpaper-*' -File -ErrorAction SilentlyContinue |
        Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $script:DataDir -Filter 'lockscreen-*.png' -ErrorAction SilentlyContinue |
        Remove-Item -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $script:DataDir -Directory -Filter 'icons-*' -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:BackupFile -ErrorAction SilentlyContinue
    Send-M10SettingChange

    foreach ($k in $script:Report.Keys) {
        $v = [string]$script:Report[$k]
        $lvl = 'ok'; if ($v -like 'FAILED*') { $lvl = 'warn' }
        Write-M10 $lvl ('{0,-14} {1}' -f $k, $v)
    }
    Write-M10 'done' "Restore finished. Log: $($script:LogFile)"
}
