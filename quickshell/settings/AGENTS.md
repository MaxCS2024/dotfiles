# Settings

The settings window on its own (`qs -c settings`, in
`~/.dotfiles/quickshell/settings`, linked to `~/.config/quickshell/settings`
by the rack manifest, started at login by `hypr/modules/autostart.lua`),
like the clipboard and the launcher: it opens whatever shell runs.
SUPER+COMMA (`quickshell:settings-toggle`), `settings.desktop` and
`qs -c settings ipc call settings open|focus|close|toggle` reach it.

Split out of the dynamic-island on 2026-10-13, at the user's request,
when the brief-built `quickshell/island` (which has no settings by its
brief) replaced it at login. The design below is the dynamic-island
brief's "Settings window" section as it stood then; read "the island"
in it as the dynamic-island, whose pill pages and gear no longer lead
here. `../STYLE.md` applies too, unless a section below overrides it.

What came along, and what stayed behind:
- All six sections and their files, unchanged, and `bt-agent.py`.
- `Controls.qml` cut down to network, Wi-Fi, Bluetooth, battery and the
  power profile; the pill's notices, OSD, shortcuts and IPC stayed.
- `QuickSettings.qml` cut down to Stay awake (which the Power page's
  idle timers honour) and Night light (put back at login); nothing here
  turns either on or off now that the pill's quick row is gone. Do not
  disturb and the microphone toggle stayed behind.
- Its login jobs run again with this config: a display trial left
  unconfirmed is reverted, the saved battery charge limit is written
  back if a battery forgot it, the saved night light is put back.
- Settings are still saved in `~/.local/state/dynamic-island/settings.json`
  (and `hypr/local.lua`), so nothing saved before is lost.
- The shortcut is `settings-toggle`, not the dynamic-island's
  `island-settings`: Hyprland drops a client that asks for a shortcut
  another already holds, so the two can run side by side.

## The window

The deeper settings, which don't fit the pill: a normal Hyprland window
(`SettingsWindow.qml`, a Quickshell `FloatingWindow` titled "Settings"),
not a panel. It opens floating and centred at 880 × 600 (window rule in
`~/.dotfiles/hypr/modules/windowrules.lua`); the usual float toggle tiles
it, so it can sit at the side of the screen.

Opening: SUPER+COMMA (the global shortcut `quickshell:island-settings`,
bound in `~/.dotfiles/hypr/modules/binds/apps.lua`) opens it if it is
closed, focuses it if it is open but not focused, and closes it if it is
focused. `settings.desktop` (in this folder, linked into
`~/.local/share/applications/island-settings.desktop` by the rack
manifest) puts "Settings" in the launcher. IPC:
`qs -c dynamic-island ipc call settings open <section>` (empty for the
last one), `focus`, `close`, `toggle`. There is only ever one window; it
reopens on the section it was last on. If `shown` says open but Hyprland
has no Settings window (closed from outside without `visible` turning
false), focusing makes a new one; the window once stayed unreachable. It stays open when the island
hides with the main bar.

Layout: a sidebar of the six sections (Displays, Sound, Network,
Bluetooth, Power, Input), the section's page to its right, with a 1px
line at white 12% between them, the window's full height, 16px from the
sidebar and 32px from the page. Below 640px
wide (tiled at the side) the sidebar shrinks to its icons. The island's
look, not `Appearance`: black, white text, bold JetBrainsMono, round
pills (`ListRow`, `Toggle`, `Slider` and `PageHeader` reused where they
fit). The sidebar row is a 40px round pill like `ListRow`: no fill at
rest, white at 12% while hovered, solid white with black text for the
current section.

Changes take effect at once and are saved straight away (toggles and
sliders), except on Displays, which stages them behind Apply.

**Keyboard:** the whole window works from the arrow keys, in two
places: the sidebar, then the page. It opens with the keys in the
sidebar, where ↑ ↓ (Home, End) switch the section at once: the solid
white row moves and its page shows, with no separate highlight (the
user's choice). → (or Enter, Tab) goes into the page, on the control
the keys left it from, else the first. In the page ↓ ↑ (Tab, Shift+Tab)
go from control to control in the order they are built, stopping at the
ends, and scroll it into view; ← (or Escape) goes back to the sidebar
from anywhere in it, except while something holds the keys (below) or a
text field's cursor isn't at its start. Enter or Space press the focused
control: a row, a button, a switch, a volume row's mute button, a
screen on the Displays canvas (selects it; moving screens is the
mouse's). Sliders and Segmented rows are grabbed first, so ← keeps
meaning back: Enter or Space grabs one, then ← → move it (a slider by
5%, or one step if coarser; a Segmented row moves its highlight), and on
a slider Enter, Space or Escape let go; on a Segmented row Enter or
Space picks and Escape lets go without picking. A Choice unfolds on
Enter, ↑ ↓ move through it, Enter picks, Escape folds. So no arrow
changes a setting unless a slider is grabbed. While Displays asks "Keep
these display settings?" the keys stay in that dialog, and after an
Apply pressed from the keys they start on Revert, the safe answer if
the screen went wrong. The Network and Bluetooth pages start scanning
(and Bluetooth its agent) half a second after they show, so passing
over them with ↑ ↓ scans nothing.

The focused control is lit well above hover: white at 32%
(`SettingsWindow.focusFill`; hover stays 12–20%), and one that is
already solid white dims to 60% (`focusSolid`). A setting in a row
lights the whole row instead, a 40px round pill like a focused ListRow
(the user liked those best): a SettingRow (its name now 16px in, its
control 8px in, so the pill has room), a volume row (now 40px, mute
button 4px in, percentage 16px in), a Sound app row, an Input layout
row. In such a row (`keyRow`, `SettingsWindow.inKeyRow`) the control's
own focus fill stays off, except a button's (Turn off, Rename, mute,
the layout arrows), which shows on top, since a row can hold several
stops; a grabbed slider's circle (60%) and a grabbed Segmented row's
highlight still show. Every switch is in a row (Wi-Fi and Bluetooth's
once sat beside their headings). Outside a row: a switch would sit on a 48 × 32 pill
and a slider's knob on a 24px circle at 32%, a text field's pill lifts
to 32%. Each page's Flickable reaches 8px past the page on the right
(its content doesn't), so a switch's pill at the right edge isn't
clipped. Never a ring (STYLE.md §1). This shows only once the
keys have been used, and a click hides it again
(`SettingsWindow.keyboard`), so with the mouse the window looks as
before. How: a control opts in with `navigable: true` and handles its
own keys; the page's Keys moves between them (`win.controls()`), and an
open dialog marks itself `navTrap`. Focus that is lost (a row rebuilt,
a control hidden) falls back to a FocusScope around everything, which
sends the next arrow back where the keys were.

Testing the keys: `wtype -k Down` with the window focused, one key per
`wtype` and a pause (0.4s) between them: sent back to back, a key
sometimes arrived as another one. Open the section wanted over IPC
rather than counting ↑ ↓ presses (a miscount once pressed Enter on the
wrong page). Only arrows, Tab and Escape, plus Enter to grab and Escape
to let go; never Enter on another control, and never ← → on a grabbed
slider.

**Saving:** per machine, never into the shared dotfiles.
`~/.config/hypr/local.lua` (in the dotfiles folder but ignored by git) is
loaded last by `hyprland.lua` when it exists, so its `hl.monitor` and
`hl.config` calls override the repo's defaults; the window writes it.
The idle timers go to `~/.config/hypr/hypridle.local.conf` (also ignored
by git), which `hypridle.conf` sources (see How Power works).

**Sections** (built one at a time, in this order; a section not built yet
shows its name and "Not built yet"):
1. **Displays.** An arrangement canvas (the screens as rectangles, dragged,
   snapping edge to edge); for the selected screen: on/off, resolution,
   refresh rate, scale (1, 1.25, 1.5, 1.75, 2), rotation, "mirror of…".
   No VRR, 10-bit or HDR. Settings are kept per monitor, by its
   description (`desc:…`), so Hyprland reapplies them whenever that
   screen is connected; plus one rule, "laptop screen off while an
   external screen is connected". Changes wait for Apply; after Apply
   a change to resolution, refresh rate, scale, rotation, on/off or
   mirroring asks "Keep these display settings?" and reverts after 15
   seconds without an answer (moving a screen doesn't ask). Plugging in
   a screen flashes "Display connected – <name>" on the island; a click
   on the flash opens Displays.
2. **Sound.** Output and input device lists, each with volume and mute,
   an input level meter, and a per-app volume mixer. No Bluetooth
   profile switching (HFP froze the Intel adapter; the earbuds stay in
   A2DP).
3. **Input.** Keyboard layouts and the key that switches them, repeat
   delay and rate; touchpad tap to click, natural scroll, speed, disable
   while typing; mouse speed and acceleration. Global, not per device.
4. **Power.** The power profile; lock after, screen off after, suspend
   after (Never, 1–30 minutes); a charge limit, made writable by a new
   udev Patch (`rack patches`) so no password is asked. The lid action
   is left out (logind, root).
5. **Network.** Wi-Fi on/off, the list and connecting (as on the island's
   page); Join hidden network…; on/off for the VPN connections
   NetworkManager already has (creating them is left to `nmcli`); wired
   status. No saved-networks list: the user found it of no use and had
   it removed (with it went Forget, Connect automatically, the IP
   details and the custom DNS).
6. **Bluetooth.** Adapter on/off, discoverable, paired devices with
   connect, Forget and Rename, battery levels, and pairing with a code
   through a small agent helper that runs only while this section is
   open (Quickshell can't be the agent).

How Displays works (`Displays.qml`, a singleton so a countdown outlives
the window; `DisplaysPage.qml`; `LocalConfig.qml` for the files):
- It reads `hyprctl monitors all -j`, again on Hyprland's
  monitoradded/monitorremoved/configreloaded events, whenever Qt's list
  of screens changes, and each time the page opens (unless there are
  edits not applied). A screen whose DRM connector reads
  "disconnected" in `/sys/class/drm/card*-<name>/status` is left out:
  Hyprland can keep an unplugged screen in `monitors all`, disabled. The
  page edits a copy (`staged`); "Not applied yet", Reset and Apply sit at
  the bottom right.
- The refresh-rate row says "Up to 60 Hz at 2560 × 1440" when another
  resolution's best rate is at least 10 Hz higher: the list only has
  what Hyprland offers, and a link can cap it (the T480's HDMI 1.4 port
  carries 4K at 30 Hz at most; 4K at 60 Hz needs its USB-C port with
  DisplayPort).
- The canvas draws each screen at its logical size (mode ÷ scale,
  swapped when rotated 90° or 270°); screens that are off or mirroring
  sit dimmed in a row to the right. A dropped screen snaps to the
  nearest free edge of another, aligning to its start, centre or end
  within 15%; the layout is then shifted so its top-left is 0x0. A
  size change pushes screens past its right or bottom edge along. The
  last screen in the layout can't be turned off or made a mirror.
- Apply runs `hyprctl reload` after writing `local.lua`. In Hyprland the
  newest matching monitor rule wins, so local.lua (loaded last) beats
  `monitors.lua`; rules use `desc:` (the port name when a screen has no
  description). A move-only Apply saves straight away. Anything else is a
  trial: the old local.lua goes to `local.lua.bak` and the dialog counts
  down; Keep saves the JSON and deletes the backup, Revert or 0 rebuilds
  local.lua from the kept settings and deletes it. A backup found when
  the island starts (it stopped mid-countdown) is put back.
- "Laptop screen off when docked" is Lua inside local.lua, so it works
  without the island: `hl.on("monitor.added"/"monitor.removed")` re-checks
  `hl.get_monitors()` (enabled screens only), ignoring mirrors and the
  screen being removed, and sets the laptop rule's `disabled`.
- The island's flash comes from `Displays.connected(label)`: an external
  screen new since the last reading, not within 5 seconds of an Apply
  or revert. Label: the model, or the description when the model is a
  hex code; a laptop panel is "Built-in display".

Testing Displays: check the generated file with a temporary IpcHandler
returning `LocalConfig.lua(Displays.settingsFromStaged())` and `luac -p`,
and the docked rule by running it under plain Lua with a fake `hl`.
A fake second screen can be put into `live`/`staged` the same way to
look at the canvas. Never call `apply()`.

How Sound works (`SoundPage.qml`, `VolumeRow.qml`): headings Output,
Input and Apps (bold 16px). Output and Input each have a `VolumeRow`
for the default device (a 32px round mute button with the speaker's
off/low/medium/high glyph or the microphone, the island's Slider, the
percentage; capped at 100%, muted reads 0%, dragging up unmutes), then
the devices as `ListRow`s, the default solid white; a click sets
`Pipewire.preferredDefaultAudioSink`/`Source`, which WirePlumber
remembers. Device glyph: headphones for Bluetooth or a headset,
a monitor for HDMI/DisplayPort, else a speaker or a microphone. Under
the input's track, a 2px line at 60% shows `PwNodePeakMonitor.peak`
as it comes (Quickshell already takes the cube root of the sample
peak); it only runs while the page is shown. Apps: every stream that
feeds a sink (`isStream && isSink`; the node properties don't always
carry `media.class` yet), with the app's icon (or a music note), its
name and what it plays (`media.name`, 60%), and its own VolumeRow;
"No app is playing sound" when there are none.

Testing Sound: open it and look. A silent stream shows the Apps row
without making a sound or changing a volume:
`timeout 6 pw-cat --playback --raw --format=s16 --rate=48000 --channels=2 /dev/zero`.

How Input works (`InputSettings.qml`, a singleton; `InputPage.qml`,
`ValueSlider.qml`): values not saved yet are Hyprland's own, read with
`hyprctl repl` and `hl.get_config`. A change goes into `draft` and is
saved 400ms after the last one (`LocalConfig.saveInput`, then
`hyprctl reload config-only`, so the monitors aren't touched), into
`input` in settings.json and an `hl.config({ input = … })` block in
local.lua. Only keys the user has set are written.
- Keyboard: the layouts as rows, the first one used at login ("At
  login"), an up arrow to make another one first and a cross to remove
  any but the last; "Add layout" turns into a search field over the 99
  layouts of `evdev.lst` (exact code first, then names starting with
  the search, then shorter names), five rows, Enter takes the first.
  Writes `kb_layout`, an empty `kb_variant` per layout, and `kb_options`
  as the switch key alone (the repo's is empty); with two or more
  layouts it is always written, Alt+Shift unless another was picked,
  since the page shows Alt+Shift as the default (it once wasn't written,
  and Alt+Shift did nothing). Switch keys: Alt+Shift,
  Ctrl+Shift, Caps Lock, Both Shifts; not Win+Space (SUPER+SPACE is
  Conf) or Right Alt (Swedish needs AltGr). Repeat delay 150–1000ms,
  rate 10–60/s, each with a restore-arrow button left of its slider,
  shown only while the value is changed: it takes the key out of
  local.lua, and the values are read again after the reload. The
  slider goes straight to Hyprland's default (600ms, 25/s, in
  `InputSettings.defaults`); reading the runtime value instead made it
  jump to the default, back to the old value, and to the default again.
- Touchpad (shown when udev finds one, `ID_INPUT_TOUCHPAD`): tap to
  click, natural scrolling, disable while typing, speed. Hyprland has
  no touchpad-wide speed, so each touchpad found gets
  `hl.device({ name, sensitivity, accel_profile = "adaptive" })`; its
  name is udev's lower-cased with dashes (`synaptics-tm3276-022`).
- Mouse: speed (`input.sensitivity`, which also moves the TrackPoint)
  and acceleration (`accel_profile` "adaptive" or "flat"). Speeds show
  -100…+100, 0 as "Default".

`LocalConfig` during a display trial: an input save leaves the
`local.lua.bak` backup alone and goes into the trial; Revert rebuilds
local.lua from the kept settings (so it keeps the input change), Keep
saves both. Checked by running its shell steps against scratch folders
with `hyprctl` swapped for `echo`.

How Power works (`PowerSettings.qml`, a singleton; `PowerPage.qml`):
- Power mode: the island battery page's rows (`Controls.profiles`).
- Main's "Stay awake" (an idle inhibitor on its bar) pauses all three
  timers, and so does the island's own (Quick settings). While either
  is on (`qs -c main ipc call awake state`, `QuickSettings.stayAwake`),
  a row above them says so, with "Turn off" (ends both). It once made
  "Lock after: 1 minute" look broken.
- When idle: Lock after, Screen off after, Suspend after, each a Choice
  of Never, 1, 2, 3, 5, 10, 15, 20, 30 minutes (plus the current value
  when it is none of them, like the default 5.5 minutes). A pick saves
  at once (`LocalConfig.savePower`): `hypridle.local.conf` gets
  `$lock_after`, `$screen_off_after`, `$suspend_after` in seconds, empty
  for never, and hypridle is restarted (`pkill -x hypridle`, then
  `setsid -f hypridle`; it reads its config only at start). In
  `hypridle.conf` (dotfiles) the defaults are variables (300, 330,
  empty), the local file is sourced inside `# hyprlang noerror`, and
  each listener sits in `# hyprlang if <var>`, so an empty value drops
  it. Suspend runs `systemctl suspend`.
- Battery › Charge limit: Off (100), 90%, 80%, 60%, written to every
  `/sys/class/power_supply/BAT*/charge_control_end_threshold` (the T480
  has two batteries). Those files are root's until the "Battery charge
  limit" patch (`~/.dotfiles/udev/92-battery-charge-limit.rules`, `rack
  patches`) hands them to wheel at boot; without it the row says so and
  "Install patch" runs `rack patches install battery-charge-limit` in
  the default terminal (`relay default exec terminal`), then reads the
  files again. relay joins the words after `--` into one shell command
  line, so the command is passed as one word; passed as `sh -c '…'`
  words it ran a bare `rack` and installed nothing. The limit is saved too, and written back at startup if a
  battery has lost it.

Testing Power: open it and look. Check a generated hypridle file by
parsing it with a throwaway `hypridle -c` whose general block sets
`ignore_dbus_inhibit` and `ignore_systemd_inhibit` (it logs "Registered
timeout rule" per listener), for 2 seconds. Never restart the real
hypridle or write a threshold to check.

How Network works (`NetworkSettings.qml`, a singleton over nmcli;
`NetworkPage.qml`; `Field.qml`, the 40px text pill): NetworkManager lets
the user change system connections without a password
(`settings.modify.system: yes`); VPNs are switched by UUID, since names
can hold spaces and colons (nmcli -t escapes them; `fields()` undoes it).
- Wi-Fi: the heading, a "Use Wi-Fi" row with the radio's switch, then
  the networks in range
  as on the island's page (`Controls.wifiNetworks`; the window scans
  with its own `Controls.windowWifiScan`, so the island page closing
  doesn't stop it). A secured network never joined asks for its
  password in a field under the list. "Join hidden network" opens a
  name and a password field (`nmcli device wifi connect … hidden yes`).
- VPN: one row with a switch per vpn or wireguard connection
  NetworkManager has; none: "No VPN connections (add one with nmcli)".
- Wired: each ethernet device, "Cable unplugged", its address, or its
  state.
- While the page is open, `nmcli monitor` refreshes it on any change. A
  failed action shows nmcli's message at the foot of the page.

Testing Network: open it and look; never connect or toggle a VPN to
check. A shell step can be checked with a fake `nmcli`
earlier on PATH that prints its arguments.

How Bluetooth works (`BluetoothSettingsPage.qml`; `bt-agent.py`):
- Adapter: under the heading, a "Use Bluetooth" row with the switch, and
  "Visible to other devices" (the adapter's
  `discoverable`, "As <adapter name>").
- My devices: the paired ones (`Controls.bluetoothDevices`), connected
  ones solid white, "Connected – 80%" with a battery. A click opens
  under it: Name (a field filled with the current name, Rename sets the
  BlueZ alias through the device's writable `name`; empty goes back to
  its own `deviceName`, shown as "Its own: …" while renamed), Connect or
  Disconnect, and Forget, which takes two presses.
- Other devices: named devices in range, "Pair" (`Controls.useDevice`:
  trusted, paired, connected once bonded), "Pairing…", "Failed".
  Discovery is the island's, at most 30 seconds (A2DP stutters under a
  scan), with its own flag (`Controls.windowBluetoothScan`); after it,
  "Search again".
- The pairing agent: `python3 -I bt-agent.py` runs while the section is
  open (a Process on the page; closing the window ends it and it
  unregisters). It registers as BlueZ's default agent with the
  KeyboardDisplay capability and speaks JSON lines (the protocol is at
  the top of the script). Its questions show in a box under the adapter
  rows: "Pair with X?" with the six-digit code and Cancel/Pair, a PIN or
  passkey field with Send, or "Type this code on X" with Done. Services
  of paired devices are allowed without asking. It needs python-dbus and
  python-gobject (here pulled in by python-validity); without them the
  page says "Pairing with a code is unavailable: …" and the rest works.

Testing Bluetooth: open it and look, and close it again soon (it scans).
Never pair, connect, forget, rename or switch the adapter to check. The
agent's answers can be tested without BlueZ: import the script, make an
`Agent` on the session bus, call its methods with stand-in reply/error
callbacks, then `answer()`.

Then the island hooks (built): the gear in the header of the island's
Wi-Fi, Bluetooth and battery pages (see Settings pages).

Restarting: close the settings window first (`ipc call settings close`),
then `qs kill -c dynamic-island`, then `qs -n -c dynamic-island -d`
(`-n`: refuse to start a second copy), and check `qs list --all` shows
exactly one. Killed with the window open, Quickshell 0.3.1 segfaults on
the way out (in libwayland) and its crash handler starts the old
config again. Two copies once ran side by side, and SUPER+COMMA opened two
windows, one per copy.

Testing: open the window and its sections over IPC and look. Never press
Apply on Displays, and don't change the volume, input, idle times,
Bluetooth or the charge limit to check a section; the user tries those.

# Decisions

- 2026-10-13: split out of the dynamic-island into its own config, like
  the clipboard, at the user's request ("so it can be used like the
  clipboard"). A copy: the dynamic-island keeps its own window.
