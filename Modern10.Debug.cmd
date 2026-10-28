@echo off
rem Runs Modern 10 with a visible console so any error message can be read. Use this if the app does not open.
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0Modern10.GUI.ps1"
