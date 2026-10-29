<h1 align="center">Modern 10</h1>

<p align="center"><img src="assets/Modern10.png" width="96" alt="Modern 10 icon"></p>

<p align="center"><b>Give Windows 10 a glassy, macOS-inspired look. Every change is backed up and reversible.</b></p>

<p align="center">
<img alt="Version" src="https://img.shields.io/badge/version-2.2-0A84FF">
<img alt="Windows" src="https://img.shields.io/badge/Windows-10-0078D4?logo=windows&logoColor=white">
<img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white">
<img alt="GUI" src="https://img.shields.io/badge/GUI-Windows%20Forms-6E56CF">
<img alt="License" src="https://img.shields.io/badge/license-MIT-green">
</p>

---

## Features

- **Look:** Windows dark or light mode, with a matching accent colour.
- **Wallpaper and lock screen:** 13 built-in glass designs (dark and light versions), or your own picture. A live preview shows your choice.
- **Icons:** 11 icon packs for This PC, drives, Quick access, Libraries, OneDrive, the Recycle Bin, ZIP files and every folder.
- **Taskbar:** top or bottom, small or default icons, always visible or auto-hide.
- **Dock options:** a dock-style preset, plus optional KiraDock and TaskbarX (installed only if you choose them).
- **Safe:** every value is backed up first, and one button puts everything back.
- **Light or dark app:** the Modern 10 window has its own theme switch, remembered between runs.
- **Private:** nothing runs in the background and nothing is downloaded. The only network use is the update check, when you press it.

## Install

1. Download this repository and extract it. If you downloaded a ZIP: right-click it > **Properties** > tick **Unblock** > OK, then extract.
2. Double-click **`Modern 10 Installer.cmd`** and choose **1**.
3. Press **Install** in the window that opens, then open **Modern 10** from the Start menu.

The installer works for your account only and needs no administrator rights. It copies the app to `%LOCALAPPDATA%\Programs\Modern10`, adds Start menu and Desktop shortcuts with the Modern 10 icon, and lists Modern 10 in **Settings > Apps**.

**Without installing:** double-click `Modern10.cmd` to run straight from the folder. On the first run, the app offers to install itself.

**Update:** open **About > Check for updates**, or run the installer again from a newer download.

## Using Modern 10

The window has a menu on the left and one page at a time:

| Page | What you do |
|---|---|
| 1. Look | Choose dark or light for Windows |
| 2. Wallpaper & lock screen | Pick a design or your own picture; pick the lock screen style |
| 3. Icons | Pick an icon pack and what it should cover |
| 4. Taskbar | Position, icon size, auto-hide, and Dock options |
| About | Version and developer, open the log folder, check for updates, uninstall |

Press **Apply** to make the changes. Press **Restore original** to put everything back. The log at the bottom shows each step, and `C:\ProgramData\Modern10\modern10.log` keeps the full text.

## What it changes

All changes are per user (`HKCU`), except the optional all-users folder icons and the lock screen fallback, which ask for permission.

| Area | Setting |
|---|---|
| Colour mode and accent | `AppsUseLightTheme`, `SystemUsesLightTheme`, `EnableTransparency`, DWM accent colours |
| Taskbar | `StuckRects3` / `MMStuckRects3` (position, auto-hide), `TaskbarSmallIcons`, a few tidy-up values |
| Icons | `HKCU\Software\Classes` keys for `CLSID\{GUID}\DefaultIcon`, `Folder`, `Directory`, `Drive`, `CompressedFolder`, drive icons, and `desktop.ini` in profile folders |
| Wallpaper | `IDesktopWallpaper`, `Control Panel\Desktop`, slideshow switched off |
| Lock screen | Per-user `LockScreen.SetImageFileAsync`; admin policy fallback only if that fails |

Backups and generated files live in `C:\ProgramData\Modern10\`.

## Safety and undo

- Press **Restore original** in the app to put back your settings, icons and taskbar.
- Restoring cannot bring back your old lock screen picture; choose it again in *Settings > Personalization > Lock screen*.
- Restarting Explorer closes open File Explorer windows. Save your work first.
- Consider creating a System Restore point before first use.

## Uninstall

Use any one of these:

- **Settings > Apps > Modern 10 > Uninstall**
- **About > Uninstall Modern 10** in the app
- `Modern 10 Installer.cmd`, option **2**

The uninstaller offers to restore your original Windows settings first. It only removes files the installer created.

## Requirements

- Windows 10 (1809 or newer) with Windows PowerShell 5.1, already included
- No administrator rights for the normal path

## Troubleshooting

- **The window does not open:** run `Modern10.Debug.cmd` to see the error. Startup errors are also saved to `%TEMP%\Modern10-startup.log` and `%TEMP%\Modern10-setup.log`.
- **Icons did not change:** keep *Restart Explorer* ticked, or sign out and back in. A work PC can lock icon settings through policy.
- **Wallpaper did not change:** check the `Wallpaper check` line in the log. It says if a policy is forcing the wallpaper.
- **Taskbar did not move:** sign out and back in.
- **Windows warns about the files:** right-click the ZIP > Properties > Unblock, then extract again.

## Project layout

```
Modern 10 Installer.cmd  Menu: install or update, uninstall
Modern10.cmd             Runs the app without installing
Modern10.Debug.cmd       Runs the app with a visible console
Modern10.GUI.ps1         The app window
Modern10.Engine.ps1      Theme, taskbar, icons, wallpaper, lock screen, restore
Modern10.Icons.ps1       Icon drawing
Modern10.Elevated.ps1    Small admin helper (runs only after a permission prompt)
Modern10.Setup.ps1       Installer window
Modern10.Uninstall.ps1   Uninstaller
version.txt              Current version number (read by the update check)
assets/                  App icon
```

## Contributing

Keep all code plain ASCII and compatible with Windows PowerShell 5.1. Run a syntax check before sending changes, and bump the version in `Modern10.Engine.ps1` and `version.txt` together.

## Disclaimer

Modern 10 changes registry settings, icons and the taskbar. It is provided as is, without warranty. Read the scripts before you run them.

## License

MIT - see `LICENSE`.

## Developer

Developed by **Tasmon Islam** - tasmon@outlook.com
