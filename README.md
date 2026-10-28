# Modern 10

![Version](https://img.shields.io/badge/version-2.1-0A84FF)
![Windows](https://img.shields.io/badge/Windows-10-0078D4?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)
![Windows Forms](https://img.shields.io/badge/GUI-Windows%20Forms-6E56CF)
![.NET](https://img.shields.io/badge/.NET-System.Drawing-512BD4?logo=dotnet&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

<p align="center"><img src="assets/Modern10.png" width="96" alt="Modern 10 icon"></p>

A dark and light, glassy, macOS-inspired look for Windows 10. One window, every change backed up and reversible.

## Install

1. Download this folder. If it came as a ZIP: right-click it > **Properties** > tick **Unblock** > OK, then extract.
2. Double-click **`Setup.cmd`**, choose a folder if you like, and press **Install**.
3. Open **Modern 10** from the Start menu (or the Desktop shortcut) and press **Apply**.

Setup installs for your account only, so it needs no administrator rights. It copies the app to `%LOCALAPPDATA%\Programs\Modern10`, adds shortcuts with the Modern 10 icon, and lists Modern 10 in **Settings > Apps**.

**Update:** run `Setup.cmd` from the newer download. **Uninstall:** Settings > Apps > Modern 10 > Uninstall. It offers to restore your original Windows settings first.

**No install?** Double-click `Modern10.cmd` to run it straight from the folder.

## What you can change

| Option | Choices |
|---|---|
| Theme | Dark or Light |
| Taskbar | Top or bottom, small or default icons, always show or auto-hide |
| Wallpaper | 13 styles (Aurora, Waves, Sunset, Ocean, Emerald, Graphite, Nebula, Rose, Midnight, Citrus, Arctic, Dunes, Lagoon) or your own image |
| Lock screen | Same as the wallpaper, or any of the 13 styles |
| Icon theme | 11 packs (Glass, Graphite, Sunset, Emerald, Violet, Rose, Amber, Ocean, Crimson, Mint, Midnight) |
| Icons applied to | This PC, User, Network, Control Panel, Quick access, Libraries, OneDrive, Recycle Bin, drives, ZIP files, the standard folders and every other folder |
| Dock options | A dock-style preset, plus optional KiraDock and TaskbarX (see below) |

Wallpapers, lock screens and icons are drawn on your PC. Nothing is downloaded.

## Optional dock add-ons

Open **Dock options...** in the app. Nothing is installed unless you tick it and press **Install selected**.

| App | Purpose |
|---|---|
| [KiraDock](https://apps.microsoft.com/detail/9NPD1H35D0WD) | A macOS-style floating dock for your favourite apps (Microsoft Store) |
| [TaskbarX](https://github.com/ChrisAnd1998/TaskbarX/releases) | Centres and animates the taskbar icons (GitHub) |

## Requirements

- Windows 10 with Windows PowerShell 5.1 (already included)
- No admin rights for most changes. A UAC prompt appears only for the all-users folder and drive icons and the lock screen fallback.

## Good to know

- Restarting Explorer closes open File Explorer windows. Save your work first.
- Folders with their own custom icon keep it. File-type icons, taskbar app icons and Start tiles are not changed.
- *Restore original* cannot bring back your old lock screen picture. Choose it again in *Settings > Personalization > Lock screen*.
- Windows 10 has no real dock, blur or rounded windows without extra software.
- A work PC can block wallpaper, lock screen or icon changes through policy.

## Troubleshooting

Read the log in the window. The full text is saved in `C:\ProgramData\Modern10\modern10.log`.

- **Icons did not change:** keep *Restart Explorer* ticked, or sign out and back in.
- **Wallpaper did not change:** check the `Wallpaper check` line in the log. It says if a policy is forcing the wallpaper.
- **Taskbar did not move:** sign out and back in.
- **Window does not open:** unblock the ZIP (step 1) and extract it again.

## Safety

- The scripts are plain text, so you can read them first.
- No network connections, no services, no startup entries.
- Backups and generated files live in `C:\ProgramData\Modern10\`.
- The uninstaller only removes files Setup created and only works on an installed copy.
- Only `Modern10.Elevated.ps1` runs as administrator, and it accepts a few fixed actions.

## Files

```
Setup.cmd              Installs the app (Start menu, shortcuts, Settings > Apps)
Modern10.Setup.ps1     The setup window
Modern10.Uninstall.ps1 Removes the app (started from Settings > Apps)
Modern10.cmd           Runs the app without installing
Modern10.GUI.ps1       The app window
assets/                App icon (Modern10.ico, Modern10.png)
Modern10.Engine.ps1    Theme, taskbar, icons, wallpaper, lock screen, restore
Modern10.Icons.ps1     Icon drawing
Modern10.Elevated.ps1  Small admin helper
```

---

MIT License. Developed by **Tasmon Islam** - tasmon@outlook.com
