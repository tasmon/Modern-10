<#
  Modern 10 - Restore launcher.
  Puts back every setting that Modern 10 changed (from the saved backup).
#>
& (Join-Path $PSScriptRoot 'Modern10.ps1') -Restore @args
