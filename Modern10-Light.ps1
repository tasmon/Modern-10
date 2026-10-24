<#
  Modern 10 - Light mode launcher.
  Asks for the taskbar icon size, then applies the light glass look.
  Extra switches are passed through, e.g.  .\Modern10-Light.ps1 -IconSize Default -NoLockScreen
#>
& (Join-Path $PSScriptRoot 'Modern10.ps1') -Theme Light @args
