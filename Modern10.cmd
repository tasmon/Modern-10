@echo off
rem Double-click launcher: runs the interactive Modern 10 script (no install, no policy change).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Modern10.ps1" %*
