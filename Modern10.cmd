@echo off
rem Opens the Modern 10 window. Nothing is installed and no policy is changed.
start "" powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Modern10.GUI.ps1"
