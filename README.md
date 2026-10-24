# Modern 10

**A dark and light, glassy, macOS-inspired look for Windows 10 - with nothing to install. Now with a GUI, a top/bottom taskbar choice and macOS-style icons.**

Modern 10 is a tiny PowerShell project that only changes **built-in Windows settings**. It draws its own
wallpaper, lock screen and **icons** locally, puts the taskbar at the **top or bottom** (your choice), and lets you
pick the **taskbar icon size** - from a small window (GUI) or from the command line. Every value it touches is backed up first, so one command puts everything back.

> No themes to patch, no DLL injection, no startup apps, no services, no downloads.

---

<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/0cc5915d-54c4-46c1-8f04-349ff972b5cd" />

---

<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/4be0b91c-bf8d-4327-ad02-1e81240f0af7" />

---

## Features

| | |
|---|---|
| Dark and Light | Two complete looks: deep indigo glass and soft pastel glass |
| Glass effect | Transparency effects on, neutral translucent taskbar and Start |
| GUI | `Modern10-GUI.cmd` opens a small window with live icon preview and a progress log |
| Taskbar position | You choose **Top** (menu-bar style) or **Bottom** (Windows default) |
| macOS-style icons | This PC, Recycle Bin (empty/full), User, Network, Control Panel, drives, generic folder (closed/open) and Documents/Downloads/Pictures/Music/Videos/Desktop folders |
| Icon size picker | Choose **Small** or **Default** icons at run time (or **Keep** your current size) |
| Own artwork | Wallpaper and lock screen are generated on your machine at your screen resolution (no downloads) |
| Verified | After applying, the script measures the real taskbar position/thickness and writes a log |
| macOS touches | Blue accent colour, icon-only taskbar buttons, search as an icon, translucent selection boxes |
| Safe | Full backup and one-command restore |

## Requirements

- Windows 10 (built for 1809 and newer; tested approach on 22H2)
- Windows PowerShell 5.1 (already included in Windows 10). If you start the script from PowerShell 7 it re-launches itself in Windows PowerShell automatically.
- No admin rights for the normal path. A UAC prompt appears **only** if the lock screen needs the machine-level fallback or an old override must be cleaned up.

> Windows 10 reached end of support on 14 October 2025. If you are still on it, keep an eye on your update/security plan.

## Quick start

1. Download or clone this repository.
2. If you downloaded a ZIP, right-click it > **Properties** > tick **Unblock** > OK, then extract.
3. Open the folder and pick one:

**GUI** - double-click `Modern10-GUI.cmd`. Pick theme, taskbar position, icon size and what to apply, then press **Apply**. **Restore original** undoes everything.

**Console** - double-click `Modern10.cmd` and answer the prompts.

**Dark mode**

```powershell
powershell -ExecutionPolicy Bypass -File .\Modern10-Dark.ps1
```

**Light mode**

```powershell
powershell -ExecutionPolicy Bypass -File .\Modern10-Light.ps1
```

**Undo everything**

```powershell
powershell -ExecutionPolicy Bypass -File .\Modern10-Restore.ps1
```

`-ExecutionPolicy Bypass` only applies to that one PowerShell window. Your system policy is not changed.

### What you will be asked (console)

```
Where should the taskbar go?
  [1] Top    - like the macOS menu bar
  [2] Bottom - the Windows default

Replace system, drive and folder icons with macOS-style icons?
  [1] Yes - This PC, drives, Recycle Bin, folders (they are drawn locally)
  [2] No  - leave icons alone

Choose the taskbar icon size:
  [1] Small   - 16px icons, slim bar (closest to a macOS menu bar)
  [2] Default - 32px icons, standard height
  [3] Keep    - leave my current size
```

Running `Modern10.ps1` directly also asks you to choose Dark or Light.

## Options

| Parameter | Description |
|---|---|
| `-Theme Dark\|Light` | Skip the theme question |
| `-TaskbarPosition Top\|Bottom` | Skip the taskbar position question |
| `-IconSize Small\|Default\|Keep` | Skip the icon size question |
| `-Icons Yes\|No` / `-NoIcons` | Skip the icons question / never touch icons |
| `-NoFolderIcons` | Skip the generic folder icon (the only icon step that needs admin) |
| `-NoUserFolderIcons` | Skip Documents/Downloads/Pictures/Music/Videos/Desktop folder icons |
| `-NoWallpaper` | Do not draw/set the wallpaper |
| `-NoLockScreen` | Do not draw/set the lock screen (no UAC prompt) |
| `-NoRestartExplorer` | Do not restart Explorer; changes appear after you sign out and in |
| `-NoPause` | Do not wait for Enter at the end (for automation) |
| `-Restore` | Undo all changes |

Examples:

```powershell
.\Modern10.ps1 -Theme Dark -TaskbarPosition Top -IconSize Small -Icons Yes
.\Modern10-Light.ps1 -IconSize Default -NoLockScreen
.\Modern10.ps1 -Restore
```

Switching between Dark and Light later is just running the other launcher again; your original settings stay in the backup.

## What it changes

All changes are per-user (`HKCU`) except the lock screen image.

| Area | Setting |
|---|---|
| Theme | `AppsUseLightTheme`, `SystemUsesLightTheme`, `EnableTransparency=1`, `ColorPrevalence=0` |
| Accent | DWM `AccentColor`, `AccentColorMenu`, `StartColorMenu` (macOS blue) |
| Taskbar position | `StuckRects3` / `MMStuckRects3` edge byte = top (1) or bottom (3) |
| Taskbar icon size | `TaskbarSmallIcons` |
| Taskbar tidy-up | `TaskbarGlomLevel=0`, `ShowTaskViewButton=0`, `ShowCortanaButton=0`, `SearchboxTaskbarMode=1`, `ShellFeedsTaskbarViewMode=2`, `PeopleBand=0` |
| Selection glass | `ListviewAlphaSelect=1`, `ListviewShadow=1`, `TaskbarAnimations=1` |
| System icons | `HKCU\...\Explorer\CLSID\{GUID}\DefaultIcon` for This PC, User's Files, Network, Control Panel and Recycle Bin (default/empty/full) |
| Drive icons | `HKCU\Software\Classes\Applications\Explorer.exe\Drives\<letter>\DefaultIcon` for each fixed drive |
| User folder icons | `IconResource=` line in each known folder's `desktop.ini` (original content and attributes are backed up) |
| Generic folder icon (admin) | `HKLM\...\Explorer\Shell Icons` values `3` (closed) and `4` (open); removed again by Restore |
| Wallpaper | `Control Panel\Desktop` Wallpaper, `WallpaperStyle=10`, `TileWallpaper=0` |
| Lock screen | Built-in per-user WinRT API `Windows.System.UserProfile.LockScreen.SetImageFileAsync` (same call Settings uses, no admin). Fallback only if that fails: `HKLM\...\PersonalizationCSP` `LockScreenImage*` and the `LockScreenImage` personalization policy (admin) |

Generated files and the backup live in `C:\ProgramData\Modern10\`:

```
backup.json
modern10.log
icons-backup.json
wallpaper-dark.png / wallpaper-light.png
lockscreen-<theme>-<timestamp>.png
icons-dark\*.ico / icons-light\*.ico
```

## Icons

All 15 icons are vector-drawn with `System.Drawing` (rounded glass folders, a monitor for This PC, a brushed-metal drive,
a mesh bin that shows crumpled paper when full, a gear for Control Panel...) and written as multi-size `.ico` files
(16 to 256 px) in `C:\ProgramData\Modern10\icons-<theme>\`. Dark and Light use different palettes.
After applying, Explorer's icon cache is cleared while Explorer is stopped so the new icons show immediately.

Not changed on purpose: file-type icons (for example `.txt` or `.zip`), taskbar app icons and Start menu tiles - those come from
the apps themselves.

## How the artwork is made

The wallpaper and lock screen are drawn with .NET `System.Drawing` at your primary screen's native resolution:
a diagonal gradient base, soft colour glows, three translucent gradient "wave" layers with a glassy highlight edge,
and a touch of grain to prevent banding. The lock screen uses a mirrored composition so the two do not look identical.
Nothing is downloaded.

## Limitations (Windows 10 is Windows 10)

- **Icon size:** Windows 10 natively supports only small (16px) and default (32px) taskbar icons. Modern 10 uses exactly those two.
- **Centered icons / floating dock:** not possible without third-party software on Windows 10, so Modern 10 does not fake it.
- **Blur:** Windows 10 only provides its built-in translucent/acrylic effects. It will look glassy, not identical to macOS vibrancy.
- **Rounded windows and macOS fonts:** not available in Windows 10 without extra software, so they are intentionally left alone.
- **Restoring the lock screen:** Windows does not expose your previous lock screen picture, so `-Restore` cannot put it back. It removes any Modern 10 override; choose your lock screen again in *Settings > Personalization > Lock screen*.

## Troubleshooting

**First, read the summary and the log.** At the end the script prints a status per step (Theme, Wallpaper, Lock screen, Taskbar) and writes `C:\ProgramData\Modern10\modern10.log`. A failing step no longer stops the others.

**Taskbar did not move / icons did not resize**
The script stops Explorer, writes the layout while no shell is running, restarts Explorer, then measures the live taskbar (up to 3 attempts). If the summary says *Saved, but live taskbar is ...*, sign out and back in. A taskbar locked or managed by a work policy cannot be moved. Do not run with `-NoRestartExplorer` unless you plan to sign out.

**Lock screen did not change**
Press **Win+L** to check (the sign-in screen can lag until the next lock). The summary tells you which method worked:
- *per-user API* - Windows switched your lock screen *Background* to **Picture** itself.
- *machine-level* - the fallback was used; set *Background* to **Picture** (not *Windows Spotlight*) in *Settings > Personalization > Lock screen*.
If your PC is managed by an organization, their policy can override both.

**Icons did not change / some icons are blank**
Run again without `-NoRestartExplorer` so Explorer can clear its icon cache, or sign out and in. The generic folder icon only
changes if you accepted the UAC prompt (or run with admin rights). If the `.ico` files in `C:\ProgramData\Modern10\` were
deleted, run **Restore original**, then Apply again.

**Wallpaper looks soft or stretched**
The image is created at your primary display's resolution. Re-run after changing resolution or scaling.

**"Running scripts is disabled"**
Use the commands above (`-ExecutionPolicy Bypass`) or double-click `Modern10.cmd`.

**Something looks off and the backup is gone**
Run `Modern10-Restore.ps1`; without a backup it still resets the taskbar to the bottom with default icons. You can also pick a theme/wallpaper from *Settings > Personalization*.

## Uninstall

There is nothing installed. Run the restore script, then delete the repository folder.
Optionally delete `C:\ProgramData\Modern10\` (the restore script already clears the images and backup).

## Safety notes

- The script is plain text. Read it before you run it.
- Consider creating a System Restore point before first use.
- It makes no network connections.
- Restarting Explorer closes open File Explorer windows; save your work first.

## Project layout

```
Modern10/
|-- Modern10.ps1          Main script (interactive; all logic)
|-- Modern10.Icons.ps1    Icon drawing library (used by the script and the GUI)
|-- Modern10-GUI.ps1      Windows Forms front-end
|-- Modern10-GUI.cmd      Double-click launcher for the GUI
|-- Modern10-Dark.ps1     Dark launcher
|-- Modern10-Light.ps1    Light launcher
|-- Modern10-Restore.ps1  Undo launcher
|-- Modern10.cmd          Double-click launcher
`-- README.md
```

## License

MIT - do whatever you like, no warranty. Add a `LICENSE` file with the standard MIT text before publishing.
