@echo off
setlocal
title Modern 10 Installer
rem Keep this file in the same folder as Modern10.Setup.ps1. No administrator rights needed.
:menu
cls
echo.
echo   Modern 10 Installer
echo   -------------------
echo.
echo   [1] Install or update Modern 10
echo   [2] Uninstall Modern 10
echo   [3] Exit
echo.
set "choice="
set /p "choice=  Choose 1, 2 or 3: "
if "%choice%"=="1" goto install
if "%choice%"=="2" goto uninstall
if "%choice%"=="3" goto done
goto menu

:install
if not exist "%~dp0Modern10.Setup.ps1" (
  echo.
  echo   Modern10.Setup.ps1 was not found next to this file. Extract the whole download first.
  pause
  goto menu
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue"
start "" powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Modern10.Setup.ps1"
goto done

:uninstall
if not exist "%~dp0Modern10.Setup.ps1" (
  echo.
  echo   Modern10.Setup.ps1 was not found next to this file.
  pause
  goto menu
)
start "" powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Modern10.Setup.ps1" -Uninstall
goto done

:done
endlocal
