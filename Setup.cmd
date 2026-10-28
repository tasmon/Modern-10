@echo off
rem Modern 10 setup - installs the app for your account (no administrator rights needed).
start "" powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Modern10.Setup.ps1"
