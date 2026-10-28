#Requires -Version 5.1
<#
.SYNOPSIS
    Modern 10 - uninstaller (started from Settings > Apps, or from the install folder).

.DESCRIPTION
    Optionally restores your original Windows settings, then removes the shortcuts, the Settings > Apps entry
    and the installed files. Only works on an installed copy - running it from a downloaded folder does nothing.
#>
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $PSCommandPath
    exit
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Modern10'
$here = $PSScriptRoot.TrimEnd('\')
$title = 'Uninstall Modern 10'
function Show-Box([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') {
    return [System.Windows.Forms.MessageBox]::Show($Text, $title, $Buttons, $Icon)
}

$loc = ''
try { $loc = ([string](Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallLocation).TrimEnd('\') } catch { }
if (-not $loc -or ($loc -ine $here)) {
    [void](Show-Box 'This copy of Modern 10 was not installed with Setup, so there is nothing to uninstall here. To remove it, press "Restore original" in the app and delete the folder.' 'OK' 'Information')
    exit
}

if ((Show-Box 'Uninstall Modern 10 from this computer?' 'YesNo' 'Question') -ne 'Yes') { exit }

$dataDir = Join-Path $env:ProgramData 'Modern10'
$restored = $false
if (Test-Path -LiteralPath (Join-Path $dataDir 'backup.json')) {
    $r = Show-Box ("Modern 10 has changed your Windows settings (theme, taskbar, icons, wallpaper).`n`nPut your original settings back before uninstalling?`n`nYes = restore, then uninstall`nNo = uninstall and keep the current look`nCancel = stop") 'YesNoCancel' 'Question'
    if ($r -eq 'Cancel') { exit }
    if ($r -eq 'Yes') {
        $wait = New-Object System.Windows.Forms.Form
        $wait.Text = $title; $wait.ClientSize = New-Object System.Drawing.Size(360, 90); $wait.StartPosition = 'CenterScreen'
        $wait.FormBorderStyle = 'FixedDialog'; $wait.ControlBox = $false; $wait.TopMost = $true
        $wl = New-Object System.Windows.Forms.Label
        $wl.Text = 'Restoring your original settings... Explorer may restart.'; $wl.AutoSize = $false
        $wl.Location = New-Object System.Drawing.Point(20, 28); $wl.Size = New-Object System.Drawing.Size(320, 40)
        $wait.Controls.Add($wl); $wait.Show(); [System.Windows.Forms.Application]::DoEvents()
        try {
            . (Join-Path $here 'Modern10.Engine.ps1')
            $o = New-M10Options
            Invoke-M10Restore $o
            $restored = $true
        } catch {
            $wait.Close()
            if ((Show-Box ("Restoring failed:`n" + $_.Exception.Message + "`n`nContinue uninstalling anyway?") 'YesNo' 'Warning') -ne 'Yes') { exit }
        }
        try { $wait.Close() } catch { }
    }
}

# shortcuts and the Settings > Apps entry
foreach ($lnk in @((Join-Path ([Environment]::GetFolderPath('Programs')) 'Modern 10.lnk'), (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Modern 10.lnk'))) {
    try { if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force } } catch { }
}
try { Remove-Item -LiteralPath $key -Recurse -Force } catch { }

# generated files and backups are only removed after a successful restore
if ($restored) { try { Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction Stop } catch { } }

# installed files: delete only what Setup put there, then remove the folder if it is empty
$mine = @('Modern10.GUI.ps1', 'Modern10.Engine.ps1', 'Modern10.Icons.ps1', 'Modern10.Elevated.ps1', 'Modern10.cmd', 'LICENSE', 'README.md',
          'assets\Modern10.ico', 'assets\Modern10.png')
foreach ($f in $mine) { try { Remove-Item -LiteralPath (Join-Path $here $f) -Force -ErrorAction SilentlyContinue } catch { } }
try { Remove-Item -LiteralPath (Join-Path $here 'assets') -Force -ErrorAction SilentlyContinue } catch { }
# this script is still running, so a short helper removes it and the folder a moment after we exit
$self = $PSCommandPath
$cmd = '/c ping 127.0.0.1 -n 3 >nul & del /f /q "' + $self + '" & rd "' + $here + '"'
try { Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList $cmd -WindowStyle Hidden } catch { }

$msg = 'Modern 10 was uninstalled.'
if (-not $restored -and (Test-Path -LiteralPath $dataDir)) { $msg += "`n`nYour current look was kept. Backups remain in $dataDir (safe to delete)." }
[void](Show-Box $msg 'OK' 'Information')
