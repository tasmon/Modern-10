@echo off
rem Opens the Modern 10 window (no console, nothing installed, no policy change).
start "" powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Modern10-GUI.ps1"
