# Dependencies

Everything below is something a file in this config actually shells out
to, or a QML module that requires a corresponding system service to be
running. Grouped by what breaks if it's missing.

## Required — core shell won't function without these

- **quickshell** (0.3.1+) — obviously. Built against `Quickshell.Bluetooth`,
  `Quickshell.Services.Pipewire`, `Quickshell.Services.UPower`,
  `Quickshell.Services.Notifications`, `Quickshell.Services.Mpris`,
  `Quickshell.Services.SystemTray`, `Quickshell.Networking`,
  `Quickshell.Hyprland`, `Quickshell.Wayland`, `Quickshell.Io`. A recent
  enough build is needed for `FileView.watchChanges`, `PwObjectTracker`,
  the Bluetooth module, and `Quickshell.Networking`
  specifically — all newer additions to Quickshell itself.

- **Hyprland** (0.55+) — `bar/Workspaces.qml` dispatches directly via
  the `Hyprland` singleton (`Hyprland.dispatch(...)`,
  `Hyprland.workspaces`, `Hyprland.focusedWorkspace`,
  `Hyprland.monitorFor(...)`). Config assumes the Lua config format
  (`hyprland.lua`) for the keybind examples referenced throughout this
  conversation, though that only affects your own bind syntax, not the
  QML itself. Also needs your build to actually
  implement a few specific Wayland protocol extensions Hyprland doesn't
  guarantee uniformly across builds/versions — confirmed present on this
  machine's build by checking `hyprctl globalshortcuts` and by
  live-testing idle/inhibit behavior (4.3) respectively:
  `hyprland_global_shortcuts_manager_v1` (bar/panel `GlobalShortcut`
  keybinds — SUPER+P/Q/B/ALT+SPACE, `hypr/modules/binds/apps.lua`'s
  `hl.dsp.global(...)` calls) and `ext-idle-notify-v1` (bar dimming +
  notification suppression while idle, `services/Idle.qml`). One
  protocol this build was specifically checked *against* and found
  **not** present: whatever client-requested background-blur protocol
  `Quickshell.Wayland.BackgroundEffect` needs — Hyprland's
  own blur stays entirely `hl.layer_rule`-config-driven
  (`hypr/modules/windowrules.lua`) instead. Protocol support isn't
  something to assume from a version number alone; re-verify live
  (`strings` on the binary, or a real behavioral test) if this ever
  moves to a different Hyprland build or a different compositor.

- **systemd** — `loginctl` (lock/session) and `systemctl`
  (reboot/poweroff) in `powermenu/PowerMenuPopout.qml`.

- **NetworkManager** — `services/Network.qml` talks to it natively over
  D-Bus via `Quickshell.Networking` (device status, wifi scan/connect,
  signal strength); `nmcli` is still used, but only
  for DNS server management (no `Quickshell.Networking` equivalent
  exists), and `ip` (iproute2) for address lookup (`NetworkDevice
  .address` is the device's MAC, not its IP — also no equivalent).
  Without NetworkManager running, the Network tab and bar icon will just
  show "Disconnected".

- **PipeWire + WirePlumber** — `services/Volume.qml` and
  `services/Mic.qml` both read/write through
  `Quickshell.Services.Pipewire` (`Pipewire.defaultAudioSink`,
  `.defaultAudioSource`, `.nodes`). No PipeWire session manager running
  means no volume control, no OSD, no device list.

- **UPower** — `services/Battery.qml` reads `UPower.displayDevice`
  directly, and `UPower.devices` for the per-pack and peripheral lists
  the battery rail draws (`battery/BatteryPanel.qml`). On a desktop with
  no battery this just reports `available: false` gracefully; on a
  laptop, UPower not running means no battery readout at all. The device
  list enumerates over D-Bus a moment *after* first access, which is why
  the service names it at startup rather than leaving the panel to ask.

- **BlueZ** (`bluetoothd`) — `services/Bt.qml` uses
  `Quickshell.Bluetooth`, which talks to BlueZ over D-Bus. No adapter
  will be found without it.

- **sudo**, correctly configured for your user — `services/PrivilegedExec.qml`
  runs `sudo -S` for pacman install/uninstall and Flatpak system-scope
  uninstall, fed a password from `common/PasswordPrompt.qml`.

- **pacman** — package search in `installer/AppInstaller.qml`, install
  and uninstall in `packages/PackagesList.qml`. Present on any Arch
  install by definition.

- **flatpak** — same file; both user- and system-scope install/list/uninstall.

- **wl-clipboard** (`wl-copy`) and **cliphist** — clipboard history
  (`bar/ClipboardButton.qml`, `clipboard/ClipboardPanel.qml`, whose Wipe
  is `cliphist wipe`). Without `cliphist`
  actively watching the clipboard (usually wired into your Hyprland
  autostart as `wl-paste --watch cliphist store`), the history will
  just stay empty — this config reads history, it doesn't populate it.

- **brightnessctl** — `services/Brightness.qml`, all reads/writes.
  Needs a backlight device it can actually see; check with
  `brightnessctl -l -c backlight` if `Brightness.available` stays
  false.

- **coreutils / POSIX shell tooling** (`sh`, `cat`, `test`, `awk`, `sed`,
  `grep`, `printf`, `mkdir`) — used throughout via `["sh", "-c", "..."]` commands: hwmon
  discovery in `services/SystemMonitor.qml`, clipboard delete in
  `clipboard/ClipboardPanel.qml`, the file-existence check in
  `services/Notifications.qml`. Present on essentially any Linux
  install; called out because several files depend on them being on
  `$PATH` inside whatever shell Quickshell spawns.

## Required by default config values — swap via `config/Theme.qml` if you use something else

- **foot** — `Theme.terminal`, the fallback for `services/Terminal.qml`
  when the terminal picked in Setup › Defaults can't be resolved. foot,
  kitty, ghostty and alacritty are all handled there.

- **uwsm** — `Theme.appLauncherPrefix`, used to launch apps from
  `Launcher.qml` and to wrap the terminal launch above.
  `Theme.logoutCmd` also defaults to `uwsm stop`.

- **yay** — the AUR helper `installAur`/AUR search assume specifically;
  swap the literal `"yay"` string in `packages/PackagesList.qml` if you
  use `paru` or another helper.

- **awww** — `wallpaper/WallpaperSwitcher.qml`'s `applyWallpaper()`
  (`awww img ... && matugen image ...`). Pre-existing gap — never
  listed even though the wallpaper switcher
  itself long predates this file's own last full pass. Fails gracefully
  (a toast error, not a crash) if missing, but it's the one thing
  actually setting the wallpaper — swap the literal `"awww"` command in
  that file if you use `swww` or another wallpaper daemon.

## Read by the CLI tooling, not by quickshell itself

- **flock** (util-linux) — rig's lock module, which relay and rack sit on.

## Must NOT be running

- **A separate notification daemon** (`dunst`, `mako`, `xfce4-notifyd`,
  etc.) — `services/Notifications.qml` registers its own
  `NotificationServer` and claims `org.freedesktop.Notifications` on
  the session bus. Only one process can own that name; if something
  else grabs it first, notifications never reach this shell's history
  or popups. Check ownership with:
  `busctl --user status org.freedesktop.Notifications`

## Optional — config degrades gracefully without these

- **matugen** — `theme/WallpaperSource.qml` reads `~/.cache/matugen/colors.json`
  for wallpaper mode, and the shell uses the Default preset
  (`theme/palette.js`) while it's missing or malformed. matugen
  isn't invoked by the shell itself — `wallpaper/WallpaperSwitcher.qml`
  runs `matugen image` when a new wallpaper is applied, and this just
  watches the resulting file. See
  `matugen/config.toml` for the template that shapes that file.

- **MPRIS-compatible media player** — `bar/MediaPlayer.qml` collapses
  entirely (`visible: false`) when no player is active/playing, rather
  than showing a placeholder; no specific player required, just
  anything that implements the MPRIS D-Bus interface (which covers
  essentially every mainstream Linux media app).

- **StatusNotifierItem-compatible apps** — `bar/SystemTray.qml` simply
  shows nothing if no app registers a tray icon.
- Intel-specific GPU hwmon detection in `services/SystemMonitor.qml`
  (`i915`/`xe` sysfs paths) — silently shows "No Intel dGPU hwmon
  found" on anything else (AMD, Nvidia, no discrete GPU). CPU
  temp/usage/load still works regardless.

- **hyprsunset** — `services/NightLight.qml` drives it over `hyprctl
  hyprsunset` (`temperature 4500` for the warm filter, `identity` to
  clear it). `hypr/modules/autostart.lua` starts it as a long-lived
  daemon, same as awww-daemon and hypridle. Without it running the night
  light toggle still flips its persisted bool and still reads back as
  on — it just never warms the screen. That service deliberately keeps
  no state of its own (Settings.nightLight is the single source of
  truth, applied outward and never read back), so there is nothing in it
  that could notice the difference and say so.

- **rfkill** (util-linux, same package as `flock` above) —
  `services/AirplaneMode.qml` shells out to it both to read
  (`rfkill --output SOFT --noheadings`) and to block/unblock every
  wireless radio at once; Quickshell has no native binding for this the
  way it has for Bluetooth and NetworkManager. Without it the airplane
  toggle reads as off and does nothing when pressed: the read collects
  no lines, and no lines is indistinguishable from "no radio is
  blocked".

- **grim** and **slurp** — the screenshot path in
  `notifications/ScreenshotPopup.qml`. grim captures the whole screen,
  the focused output, or a region; slurp is the region select. These are
  the first of four tools Conf's Utilities rows name in `requires:`:
  `menu/MenuActions.qml` probes PATH once per menu open — they come and
  go with `pacman -S`, and the menu is exactly where someone goes right
  after installing one — and a row whose tool is missing draws dimmed,
  reads "needs <tool>", and refuses to run rather than silently doing
  nothing. Escaping out of slurp exits 3, which is read as "no
  screenshot wanted" rather than as a failure.

- **wf-recorder** and **pkill** (procps-ng, *not* coreutils) — screen
  recording in `menu/MenuActions.qml`. wf-recorder runs until something
  signals it and the menu row is the only stop control, so pkill is as
  load-bearing as the recorder: it sends `-INT` specifically, because
  `-TERM` leaves the container unfinalised and the file unplayable.
  wf-recorder is not installed on this machine today, which is the case
  the `requires:` guard above was built for.

- **hyprpicker** — the colour picker in `menu/MenuActions.qml`. `-a -f
  hex` puts the hex on the clipboard itself and prints it, so the
  notification is the only sign it worked; nothing else on screen
  changes. A cancelled pick exits non-zero with empty stdout and is
  deliberately silent.

- **jq** — `notifications/ScreenshotPopup.qml` pipes `hyprctl
  activewindow -j` and `hyprctl monitors -j` through it to find the
  geometry for the window and screen captures; without it those two
  variants fail (with a toast) while a region capture still works. Also
  used outside the shell: `rack settings` parses `rack/schema.json` and
  the `settings.json` written by `services/Settings.qml`, and relay's
  `notif`, `network` and `bluetooth` modules use it for `--exec` vectors
  and `--json` output.

- **curl** and network access to **api.open-meteo.com** —
  `services/Weather.qml` fetches the forecast every 15 minutes (a minute
  after a failure). Without either the bar's weather module never gets a
  first reading and stays hidden; after one, it keeps showing the last
  good forecast.

  The location is per-machine and gitignored: `quickshell/main/.env`
  needs two lines like these (London, as an example):

  ```
  WEATHER_LATITUDE=51.5074
  WEATHER_LONGITUDE=-0.1278
  ```

  with your own coordinates in their place. Without it the module stays
  hidden, same as with no network.

## Fonts

- **JetBrainsMono Nerd Font** (`Theme.font`) — must be the actual
  Nerd Font *patched* variant, not plain JetBrains Mono. Icons
  throughout the bar and panels use both standard Font Awesome
  codepoints (`\uf0xx` range — network, volume, battery, power, etc.)
  and Nerd-Font-specific private-use glyphs (the battery icons in
  `Battery.qml` are literal glyph characters, not escape codes) that
  only resolve with a genuinely patched font installed. `Theme.fontHeading`
  (the "Classical" plate system's headers/monogram letters/
  settings-window labels) reuses this same font rather than
  a separate display face — no second font dependency for that.
