# Modern10.Elevated.ps1 - the only part of Modern 10 that ever runs as administrator.
# Started by the GUI engine through a UAC prompt. It accepts a fixed set of actions and takes no free-form
# paths: icon files are always looked up inside C:\ProgramData\Modern10 and the lock image must be a
# "lockscreen-*.png" file name inside that folder.
#
# Developer: Tasmon Islam
param(
    [Parameter(Mandatory = $true)][ValidateSet('SetMachineIcons', 'RemoveMachineIcons', 'SetLock', 'RemoveLock', 'Cleanup')][string]$Action,
    [ValidateSet('Dark', 'Light')][string]$Theme = 'Dark',
    [ValidateSet('Glass', 'Graphite', 'Sunset', 'Emerald', 'Violet')][string]$IconTheme = 'Glass',
    [string]$LockFile = ''
)
$ErrorActionPreference = 'Stop'

$dataDir = Join-Path $env:ProgramData 'Modern10'
$logFile = Join-Path $dataDir 'modern10.log'
function Write-HelperLog([string]$t) {
    try { Add-Content -LiteralPath $logFile -Encoding UTF8 -Value ('{0:yyyy-MM-dd HH:mm:ss}  (admin) {1}' -f (Get-Date), $t) } catch { }
}

$cspKey        = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
$polKey        = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
$shellIconsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons'
$driveIconsSub = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons'

function Set-StringValue([string]$Path, [string]$Name, [string]$Value) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
}

function Get-FixedLetters {
    $l = @()
    foreach ($d in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) { $l += $d.DeviceID.Substring(0, 1) }
    return $l
}

function Set-MachineIcons {
    $dir = Join-Path $dataDir ('icons-' + $Theme.ToLower() + '-' + $IconTheme.ToLower())
    $closed = Join-Path $dir 'Folder.ico'
    $open   = Join-Path $dir 'FolderOpen.ico'
    $drive  = Join-Path $dir 'Drive.ico'
    foreach ($f in $closed, $open, $drive) { if (-not (Test-Path -LiteralPath $f)) { throw "Icon file missing: $f" } }
    Set-StringValue $shellIconsKey '3' ("$closed,0")
    Set-StringValue $shellIconsKey '4' ("$open,0")
    foreach ($letter in (Get-FixedLetters)) {
        $k = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey(("{0}\{1}\DefaultIcon" -f $driveIconsSub, $letter))
        try { $k.SetValue('', $drive, [Microsoft.Win32.RegistryValueKind]::String) } finally { $k.Close() }
    }
}

function Remove-MachineIcons {
    foreach ($n in '3', '4') {
        $v = Get-ItemProperty -LiteralPath $shellIconsKey -Name $n -ErrorAction SilentlyContinue
        if ($v -and ([string]$v.$n) -like '*\Modern10\*') { Remove-ItemProperty -LiteralPath $shellIconsKey -Name $n -ErrorAction SilentlyContinue }
    }
    $root = [Microsoft.Win32.Registry]::LocalMachine
    $dk = $root.OpenSubKey($driveIconsSub)
    if ($dk) {
        $names = @($dk.GetSubKeyNames()); $dk.Close()
        foreach ($n in $names) {
            $k = $root.OpenSubKey(("{0}\{1}\DefaultIcon" -f $driveIconsSub, $n))
            if ($k) {
                $cur = [string]$k.GetValue('', ''); $k.Close()
                if ($cur -like '*\Modern10\*') { $root.DeleteSubKeyTree(("{0}\{1}" -f $driveIconsSub, $n), $false) }
            }
        }
    }
}

function Set-Lock {
    if ($LockFile -notmatch '^lockscreen-(dark|light)-\d{8}-\d{6}\.png$') { throw 'Invalid lock screen file name.' }
    $img = Join-Path $dataDir $LockFile
    if (-not (Test-Path -LiteralPath $img)) { throw "Lock screen image missing: $img" }
    Set-StringValue $cspKey 'LockScreenImagePath'   $img
    Set-StringValue $cspKey 'LockScreenImageUrl'    $img
    New-ItemProperty -LiteralPath $cspKey -Name 'LockScreenImageStatus' -Value 1 -PropertyType DWord -Force | Out-Null
    Set-StringValue $polKey 'LockScreenImage'       $img
}

function Remove-Lock {
    foreach ($pair in @(@($cspKey, 'LockScreenImagePath'), @($polKey, 'LockScreenImage'))) {
        $v = Get-ItemProperty -LiteralPath $pair[0] -Name $pair[1] -ErrorAction SilentlyContinue
        if ($v -and ([string]$v.($pair[1])) -like '*\Modern10\*') {
            if ($pair[0] -eq $cspKey) {
                foreach ($n in 'LockScreenImagePath', 'LockScreenImageUrl', 'LockScreenImageStatus') {
                    Remove-ItemProperty -LiteralPath $cspKey -Name $n -ErrorAction SilentlyContinue
                }
            } else {
                Remove-ItemProperty -LiteralPath $polKey -Name 'LockScreenImage' -ErrorAction SilentlyContinue
            }
        }
    }
}

try {
    switch ($Action) {
        'SetMachineIcons'    { Set-MachineIcons }
        'RemoveMachineIcons' { Remove-MachineIcons }
        'SetLock'            { Set-Lock }
        'RemoveLock'         { Remove-Lock }
        'Cleanup'            { Remove-Lock; Remove-MachineIcons }
    }
    Write-HelperLog "$Action done"
    exit 0
} catch {
    Write-HelperLog "$Action failed: $($_.Exception.Message)"
    exit 1
}
