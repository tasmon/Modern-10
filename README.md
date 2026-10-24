# Modern 10

**A dark and light, glassy, macOS-inspired look for Windows 10 - one window, nothing to install.**

Developed by **Tasmon Islam**.

Modern 10 only changes **built-in Windows settings**. It draws its own wallpaper, lock screen and
**icons** locally (several wallpaper styles and icon themes to choose from), puts the taskbar at the **top or bottom**, sets the **taskbar icon size** and can
**auto-hide** the taskbar for a dock-like feel. Every value it touches is backed up first, so one button puts
everything back.

> No themes to patch, no DLL injection, no startup apps, no services, no downloads.

---

## Start it

1. Download or clone this folder. If you downloaded a ZIP, right-click it > **Properties** > tick **Unblock** > OK, then extract.
2. Double-click **`Modern10.cmd`**. The Modern 10 window opens (there is no console and no command line to learn).
3. Pick your options and press **Apply**. Press **Restore original** to undo everything.

`Modern10.cmd` only starts the window with `-ExecutionPolicy Bypass` for that one process; your system policy is not changed.

## The window

| Control | What it does |
|---|---|
| Theme: Dark / Light | Two complete looks: deep navy-violet glass and soft pastel glass |
| Taskbar position | **Top** (menu-bar style) or **Bottom** (Windows default) |
| Taskbar icon size | **Small** (16px), **Default** (32px) or **Keep** your current size |
| Taskbar behaviour | **Keep**, **Always show** or **Auto-hide** |
| Wallpaper | Choose **Aurora, Waves, Sunset, Ocean, Emerald, Graphite** (each in a dark and a light version, drawn at your screen resolution, no downloads) or **your own image**. A live preview shows the choice |
| Lock screen | Uses the same style, mirrored so it differs from the wallpaper |
| Icon theme | **Glass** (blue), **Graphite**, **Sunset**, **Emerald** or **Violet**, each in a dark and a light version, with a live preview |
| System, drive, folder-type icons | This PC, User, Network, Control Panel, Quick access, Libraries, OneDrive, Recycle Bin (empty/full), **every folder, every drive and ZIP archives** |
| This PC folder icons | 3D Objects, Desktop, Documents, Downloads, Music, Pictures, Videos |
| Profile folder icons | The same folders when you browse inside your user profile (`desktop.ini`) |
| All users too | Also writes the generic folder icon and drive icons machine-wide (one UAC prompt) |
| Dock options | A dock-style preset and a short list of open-source dock/taskbar add-ons |
| Icon preview | Shows the icons that will be drawn for the selected theme |

The log under the buttons shows each step. A summary at the end lists what worked, and the same text is written to
`C:\ProgramData\Modern10\modern10.log`. A failing step never stops the others.

## Requirements

- Windows 10 (built for 1809 and newer; the approach is the same on 22H2)
- Windows PowerShell 5.1 (already included in Windows 10)
- No admin rights for the normal path. A UAC prompt appears only for the **generic folder icon** (and the machine-level drive icons that go with it), for the lock screen fallback, or to clean up older overrides.

> Windows 10 reached end of support on 14 October 2025. If you are still on it, keep an eye on your update/security plan.

## Why the icons did not change in the old version (fixed in 2.0)

1. **Wrong place for the shell icons.** This PC and its folders (Documents, Downloads, ...) read their icon from
   `HKCU\Software\Classes\CLSID\{GUID}\DefaultIcon`. Version 1 wrote only to the desktop-icon location
   (`HKCU\...\Explorer\CLSID\...`), which does not affect the This PC view. Version 2 writes both.
2. **The "(Default)" value was never really set.** The old code created a value literally named `(default)`.
   Explorer ignores it. Version 2 writes the real unnamed default value through the .NET registry API.
3. **Missing folders.** 3D Objects and the This PC folder GUIDs were not covered at all. Both the current and
   the legacy GUID of each folder are now written.
4. **Cache and refresh.** Explorer's icon cache is cleared while Explorer is stopped, and the shell is notified
   again after it restarts (`SHChangeNotify` and `ie4uinit -show`).
5. **Verification.** After writing, the engine reads every entry back and reports how many are really in place.

If the log still says an entry is missing, send me that log line.

## Wallpaper: what changed in 2.0.1

The wallpaper is now set through the same COM interface the Settings app uses (`IDesktopWallpaper`) plus the classic
`SystemParametersInfo` call. A slideshow is switched off, the cached `TranscodedWallpaper` is removed, every apply uses a
new file name (so Windows cannot serve an old copy), and the result is read back and logged. The wallpaper is checked
again after Explorer restarts. If a work policy forces the wallpaper, the log says so.

## Universal icon replacement

Besides This PC and its folders, Modern 10 writes per-user class-level overrides so that Explorer uses the chosen theme everywhere:

| Registry key (under `HKCU\Software\Classes`) | Covers |
|---|---|
| `Folder\DefaultIcon`, `Directory\DefaultIcon` | every ordinary folder |
| `Drive\DefaultIcon`, `Applications\Explorer.exe\Drives\<letter>` | every drive |
| `CompressedFolder\DefaultIcon` | ZIP archives |
| `CLSID\{GUID}\DefaultIcon` | This PC, User, Network, Control Panel, Recycle Bin, Quick access, Libraries, OneDrive and the seven This PC folders |

Folders that carry their own custom icon (for example a folder an app styled itself, or one with its own `desktop.ini`) still
show that icon; Windows always prefers the most specific setting. File-type icons, taskbar app icons and Start tiles are not touched.

## What it changes

All changes are per-user (`HKCU`) except the generic folder icon, machine drive icons and the lock screen fallback.

| Area | Setting |
|---|---|
| Theme | `AppsUseLightTheme`, `SystemUsesLightTheme`, `EnableTransparency=1`, `ColorPrevalence=0` |
| Accent | DWM `AccentColor`, `AccentColorMenu`, `StartColorMenu` (macOS blue) |
| Taskbar position | `StuckRects3` / `MMStuckRects3` edge byte = top (1) or bottom (3) |
| Taskbar auto-hide | Bit 0 of byte 8 in the same `Settings` value |
| Taskbar icon size | `TaskbarSmallIcons` |
| Taskbar tidy-up | `TaskbarGlomLevel=0`, `ShowTaskViewButton=0`, `ShowCortanaButton=0`, `SearchboxTaskbarMode=1`, `ShellFeedsTaskbarViewMode=2`, `PeopleBand=0` |
| Selection glass | `ListviewAlphaSelect=1`, `ListviewShadow=1`, `TaskbarAnimations=1` |
| Shell icons | `HKCU\Software\Classes\CLSID\{GUID}\DefaultIcon` and `HKCU\...\Explorer\CLSID\{GUID}\DefaultIcon`; class-level `Folder`, `Directory`, `Drive`, `CompressedFolder` |
| Drive icons | `HKCU\Software\Classes\Applications\Explorer.exe\Drives\<letter>\DefaultIcon` (and `HKLM\...\Explorer\DriveIcons\<letter>` with admin) |
| Profile folder icons | `IconResource=` line in each folder's `desktop.ini` (original content and attributes are backed up) |
| Generic folder icon (admin) | `HKLM\...\Explorer\Shell Icons` values `3` (closed) and `4` (open); removed again by Restore |
| Wallpaper | `IDesktopWallpaper` COM call, `Control Panel\Desktop` Wallpaper, `WallpaperStyle=10`, `TileWallpaper=0`, `Explorer\Wallpapers\BackgroundType=0` |
| Lock screen | Per-user WinRT API `LockScreen.SetImageFileAsync` (no admin). Fallback only if that fails: `PersonalizationCSP` and the `LockScreenImage` policy (admin) |

Generated files and the backups live in `C:\ProgramData\Modern10\`:

```
backup.json  icons-backup.json  modern10.log
wallpaper-<theme>-<style>-<timestamp>.png
lockscreen-<theme>-<timestamp>.png
icons-<theme>-<icontheme>\*.ico
```

## Dock-style taskbar

Windows 10 has no real dock, but you can get close:

- **Built in, nothing extra:** open **Dock options...** and press *Use the dock-style preset* (bottom, default icons, auto-hide), then **Apply**. Auto-hide is just a flag in the taskbar's registry setting.
- **Open-source add-ons** (separate downloads; Modern 10 does not install them):

| Tool | What it gives you | Notes |
|---|---|---|
| [Seelen UI](https://github.com/eythaann/Seelen-UI) | macOS-style dock and toolbar replacing the taskbar | AGPL-3.0, Windows 10 and 11, heaviest option |
| [Windhawk](https://windhawk.net) | Small mod platform; browse its catalog for taskbar mods | Windows 10 is the minimum supported version |
| [TranslucentTB](https://github.com/TranslucentTB/TranslucentTB) | Clear or blurred taskbar | GPL-3.0, Windows 10 and 11 |
| [SmartTaskbar](https://github.com/Oliviaophia/SmartTaskbar) | Hides the taskbar when a window is maximised | MIT, tiny |

For the closest "floating dock" look, Seelen UI is the all-in-one choice; the built-in preset above is the lightest.

## Limitations (Windows 10 is Windows 10)

- **Icon size:** Windows 10 natively supports only small (16px) and default (32px) taskbar icons.
- **Floating dock:** not possible without third-party software on Windows 10 - see the table above.
- **Blur:** Windows 10 only provides its built-in translucent/acrylic effects.
- **Rounded windows and macOS fonts:** not available without extra software, so they are intentionally left alone.
- **Restoring the lock screen:** Windows does not expose your previous lock screen picture, so *Restore original* cannot put it back. Choose it again in *Settings > Personalization > Lock screen*.
- File-type icons (`.txt`, `.pdf`, ...), taskbar app icons and Start tiles come from the apps themselves and are not changed (ZIP archives are the one exception).

## Troubleshooting

**Read the log first.** The window shows each step, and `C:\ProgramData\Modern10\modern10.log` keeps the full text.

**Icons did not change**
Leave *Restart Explorer* ticked, or sign out and in. The generic folder icon only changes if you accept the UAC prompt.
Make sure *System, drive, folder-type icons* is ticked (the folder and generic options depend on it). If the `.ico` files in
`C:\ProgramData\Modern10\` were deleted, press **Restore original** and then **Apply** again. A work PC can lock icon
settings through policy.

**Wallpaper did not change**
Read the `Wallpaper check` line in the log: it shows what Windows reports after the change. A message about a policy means an organisation setting is forcing the wallpaper.

**Taskbar did not move / resize**
The engine stops Explorer, writes the layout while no shell is running, restarts Explorer and measures the live taskbar (up to 3 attempts).
If the summary says *Saved, but live taskbar is ...*, sign out and back in. A taskbar managed by a work policy cannot be moved.

**Lock screen did not change**
Press **Win+L** to check. The summary tells you which method worked. If the machine-level method was used, set *Background* to
**Picture** (not *Windows Spotlight*) in *Settings > Personalization > Lock screen*. Organisation policy can override both.

**The window does not open**
Right-click the ZIP > Properties > **Unblock** and extract again. If Windows shows an error dialog, it contains the reason.

## Uninstall

Nothing is installed. Press **Restore original**, then delete the folder (and optionally `C:\ProgramData\Modern10\`).

## Safety notes

- The scripts are plain text. Read them before you run them.
- Consider creating a System Restore point before first use.
- It makes no network connections.
- Restarting Explorer closes open File Explorer windows; save your work first.
- The only code that runs as administrator is `Modern10.Elevated.ps1`. It accepts five fixed actions, no free-form paths, and only touches files inside `C:\ProgramData\Modern10`.

## Project layout

```
Modern10/
|-- Modern10.cmd           Double-click to open the window
|-- Modern10.GUI.ps1       The window (Windows Forms)
|-- Modern10.Engine.ps1    All the work: theme, taskbar, icons, wallpaper, lock screen, restore
|-- Modern10.Icons.ps1     Icon drawing library (also used for the preview)
|-- Modern10.Elevated.ps1  Tiny admin helper (only runs after a UAC prompt)
|-- LICENSE
`-- README.md
```

## License

MIT - see `LICENSE`. Copyright (c) 2026 Tasmon Islam.
