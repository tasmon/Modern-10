<#
  Modern 10 - Dark mode launcher.
  Asks for the taskbar icon size, then applies the dark glass look.
  Extra switches are passed through, e.g.  .\Modern10-Dark.ps1 -IconSize Small -NoLockScreen
#>
& (Join-Path $PSScriptRoot 'Modern10.ps1') -Theme Dark @args
