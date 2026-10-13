# Dynamic island

A standalone Quickshell config (`qs -c dynamic-island`, in
`~/.dotfiles/quickshell/dynamic-island`, linked to
`~/.config/quickshell/dynamic-island` by stow (`stow quickshell`), and the
shell started at login by `hypr/modules/autostart.lua`, in place of
main): a bar for
Hyprland that shows the time, the current song when dragged right, or
the date and battery when dragged left, and
briefly swaps to the workspace name whenever the workspace changes, to
the volume or brightness when they change, and to a battery notice when
the charger goes in or the battery runs low, and to a live waveform
for as long as dictation (voxtype, SUPER+V) listens. A
left click expands it into a media player, a right click into a small
settings panel (network, Bluetooth, volume, battery, and the volume and
brightness sliders, with a Wi-Fi page and a Bluetooth page for
connecting and a battery page for the power mode), a middle click into
a power menu. SUPER+COMMA opens the settings window, a normal Hyprland
window for the deeper settings (displays, sound, network, Bluetooth,
power, input).

This file is the design brief. Read it before creating or changing anything
here. `../STYLE.md` applies too, unless a section below overrides it.
A section marked _TBD_ is undecided: ask the user, and record the answer
here before building it.

## Scope

The island is the user's alternative to the main bar: with a launcher
(fuzzel), the clipboard and its own settings window it runs as a complete shell
with main never started. The pill must stay small. Check every request
against this section first. Something that falls outside it is raised
with the user, not built.

**The rule:** the pill shows what is happening now and reacts to
changes. It doesn't manage the system. The exceptions are connecting
to a Wi-Fi network or a Bluetooth device and picking the power profile
(see Settings pages). Deeper management belongs to the settings window
(see Settings window), not the pill.

**Standalone:** it works with the main bar never started. It may follow
main when main is running (hiding with the bar), but nothing it shows or
does may need main.

**In scope:**
- The time, the "Workspace N" flash, the volume/brightness OSD and the
  battery notices.
- The dictation face, while voxtype records or transcribes.
- The privacy dots and their notices (see Privacy indicators).
- The song view and the media player.
- The today view: the date and the battery.
- The settings panel: the fused pill, the two sliders and, under its
  notch, the quick settings row (Stay awake, Do not disturb, Night
  light, microphone). It is frozen; a new button or row needs a decision
  here first.
- The Wi-Fi and Bluetooth pages, for connecting only, and the battery
  page, for the power profile only.
- The power menu (with main gone, it is the only one).
- The wallpaper gallery (SUPER+ALT+W; see Wallpaper gallery).
- The settings window: Displays, Sound, Network, Bluetooth, Power and
  Input, and nothing else (see Settings window).

**Limits (the pill):**
- Two levels at most. A gesture opens one small panel; only the settings
  panel's network, Bluetooth and battery segments go one level further,
  to their page. A page's only way further is its header's settings
  button, which opens the settings window on the matching section.
- Lists, scrolling and typing only on those pages: the network and
  device lists and the Wi-Fi password field. Anything more (hidden
  networks, VPNs, a pairing code, device settings) belongs to the
  settings window.
- Panels stay about 360px wide or less and use the shared open/close
  sequence. The wallpaper gallery is the exception: three images wide,
  as tall as its row.

**Out of scope:** settings for the island itself (time format, OSD on or
off, …), colour themes (main's palettes and matugen theming), a
workspace overview, Conf's sections (Install, Features, Update, Defaults, Style:
Conf is to be split out of main into its own config, like the launcher),
weather, system stats (CPU, RAM, temperature), a song-changed flash,
Bluetooth devices' low-battery flashes, the app
launcher (fuzzel) and clipboard (its own config), and a calendar.

**Undecided, _TBD_:**
- Notifications. Showing them would mean the island running the
  notification daemon when main isn't running. The user likes the idea
  but doesn't use notifications much yet.
- How notifications look: dunst's default until everything else is
  settled; designing them comes last.
- Main's other keys with nothing behind them (the notification and
  network rails, themes) aren't missed for now. Conf isn't needed: the
  user wants the island minimal. The media keys and Print went to
  Hyprland (playerctl; grim, slurp and wl-copy), so they need no shell.

## Look

- Position: top centre of the screen, 7px from the top. It reserves 31px
  (24 plus that margin) so windows tile below it, their border 7px under
  the pill once Hyprland's gaps are added, the same as the gap above; an
  open panel overlaps them. While main's bar is on screen (its
  `quickshell:bar` layer, counted in `Controls.mainBarUp`) the bar
  reserves the strip instead and the island sits over it, since
  reserving both would stack the island below the bar.
- Shape: a single fully rounded pill (radius = height / 2). This overrides
  `STYLE.md` §5's 2px corners. As the player it keeps a 32px radius
  (`min(height / 2, 32)`).
- Size: the width grows and shrinks to fit whatever the island is showing,
  with 32px of padding on each side of the text. Every compact view (time,
  song, today, workspace) uses this one value, `pill.padX`. The OSD face
  is the exception, at 24px (`pill.shownPadX`).
- Type: JetBrainsMono Nerd Font, Bold (`Font.Bold`) everywhere,
  including the player's title.
- Colours: white text on a black background. This overrides `STYLE.md` §2;
  the island doesn't use the `Appearance` tokens.
- Time format: `18:32` (24-hour clock, no weekday).
- Workspace label: always "Workspace N", from the workspace id (1–9).
  A workspace's own Hyprland name is never shown.

## States

The island shows one thing at a time.

| State     | Trigger                    | Content                  | Width       |
|-----------|----------------------------|--------------------------|-------------|
| resting   | default; dragging the pill left | time, `18:32`       | fits the text |
| media     | dragging the pill right    | music note + "Title – Artist" | fits the text, at most the 400px window |
| today     | dragging the pill left     | date and battery, `tors 8 okt – [battery] 46%` | fits the text |
| player    | left click (press without moving 4px) | media player | 360 × 128 |
| settings  | right click                | network, Bluetooth, volume and battery fused in one pill, volume and brightness sliders; the quick settings row under the notch | 360 × 156, 360 × 208 with the row |
| wifi      | settings panel's network segment | Wi-Fi page: header, networks | 360 × 288 |
| bluetooth | settings panel's Bluetooth segment | Bluetooth page: header, devices | 360 × 288 |
| battery page | settings panel's battery segment | battery page: header with the charge, power profiles | 360 × 200 |
| power     | middle click               | lock, reboot, log out, power off orbs | 304 × 88 |
| wallpaper | SUPER+ALT+W                | wallpaper gallery        | three images × its row (757 × 178) |
| workspace | switching to any workspace | "Workspace N"            | fits the text |
| osd       | volume or brightness changes | icon, percentage, filling ring | one width for 0–100% |
| battery   | charger plugged in; battery below 20%, 10% or 5% | battery icon + "Charging – 46%", "Low battery – 18%" or "Battery critical – 4%" | fits the text, at most 400px |
| layout    | keyboard layout switched   | keyboard icon + "Layout – English (US)" | fits the text, at most 400px |
| caps      | Caps Lock toggled          | Caps Lock arrow + "Caps Lock – on" or "– off" | fits the text |
| display   | external screen plugged in | monitor icon + "Display connected – XV280K" | fits the text, at most 400px |
| notice    | network up, failed or lost; Bluetooth device in or out | icon + "Connected – Telia-3D6C57" and the like | fits the text, at most 400px |
| dictation | voxtype recording or transcribing (SUPER+V) | cancel button, live waveform, stop button | 144, fixed |

The three views sit in a row, song | time | today. A drag right moves one
view to the left, a drag left one to the right; there is no wrap-around.
Dragging means pressing on the pill and moving more than 48px. A view stays
until dragged away. With no player the song view is still reachable and
reads "[music note] Nothing playing". The player is whichever one is playing,
else the first with a title. A title too long for the pill is cut with "…".

After a workspace switch, the island shows "Workspace N", then returns
to the time (or the song) on its own after 1.5 seconds. The switch slides
whatever text is up (the time, song or today view, or an earlier
"Workspace N") out and the new name in beside it (16px apart, 160ms,
OutCubic, the old text fading as it goes), the way the drag views move:
to a higher number the text moves left and the name comes in from the
right, to a lower number it moves right. A switch during the 1.5 seconds
restarts the timer. Two labels (`workspaceLabelA`/`B`) take turns for
this; `root.workspaceLabel` is the current one. From the OSD or battery
face, with a panel open, or mid-drag, the name fades in instead. The
return to the view after 1.5 seconds is still a fade.

## OSD face

Any change to the volume (mute included; muted reads 0%) or the screen
brightness, from keys, the main bar or anything else, shows the OSD face
for 1.5 seconds after the last change, over whatever view is up; then
that view fades back. Left: the speaker icon (off / low / medium / high,
`Controls.volumeIcon`, shared with the settings slider) or the sun
(`Controls.brightnessIcon`) at 16px; 8px on, the percentage, bold 13px,
left-aligned in the width of "100%" so the circle never moves. Right,
8px past that width: a 16px ring, 3px thick and white at 20%, with a
white arc growing clockwise from 12 o'clock to the value, easing 120ms
between readings. The middle stays empty. The newest flash wins: a
workspace switch replaces it and it replaces "Workspace N". Not shown
while a panel is open (the settings sliders cover that) or mid-drag.

`Controls.changed(kind, value)` drives it; it stays quiet for the first
2 seconds while readings arrive. The volume and brightness keys also fire
it on every press (and every brightness ramp step), with the current
value, through two Hyprland global shortcuts the island registers in
`Controls.qml`, `quickshell:island-osd-volume` and
`quickshell:island-osd-brightness`, dispatched from
`~/.dotfiles/hypr/modules/binds/media.lua`. So a press at 100% (or 0%),
which changes nothing, still shows the face. Brightness is polled every 0.5s, and
every 50ms for 1.5 seconds after a change, so a held key keeps up.

Testing: emit `Controls.changed` from a temporary IpcHandler, or
`hyprctl dispatch 'hl.dsp.global("quickshell:island-osd-volume")'`
(shows the current value, changes nothing); never change the real volume
or brightness.

## Battery notice

Plugging in the charger shows "Charging – 46%"; the battery dropping
below 20%, and again below 10%, while on battery power shows "Low
battery – 18%", and below 5% "Battery critical – 4%", which also sends
a critical notification (see System alerts). Both start with `Controls.batteryIcon` at 16px, 8px
before the bold 13px text, and stay for 3 seconds, twice as long as the
other flashes, since nothing the user did caused them. Unplugging shows
nothing. Like the OSD it obeys "the newest flash wins", isn't shown while
a panel is open or mid-drag, and pressing the pill drops it.

`Controls.batteryNotice(kind)` drives it ("charging", "low" or
"critical"), quiet for the first 2 seconds; "critical" also fires then
if the battery is already under 5% on battery power. "Charging" follows UPower's `onBattery` going false,
not the charging state, which can flip back and forth around the
battery's charge thresholds.

Testing: `test-notices.sh` (see Testing the notices); don't unplug
anything.

## Notifications

Notifications are their own thing, not the island's: dunst answers
`org.freedesktop.Notifications` (unmasked 2026-10-10; D-Bus starts it on
the first one), so they work whichever shell runs, with dunst's default
look for now. App notifications go there too; the user doesn't mind how.
The system ones the user cares about the island shows itself, in the
pill, from what it watches: the battery notices, "Display connected",
the layout, and the network and Bluetooth notices below.

**The rule** (decided 2026-10-11): the pill is for system state the
island watches itself, a flash of 1.5–3 seconds that needs no answer.
A regular notification (dunst) is a message from an app or a tool:
something to read, maybe act on, or that the island can't see. Nothing
shows in both places, so nothing that sends its own notifications for
what the pill already shows (nm-applet, blueman) is run.

Regular notifications:
- Apps: messages, reminders, finished downloads ("Anna – are we still
  on for tonight?", "Download complete – report.pdf").
- The user's own tools, rack and relay: results and failures only, never
  progress ("Dotfiles synced", "Update failed – click for the log",
  "Screenshot saved"). `relay notif send` goes straight to D-Bus, so
  dunst shows them; the glyph hint is main's and dunst ignores it.
- The Print keys (Hyprland's, `hypr/modules/binds/media.lua`):
  "Screenshot copied – Saved in Pictures/Screenshots as <file>", the
  capture as the thumbnail, through `notify-send`. Hyprland's own
  notification said it before.
- System problems that need the user, never status readouts: "Disk
  almost full – 2.1 GB left on /", and "Battery critical – 5%", the one
  event shown in both places, since a 3-second flash is easy to miss
  with the laptop about to die. Both are the island's (`Alerts.qml`,
  see System alerts).

Never a regular notification: anything the pill shows (network,
Bluetooth, charging, display, layout, volume, brightness), and progress
("Syncing…", "Connecting…"): only the result.

| Urgency  | For                                         | Timeout          |
|----------|---------------------------------------------|------------------|
| low      | done, nothing to do (synced, screenshot)    | 3 s              |
| normal   | messages, reminders, downloads              | 5 s              |
| critical | failures, critical battery, disk full       | until dismissed  |

How they look stays dunst's default until the rest is settled.

## System alerts

`Alerts.qml` sends the two system problems as regular notifications
(`notify-send -u critical`, so dunst keeps them until dismissed) and
takes each back by id once the problem is gone. A newer reading
replaces the open one (`-r`) instead of adding a second.
- Battery critical: Controls' "critical" battery notice (on battery,
  dropping below 5%, or already under it when the island starts) flashes
  "Battery critical – 4%" in the pill and sends "Battery critical – 4%"
  / "Plug in now" (app Battery, icon battery-caution). Plugging in
  closes it.
- Disk almost full: `df` a minute after the island starts, then every
  10 minutes, each device once (the btrfs subvolumes share one), at its
  shortest mount point. A filesystem with under 5 GB and under 10% free
  sends "Disk almost full" / "2.1 GB left on /" (app Disk, icon
  drive-harddisk), once: it warns again only after the space has come
  back to 6 GB or 12% free, which also closes it. Both limits, so the
  1 GB /boot only warns near its end and a big disk not at 10%.
No pill flash for the disk: it is a notification only.

Testing: `test-notices.sh notifications` sends both from made-up
readings and takes them back after 6 seconds;
`island-notices battery critical` (closed by `battery charging`) and
`island-notices disk / 2.1` (closed by `disk / 50`) by hand. No disk is
filled and nothing is unplugged.

## Network and Bluetooth notices

`Controls.notice(icon, before, name, after)`, shown like the battery
notice: the icon at 16px, 8px before the bold 13px line (before + name
+ after), for 3 seconds, the newest flash winning, not while a panel is
open or mid-drag, dropped by a press. Quiet for the first 2 seconds.
- "Connected – <network>" when a Wi-Fi network comes up (from
  `Controls.ssid`), "Connected – Ethernet" when a cable does.
- "Wi-Fi lost" when the network goes and, 3 seconds later, Wi-Fi is
  still on with no network and no cable: switching networks passes
  through none, and switching Wi-Fi off isn't a loss.
- "Couldn't connect – <network>" when a network reports
  `connectionFailed`, whoever started it, except for a missing password
  (the island's Wi-Fi page asks for it).
- "<device> connected – 80%" (the battery when the device reports one)
  and "<device> disconnected" for Bluetooth devices, with the device's
  glyph; not while the adapter is off.
No USB drives (the user: unnecessary).

Testing: `test-notices.sh` (see Testing the notices); don't disconnect
anything.

## Long names

Every notice is a `NoticeFace.qml`: the icon, then a line made of
`before`, `name` and `after`. The pill stays at most 400px wide
(`pill.noticeMaxWidth`, 400 less the padding); a line that would pass
that has only its name cut with "…", the network, device or screen, so
"Couldn't connect –" and "connected – 80%" always show:
"Couldn't connect – Telia-3D6C57-5GHz-Gu…", "Sony WH-1000XM5
Wireles… connected – 80%", "Display connected – Dell UltraSharp U27…".
The battery notice has no name and is never cut.

## Layout notice

Switching the keyboard layout (Alt+Shift, or any other way) shows the
keyboard icon at 16px, 8px before "Layout – English (US)" in
bold 13px, for 1.5 seconds like the workspace name, since the user did
it. Like the other flashes it obeys "the newest flash wins", isn't shown
while a panel is open or mid-drag, and pressing the pill drops it.

`Controls.layoutNotice(name)` drives it, from Hyprland's `activelayout`
event ("keyboard,layout"). Every keyboard device keeps its own layout,
so each is tracked on its own (`keyboardLayouts`, first read from
`hyprctl devices -j`): only a change from that same keyboard's last
layout flashes, and a keyboard's first report doesn't. Virtual keyboards
(`hl-virtual-keyboard…`: wtype, when voxtype types) are ignored. Two
earlier versions flashed falsely: one compared every event against the
last name seen (a volume key reports `thinkpad-extra-buttons`, still
Swedish), the next read the "main" keyboard, which is only the one used
last, so voxtype's virtual keyboard became it while typing. Quiet for
the first 2 seconds.

Testing: `test-notices.sh` (see Testing the notices); don't switch the
real layout.

## Dictation

While voxtype records (SUPER+V, `voxtype record toggle`) and until it
has typed the text, the pill shows the dictation face
(`DictationFace.qml`), main's dictation pill (`osd/VoxtypeOsd.qml`)
brought over in black and white, since nothing showed a recording once
main stopped starting at login. It isn't a flash: it stays for as long
as dictation lasts, over every view and flash. A flash that comes
meanwhile waits behind it, and shows afterwards if its time hasn't run
out.

144 × 32 throughout, so the pill never changes width: at the left end
a 24px round cancel button (white at 12%, 20% hovered, a cross;
`voxtype record cancel` drops the recording), at the right end a solid
white stop button with a black square (`voxtype record toggle`, the same
as SUPER+V, types what was heard; it shrinks to 90% while pressed),
each 4px from the pill's rounded end (`pill.shownPadX`), and between
them 16 bars, 2px wide in 4px cells, 2–16px tall, following the default
microphone's level (heavier in the middle, measured from the room's
noise floor as main did). Transcribing: the buttons fade (120ms) and the
bars dim to 60% and become a wave travelling left to right, at most 8px.
Main's red stop button is white here (Look: white on black).

The face's buttons are the only thing on it to click: a press elsewhere
on it neither drags nor opens the player. A right or middle click still
opens the settings panel or the power menu over it, and closing them
brings it back. The island doesn't take keyboard focus for it, so
clicking stop leaves the text going to the window that had it. Hidden
with SUPER+ALT+SPACE, the island shows nothing, dictation or not.

`Dictation.qml` (a singleton) follows `voxtype status --follow` (idle,
recording, transcribing, stopped; one process, outliving the daemon;
not retried when voxtype isn't installed) and works out the bar heights
once for every screen, sampling the microphone only while recording.

Testing: `test-notices.sh pill` ends with it, or
`qs -c dynamic-island ipc call island-notices dictation recording`
(`transcribing`, and `""` to go back to voxtype's own state). It shows
the face without recording anything; the bars follow the real
microphone. Never click its buttons, or press SUPER+V, to check it:
they drive the real voxtype.

## Caps Lock notice

Toggling Caps Lock shows the Caps Lock arrow (U+F0632) at 16px, 8px
before "Caps Lock – on" or "Caps Lock – off" in bold 13px, for 1.5
seconds: the layout notice's face and rules (`Island.flashShort`, which
both use; the newest flash wins, not while a panel is open or
mid-drag, a press drops it).

Hyprland has no Caps Lock event. Two `non_consuming` press binds
(`hypr/modules/binds/media.lua`), `Caps_Lock` and `CAPS + Caps_Lock`,
press the global shortcut `quickshell:island-capslock` without taking
the key from XKB: Caps Lock being on counts as the CAPS modifier held,
so a bind without it never fired while turning it off, nor a release
bind while turning it on (the first version, which never flashed). 150ms
later, once XKB has toggled, the island reads `capsLock` from `hyprctl
devices -j`, on if any keyboard has it on ("main" is only the keyboard
used last, often the volume keys' `thinkpad-extra-buttons`), and
flashes only when it differs from the last reading (`Controls.capsLock`,
first read at start, quiet for the first 2 seconds). So with Caps Lock set to switch layouts
(Settings › Input) it stays off and nothing flashes but the layout.

Testing: `test-notices.sh pill`, or
`qs -c dynamic-island ipc call island-notices caps true|false`. The
real path:
`hyprctl dispatch 'hl.dsp.global("quickshell:island-capslock")'` reads
the state and, unchanged, shows nothing. wtype can't test it: its keys
don't trigger Hyprland's binds.

## Privacy indicators

Brought over from `../island` (2026-10-13, the user's request, after
trying that island): who is using the microphone, the camera or the
screen, in `Privacy.qml`.

- **Dots:** one per device in use, microphone (orange `#ff9f0a`),
  camera (green `#30d158`), screen (red `#ff453a`), in that order,
  never merged: 8px, 8px apart (16px hit areas), just right of the
  pill, centred on its collapsed line, so they ride along as it grows
  and shrinks. They pop in (160ms, OutBack) and go at once. Nothing
  hides them: a panel, a flash, or hiding the island (SUPER+ALT+SPACE),
  when the window stays up for them alone, reserving nothing, the dots
  at the pill's centre. These colours override `STYLE.md` and Look's
  white on black: the brief that brought them fixes them.
- **Notices:** a device starting to be used is announced as a notice
  (see Network and Bluetooth notices): the device's glyph and
  "Firefox is using the microphone", "OBS is sharing the screen",
  "Something is recording the screen" (a screencopy recorder, which
  names no app), or "Microphone – Firefox, Discord" for several; the
  apps are the cut-with-"…" name. Several devices at once take turns,
  3 s each. A device off for less than 2 s isn't announced again. Like
  every notice, not shown while a panel is open or mid-drag; the dots
  are. Not while dictating, for the microphone: the dictation face
  already shows it listening; the dot does.
- **A click on a dot** names the apps on that device, as a notice.
- **Detection:** active PipeWire links from a capture device to an
  app's stream (an `Audio/Source…` is the microphone; a `Video/Source`
  with a `device.api` a camera, without one a screencast), and
  Hyprland's `screencast` event for recorders that skip PipeWire,
  trusted after 1.5 s so a screenshot doesn't light it. Quickshell's
  own level meters (the dictation waveform, the settings window's input
  level) and `stream.monitor` streams don't count.
- Not covered: apps opening `/dev/video0` directly, not through
  PipeWire; over fullscreen windows the island (Top layer) and its dots
  are under the window.

Testing: `qs -c dynamic-island ipc call privacy add|drop <kind> <app>`
(made-up users), `clear`, `list <kind>` (a dot's click), `users`; and
`../island/fake-capture.sh mic|camera|screen [app]` for real PipeWire
streams from fake devices. Never test with `pw-record --target`: when
the target is missing it records from the real microphone.

## Testing the notices

`./test-notices.sh [pill|notifications]` (both when no part is named)
shows everything that can pop up, one after another, and prints which
one is up. `pill` flashes every notice the pill has: the battery,
display, layout, Caps Lock, network and Bluetooth notices (one per device glyph),
then a few with long names, then the dictation face. `notifications` sends the regular ones
through dunst the way their senders do (see Notifications): three app
messages with `notify-send`, rack's "Dotfiles synced" and "Update
failed" with `relay notif send`, the Print keys' line on the newest
screenshot (nothing captured or copied), and the critical battery and
disk ones; the critical ones never time out, so the script closes them
by id after 6 seconds, and on exit.

The pill part goes through the `island-notices` IPC target in
`Controls.qml`, which emits the same signals the system events do
(`batteryNotice`, `Displays.connected`, `layoutNotice`, `notice`), so
nothing on the system changes. The target stays, unlike the temporary
handlers used elsewhere, so the script keeps working. One notice by hand:
`qs -c dynamic-island ipc call island-notices notice <glyph> "<before>" "<name>" "<after>"`
(empty strings for the parts not used).
The battery notices show the real charge. Close any panel first; the
island skips notices while one is open.

## Today view

The Swedish date and the battery: `tors 8 okt – [battery] 46%`
(`ddd d MMM` in sv_SE, short weekday, with the month's abbreviation dot
removed). The battery is `Controls.batteryIcon` (the main bar's ladder, a
bolt while charging) at 16px, via rich text so it holds its own next to
the 13px bold text, with one space after it, and the rounded percentage;
it is left out on a machine with no battery.

## Media player

A left click on the pill opens it, player or not. 16px padding;
album art (96px, 12px corners) on the left; beside it the title (bold),
the artist (white at 60%), a 4px progress bar, elapsed and total time, and
previous / play-pause / next. A click on the player outside its buttons,
or anywhere outside the island, closes it. With no player it stays open
and shows the empty state: a dim music note in the art square, "Nothing
playing" over "No media player open", an empty bar at 0:00 / 0:00, and
the controls at 30% and inert. A cover that fails to load shows the same
note.
Closing returns to whichever view (song, time or today) it was opened from.

Opening: the compact text fades out, the box grows to 360 × 128, then the
player fades in. Closing is the exact reverse: the player text fades out
first, the time fades in at the middle of the still-large box, then the
box shrinks back to the pill.

## Settings panel

A right click on the pill opens it; it opens and closes with the same
sequence as the media player. 16px padding; the buttons (below) first,
then two 32px slider rows, 8px apart:
speaker icon, slider, volume %; sun icon, slider, brightness %. The
speaker icon shows off / low / medium / high and mutes on click. Sliders
are a 4px white-on-20%-white track with a 12px white knob. Volume is the
default PipeWire sink, capped at 100%. Brightness is the first
/sys/class/backlight device, read every 0.5s and set with brightnessctl,
never below 1%.

At the top, above the sliders (12px gap), the fused pill, 40px tall and
the panel's full inner width.

The fused pill (`TileGroup.qml`) is the main bar's volume/network/battery
island brought to the island: one fully round pill, white at 12%, split
into four equal segments with no dividers, in the order network,
Bluetooth, volume, battery. A hovered segment lifts to about 20%; an
active one is solid white with a black icon. The end segments' fills
follow the pill's rounding, the inner sides are square.
- Network (network icon): a click turns the panel into the Wi-Fi page.
- Bluetooth: the main bar's glyphs (off / on / connected), active
  while the adapter is on. A click turns the panel into the Bluetooth
  page, where the adapter's switch now is.
- Battery (battery icon): a click turns the panel into the battery
  page.
- Volume: the speaker icon (`Controls.volumeIcon`, the same as the
  slider's). A click mutes and unmutes in place.

A left or right click on the panel outside a control, or
any click outside the island, closes it.

**Quick settings.** In the panel's 16px bottom padding, centred, is the
notch: a 32 × 4 bar, white at 30% (60% while hovered or held), with a
96 × 16 hit area. Dragging it down reveals a second fused pill, the
same `TileGroup`, 12px under the sliders; the panel grows by 52px to
360 × 208, following the finger (`Island.quickReveal`, 0–1, drives the
height and the row's opacity) and the notch rides down with the
panel's bottom. Released past halfway it finishes the way it was going,
short of that it eases back (160ms, OutCubic); a click opens or closes
it. Dragging up hides it. It stays as it was left, also across
openings, until the next drag. The row (`QuickSettings.qml`, none of it
needs main):
- Stay awake (a coffee cup), solid white while on: a
  `systemd-inhibit --what=idle` lock held by a process, which hypridle
  honours, so it works with the island hidden. Not saved: a forgotten
  one would keep the laptop up on battery after a restart. The Power
  page's "Stay awake is on" row counts it, and its Turn off ends it.
- Do not disturb (bell, a struck-through bell while on), solid white
  while on: dunst paused (`dunstctl set-paused`), which holds
  notifications and shows them once it is unpaused. Read back from dunst
  on start, after a toggle and each time the panel opens. The pill's
  own notices aren't notifications, so they still show.
- Night light (a moon), solid white while on: hyprsunset at 4500 K
  (`hyprctl hyprsunset temperature 4500`, `identity` off), main's
  warmth. Saved in settings.json (`quick.nightLight`) and put back when
  the island starts.
- Microphone: the default source muted or not, the glyph showing which,
  never solid, like the speaker segment above.

Testing the row: open the panel and look; never click a segment.
Night light changes the screen.

Testing: never change the brightness (or run any screen command) to check
this panel, and don't toggle Bluetooth or mute; open it and look.

## Settings pages

The settings panel's network, Bluetooth and battery segments turn the
panel into a page: for connecting to a network or a device, or picking
the power profile, and nothing more (`WifiPage.qml`,
`BluetoothPage.qml`, `BatteryPage.qml`). Switching: the panel fades out
(120ms), the box eases to the page's size (220ms, OutCubic), the page fades in
(160ms); back is the same in reverse to the settings panel. A click
outside the island closes it from a page as from the panel.

Each page, 16px padding: a 32px header (`PageHeader.qml`), then 8px on,
a list five rows tall that scrolls past that. The header has a round
32px back button (a chevron, white at 12% while hovered), the bold
title, on the right the radio's switch (`Toggle.qml`: a 36 × 20
pill, white at 20% with a white knob off, solid white with a black knob
on), and left of the switch (or of the battery page's charge) a round
32px gear like the back button: it closes the island and opens the
settings window on Network, Bluetooth or Power (`Island.openSettings`,
from each page's `openSettings` signal, `PageHeader.hasSettings`). A row (`ListRow.qml`) is a 40px fully round pill, 4px from the
next: an icon at 18px, the bold 13px name, and on the right a short
detail in bold 11px at 60%. No fill at rest, white at 12% while hovered,
solid white with black text while connected, the same way a fused-pill
segment is active. Empty: "Wi-Fi is off" / "Bluetooth is off",
"Searching…", or "No … adapter", at 60%, in the middle of the list.

Wi-Fi: Quickshell.Networking, scanning only while the page is open.
Rows: the connected network, then saved ones, then by signal (in four
steps, so the rows don't reshuffle every scan); hidden SSIDs are left
out. Icon: signal strength 1–4, with a lock when secured. Detail:
"Connected", "Connecting…", "Failed", "Saved", or nothing. A click on
a network connects to it; a click on the connected one does nothing. A
secured network never joined first asks for its password: the list
gives way to a password field (a 40px pill, white at 12%, with a round
white arrow button at its end), the header shows the network's name,
Enter or the arrow connects, Escape or back returns to the list. A saved
network whose password NetworkManager no longer has (NoSecrets) asks
the same way.

Bluetooth: Quickshell.Bluetooth, discovering only while the page is open
and for at most 30 seconds (A2DP stutters under a scan). Rows: paired
devices (the connected ones first), then the named devices in range.
Icon: by BlueZ's device icon (headphones, keyboard, mouse, phone, …).
Detail: "Connected" (with " – 80%" when the device reports a battery),
"Connecting…", "Pairing…", "Failed", "Pair" for a new device, or
nothing. A click on a paired device connects or disconnects it; on a
new one it pairs, as the main bar does (trusted, then connected once
bonded). The island runs no pairing agent, so only devices that need no
code pair from here; the settings window's Bluetooth section pairs the
rest.

Battery: 360 × 200. The header has no switch; in its place the charge,
`46%`, or `46% – Charging`, bold 13px at 60%. Then one row per power
profile (power-profiles-daemon through UPower's PowerProfiles): Power
saver (leaf), Balanced (scales), Performance (speedometer, only where
the hardware has it), the main bar's labels and icons. The current one
is solid white; a click switches to that profile. Without the daemon
(`powerprofilesctl get` fails at startup), "Power profiles unavailable".

Keyboard: the island takes keyboard focus (OnDemand) while the settings
panel or a page is open, for the password field. It is set as the panel
opens, never while it is open: changing it during the focus grab clears
the grab and closes the island.

Testing: open the pages with a temporary IpcHandler (`root.open`, then
`root.switchTo`) and look. Don't click a row, the switches or the arrow,
and never submit a password, to check them. A new page file isn't
picked up by the reload; restart the island.

## Power menu

A middle click on the pill opens it, with the same open/close sequence as
the player. 16px padding; four 56px round icon-only orbs, 16px apart:
Lock, Reboot, Log out, Power off. An
orb is white at 12% with a white icon, and solid white with a black icon
while hovered. The commands and icons are the main bar's power menu's
(`powermenu/PowerMenuPopout.qml`, logout from `Theme.logoutCmd`), and like
it there is no confirmation: a click closes the island and runs the
action, through `Quickshell.execDetached` so a running hyprlock outlives
an island reload.

Testing: never click an orb, or run any of these commands, to check it.

## Wallpaper gallery

SUPER+ALT+W (the global shortcut `quickshell:island-wallpapers`, bound in
`~/.dotfiles/hypr/modules/binds/apps.lua`) opens it on the focused
screen's island, or closes it there. The island grows to exactly three
whole images wide (the middle one and one to each side) and only as tall
as its row: the images (12% of the screen's height), the middle one's
lift and 16px padding (757 × 178 on the laptop), with the shared
open/close sequence.

Inside (`WallpaperGallery.qml`): the images in `~/Pictures/Wallpapers`
(png, jpg, jpeg, webp, by name) in one row, all the same size (16:9,
16px apart), along the bottom of the padding; the ones further out are
outside the island and slide in as you move. At the first or last image
one side is empty. The chosen one is in the middle and raised 16px to the top;
nothing else sets it apart. 12px corners, decoded at 480px wide. It opens on the wallpaper
showing now (`awww query`). ← and → move (160ms, OutCubic), Enter sets
the middle one and closes, Escape closes, and so does a click outside.
"No images in ~/Pictures/Wallpapers" when the folder is empty.

Setting it (`Wallpapers.apply`): `awww img <path> --transition-type
wipe`, with no `-o`, so every connected screen gets it. Wallpaper only:
no colours follow it.

Keyboard: the gallery takes the keyboard outright (Exclusive), so the
arrows work without a click. Its focus grab starts 150ms after it opens:
the keyboard change reaches Hyprland just after `open()`, and a grab
already on by then was cleared by it, closing the gallery as it opened.

Testing: `hyprctl dispatch 'hl.dsp.global("quickshell:island-wallpapers")'`
opens and closes it like the key; step it with a temporary IpcHandler
calling `gallery.step()`. Never press Enter or call `apply()` to check.

## Hiding with the main bar

SUPER+ALT+SPACE hides and shows the island (`Controls.barVisible`). The
bind presses two global shortcuts: main's `quickshell:bar-toggle` and
the island's own `quickshell:island-toggle`, so the key works with main
never started. When main runs, the island also follows the bar
(`qs -c main ipc call bar toggle`, or any other way the bar is
toggled): main's `services/Panels.qml` calls `qs -c dynamic-island ipc
call island setBarVisible <bool>` on every barVisible change, which has
the last word over the island's own flip; at startup the island asks
`bar state` once.

Hiding (220ms, InCubic, so it speeds up and doesn't linger as a dot):
the text fades (80ms) as the pill's sides close in; once the width is
less than the height the height follows, so the pill becomes a circle
that keeps shrinking to a point, centred where the pill was, and the
window unmaps. No fade. Showing is the reverse (260ms, OutCubic): it
grows from a point to a circle and opens out to the pill, the text
fading back in from 140ms. Hyprland's own layer fade-in softens the
first frames of showing. An open panel closes first, then the island
hides. `orbing` keeps the width Behavior off for the whole hide/show.

Testing: `hyprctl dispatch 'hl.dsp.global("quickshell:island-toggle")'`
toggles it like the key, without main.
`qs -c dynamic-island ipc call island setBarVisible false|true`
moves only the island. Check `qs -c main ipc call bar state` first and
leave the island matching it afterwards; a test that ends on `true` while
the bar is hidden leaves the island showing on its own.

## Motion

On a workspace switch, the time slides out and "Workspace N" slides in,
in the direction of the switch (see States); afterwards the time fades
back. The pill's width eases to fit the new text at the same time.

The pill itself never moves. Dragging moves only the text, which follows
the cursor and is cut off 8px inside the pill's ends. The other view's
text rides along beside it, 16px away, so both show mid-drag: dragging
the time right brings the song in from the left, artist end first.
Released past 48px towards the other view, both keep sliding until the
new text is centred (160ms, OutCubic). Released short of that, the text
slides back to the middle and the other view fades out.
While dragging, the pill's width moves from the dragged text's width
towards the incoming text's, in step with the drag; on release it eases
the rest of the way (or back).

## Settings window

The deeper settings, which don't fit the pill: a normal Hyprland window
(`SettingsWindow.qml`, a Quickshell `FloatingWindow` titled "Settings"),
not a panel. It opens floating and centred at 880 × 600 (window rule in
`~/.dotfiles/hypr/modules/windowrules.lua`); the usual float toggle tiles
it, so it can sit at the side of the screen.

Opening: SUPER+COMMA (the global shortcut `quickshell:island-settings`,
bound in `~/.dotfiles/hypr/modules/binds/apps.lua`) opens it if it is
closed, focuses it if it is open but not focused, and closes it if it is
focused. `settings.desktop` (in this folder, linked into
`~/.local/share/applications/island-settings.desktop` by stow
(`stow quickshell`)) puts "Settings" in the launcher. IPC:
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
   udev rule (`udev/`, see the README) so no password is asked. The lid action
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
  "Install patch" runs the rule's install in a ghostty window (sudo:
  `install` into `/etc/udev/rules.d`, `udevadm control --reload`,
  `udevadm trigger --action=add --subsystem-match=power_supply`, what
  `rack patches install` did before rack left the dotfiles on
  2026-10-13), then reads the files again. The limit is saved too, and written back at startup if a
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

## Decisions

Dated record of what the user chose or rejected, and why.

- 2026-10-08: resting state is the day and time only. A workspace switch
  shows the workspace name briefly, then the island goes back to the day
  and time.
- 2026-10-08: fade transition, name shown for 1.5 seconds, `Thu 18:32`
  format, a pill at the top centre.
- 2026-10-08: width fits the content; white text on black; the label is
  always "Workspace N" (workspaces are 1–9), even for a named workspace.
- 2026-10-08: fully rounded corners, an exception to `STYLE.md` §5.
- 2026-10-08: the day is the full weekday name in Swedish
  (`torsdag 18:32`), replacing `Thu 18:32`.
- 2026-10-08: side padding raised from 16px to 24px for more room
  around the text.
- 2026-10-08: the weekday was dropped; the island shows only the time
  (`18:32`).
- 2026-10-08: dragging the pill right shows the current song as
  "Title · Artist" (no controls); dragging left goes back to the time.
- 2026-10-08: the pill no longer moves when dragged; only the text
  slides, and the next view's text slides in behind it.
- 2026-10-08: mid-drag, the next view's text shows beside the dragged
  text instead of appearing only on release.
- 2026-10-08: the pill grows (or shrinks) with the drag towards the
  incoming text's width.
- 2026-10-08: left click expands the pill into a media player (art,
  title, artist, progress, controls); a click on it or outside closes it.
  Close order: player fades, time appears in the large box, box shrinks.
- 2026-10-08: dragging left from the time shows system stats (CPU, RAM,
  battery, CPU temperature); the views are now song | time | system.
- 2026-10-08: icons. The system view swaps its CPU/RAM/BAT labels for
  icons and adds a thermometer; the song view gets a music note.
- 2026-10-08: side padding raised from 24px to 32px, the same for every
  compact view (measured: 33–34px of black each side in all three).
- 2026-10-08: right click opens a settings panel with volume and
  brightness sliders, using the player's open/close sequence.
- 2026-10-08: settings panel gets a network button (opens the main bar's
  network panel) and a battery button (cycles the power profile); the
  panel is now 360 wide like the player.
- 2026-10-08: the network and battery buttons are icon-only, and each
  opens the main bar's panel (battery no longer cycles the power profile).
- 2026-10-08: a Do Not Disturb button joins network and battery; it
  toggles the main bar's DND in place.
- 2026-10-08: a Bluetooth button (second of four) toggles the adapter in
  place, white while on.
- 2026-10-08: no player no longer blocks anything: the song view and the
  player show a "Nothing playing" state instead.
- 2026-10-08: the system view (CPU, RAM, battery, temperature) is gone. It
  read like a spreadsheet, made the pill twitch as numbers changed width, and
  repeated the settings panel's battery. The left view is now "today": the
  Swedish date and the current weather.
- 2026-10-08: the today view's weekday is shortened (`tors`, not `torsdag`).
- 2026-10-08: the divider in the song and today views is a bullet (•),
  bigger than the middle dot (·); a filled circle (●) was too heavy.
- 2026-10-08: the settings panel's buttons moved above the sliders.
- 2026-10-08: text weight raised from Regular to SemiBold for a meatier
  look (Medium was too close to Regular to notice).
- 2026-10-08: text weight raised again, from SemiBold to Bold, after a
  side-by-side comparison. The player's title no longer stands out by
  weight.
- 2026-10-08: the today view's weather icon is 16px instead of 13px, to
  match the bold text.
- 2026-10-08: the player's album art corners went from 16px to 12px.
- 2026-10-08: middle click opens a power menu: four round orbs (lock,
  reboot, log out, power off), no confirmation, like the main power menu.
- 2026-10-08: the power orbs lost their text labels; icons only.
- 2026-10-08: the battery joins the today view, after the weather; the
  time view stays just the time.
- 2026-10-08: the dot after the short month is removed (`okt`, not `okt.`).
- 2026-10-08: an OSD face for volume and brightness changes: the
  percentage on the left, a circle filling like a pie on the right.
- 2026-10-08: the OSD face gets a speaker/sun icon on the left, then the
  percentage; the circle moves further right.
- 2026-10-08: the volume and brightness keys show the OSD face on every
  press, even at 100% or 0% where nothing changes.
- 2026-10-08: the song view's divider is an en dash (`Title – Artist`);
  the today view keeps the bullet.
- 2026-10-08: the today view's dividers are en dashes too; no bullets left.
- 2026-10-08: switching workspaces while a name is showing slides the old
  name out and the new one in (by direction of the number), instead of a
  swap.
- 2026-10-09: the island hides and shows with the main bar: the sides
  close in to an orb that fades out, and the reverse.
- 2026-10-09: the orb's fade-out is faster, 80ms instead of 160ms; the
  fade-in on appearing stays 160ms.
- 2026-10-09: the whole hide is faster, about 200ms (text 80ms, shrink
  140ms, fade 60ms); appearing is unchanged.
- 2026-10-09: no orb stop: hiding shrinks the pill continuously to a
  circle and on to nothing, no fade; showing grows it back from a point.
- 2026-10-09: the app launcher is its own config (`qs -c launcher`), so it
  works without the main bar. The island gets no gesture for it (every
  click and the drag are taken); SUPER+P opens it.
- 2026-10-09: the settings panel's network, Bluetooth and battery buttons,
  plus a new volume (mute) button, are fused into one icon-only pill, like
  the main bar's volume/network/battery island. DND stays its own round
  button beside it. Chosen over a pill with values under each icon, and
  over fusing DND in too.
- 2026-10-09: scope set (see Scope). The island is a demo of a possible
  alternative to the main bar, not a replacement, and must work without
  main running. It shows what is happening now and doesn't manage the
  system.
- 2026-10-09: the weather is gone from the today view (it needed main's
  `.env` for its location); the view is the date and battery. The Do Not
  Disturb button is gone too (it only worked through main), so the
  fused pill takes the panel's full width.
- 2026-10-09: battery notices: "Charging" when the charger goes in, "Low
  battery" below 20% and 10%, so the battery is noticed without main.
- 2026-10-09: notifications, and what the network and battery segments
  do without main, are left undecided.
- 2026-10-09: the workspace slide applies from the time (and the song
  and today views) too, not only between two names, so the island looks
  like it moves to the new workspace instead of the name fading in.
- 2026-10-09: the island reserves space at the top, so windows no longer
  slide under it; not while main's bar is up. First 40px with its margin,
  then 32px because that was too much room. The top margin went from 8px
  to 7px so the gaps above and below the pill are equal (measured).
- 2026-10-09: the OSD face's circle is a ring (2px, empty middle) with
  an arc filling clockwise, instead of a pie.
- 2026-10-09: the OSD face is tighter: 8px between the percentage and
  the ring (was 16px), and 24px from the ends (was 32px).
- 2026-10-09: the OSD ring is 3px thick (was 2px).
- 2026-10-10: the island can connect to Wi-Fi and Bluetooth, and only
  that: the settings panel's network and Bluetooth segments open a page
  each (a list, and a password field for new secured networks). A
  scope change, made by the user. Network no longer opens main's panel,
  and Bluetooth no longer toggles in place; its switch is on its page.
- 2026-10-10: the battery segment opens a battery page for changing the
  power mode (power saver, balanced, performance), instead of main's
  battery panel. Nothing in the island needs main any more.
- 2026-10-10: scope change, made by the user: the island is now a real
  alternative to main, not a demo. Deeper settings (monitors and the
  like) didn't fit the pill, so it gets a settings window, in this
  config rather than its own. Chosen in a grilling session; the user took
  my recommendation on most points:
  - a normal Hyprland window, floating by default and tileable (the user:
    "so it can be floating, but … have it on the side"), opened with
    SUPER+COMMA, a `.desktop` entry and IPC; no island gesture;
  - sections Displays, Sound, Network, Bluetooth, Power, Input (the
    island's own preferences were left out); a sidebar layout; the
    island's black-and-white look;
  - changes saved per machine (`hypr/local.lua`, ignored by git), not in
    the shared dotfiles; applied at once, except Displays (Apply and a
    15-second keep-or-revert);
  - displays remembered per monitor, plus "laptop screen off while an
    external is connected", and a "Display connected" flash;
  - the island's Wi-Fi, Bluetooth and battery pages stay, each with a
    settings button to the matching section (the user leaned to this
    over leaving them unconnected);
  - Conf is to be split out of main into its own config later, not
    folded into the window; picking main or the island at login is left
    for later.
- 2026-10-10: Input: repeat delay and repeat rate get a reset-to-default
  button; a thin divider between the settings window's sidebar and page.
  Both at the user's request.
- 2026-10-10: a "Keyboard layout – <name>" flash on the island when the
  layout switches; the settings window's divider runs the full height,
  with more room (32px) before the page. The user's requests. The repeat
  sliders' reset no longer flickers through the old value.
- 2026-10-10: the layout flash is shortened to "Layout – <name>",
  keeping the keyboard icon.
- 2026-10-10: fixes from the user's Power test: the Power page warns
  when main's Stay awake pauses the idle timers (with Turn off); the
  patch install ran a bare `rack`; the layout flash only follows the main
  keyboard (it fired when voxtype typed, or on a volume key).
- 2026-10-10: the Network section's saved-networks list is gone, with
  its details (autoconnect, IP, custom DNS, Forget): the user had no use
  for it.
- 2026-10-10: the island's Wi-Fi, Bluetooth and battery pages get a gear
  in their header that opens the settings window on the matching
  section. The settings window plan is complete.
- 2026-10-10: the island moved into `~/.dotfiles/quickshell/dynamic-island`
  (rack links it and its .desktop entry) and into autostart, beside main.
  The user's request.
- 2026-10-10: login starts the island instead of main (autostart). Main
  can still be started by hand; while it runs, the island follows it as
  before. The user's choice, after the island had run beside main.
- 2026-10-10: the media keys are Hyprland's (playerctl), not any
  shell's: the user wants the island to lean on no single part, and
  doesn't want relay in the way either.
- 2026-10-10: Print and SHIFT+Print are Hyprland's own (grim, slurp,
  wl-copy, and Hyprland's notification), not main's. Conf is not to be
  brought over: the user wants this minimal. Notifications are left
  undecided for now.
- 2026-10-10: no colour themes in the island: main's theme feature is
  dropped for it ("I don't think we need it"). Still open from the list
  of what went with main: workspaces, the wallpaper, night light and
  Stay awake, the tray.
- 2026-10-10: no workspace overview ("drop the workspaces"). A wallpaper
  gallery instead: SUPER+ALT+W, the island grows to about a third of the
  screen wide and a quarter high, images from ~/Pictures/Wallpapers in a
  row with the middle one raised, ← → and Enter, set with awww on every
  screen. The user's design; opening, size and moving to be refined later.
- 2026-10-10: the gallery's images are all one size in one row; the
  middle one is only raised, not bigger or brighter (the user's
  correction). The layout flash tracks each keyboard on its own and
  ignores virtual ones; it still fired while voxtype typed.
- 2026-10-10: the gallery is only as tall as its row (no empty space
  above and below the images), at the user's request.
- 2026-10-10: the gallery is exactly three whole images wide, so none is
  cut off at the sides. The user: "then I think it's perfect".
- 2026-10-10: notifications. They are their own thing, not the island's:
  dunst is unmasked and answers them under any shell, default look until
  the end (design comes last). The island shows the system ones itself:
  network connected, couldn't connect and Wi-Fi lost; Bluetooth devices
  connecting and disconnecting; the battery notices as they were. No USB
  drives. App notifications: the user doesn't mind. The user's own tools
  (rack, relay): undecided.
- 2026-10-11: the settings window works with the arrow keys, at the
  user's request (the island's settings panel was offered too and left
  out). Arrows move, Enter acts: ↑ ↓ through the sidebar and the page's
  controls, → or Enter into a section, ← or Escape back. Focus shows as
  the hover fill (white at 80% on a solid white control), only after a
  key press, never as a ring. See Settings window › Keyboard.
- 2026-10-11: the keys reworked at the user's request: no highlight in
  the sidebar, ↑ ↓ move the white row itself and switch the section at
  once; → goes into the page to change settings there, ← comes back.
  Sliders and Segmented rows are grabbed with Enter first, so ← always
  means back (the user's pick over ← → changing them directly). → back
  into a page returns to the control left.
- 2026-10-11: the keys' focus was too hard to see (it looked like
  hover: 12–20%, 80% on solid white). Now 32% white, 60% on a solid
  white control, a text field lit the same, and a grabbed slider's
  circle at 60%; at the user's request ("easier to see what options you
  are on").
- 2026-10-11: a focused switch's pill was cut off at the page's right
  edge (the Flickable's clip); the Flickables now reach 8px further right
  than their content. The user's report.
- 2026-10-11: whole rows light up for the keys, as the power mode rows
  did, which the user liked: setting rows, volume rows, app rows and
  layout rows, the control's own fill off inside them (buttons and
  grabbed controls excepted). Setting rows' names and controls moved in
  (16px, 8px) to sit inside the pill.
- 2026-10-11: the Wi-Fi and Bluetooth switches left their headings for
  rows of their own, "Use Wi-Fi" and "Use Bluetooth" (like "Use this
  display"), so they light up whole for the keys too. The user's request.
- 2026-10-11: `test-notices.sh` and a lasting `island-notices` IPC
  target, at the user's request, to see every notice in turn (see
  Testing the notices).
- 2026-10-11: long names in the notices are cut with "…", only the name,
  so the pill stays within 400px and the words around it show (see Long
  names). The user's request, after the test showed long SSIDs, device
  and screen names stretching the pill.
- 2026-10-11: `test-notices.sh` shows the regular notifications too
  (`notifications`), at the user's request; `pill` or `notifications`
  runs one part.
- 2026-10-11: what is a regular notification (see Notifications): the
  pill for system state it watches, dunst for apps' and tools' messages,
  nothing in both places; rack and relay send results and failures,
  never progress (the open question settled); urgency low / normal /
  critical at 3 s / 5 s / until dismissed. The Print keys' confirmation
  moved from Hyprland's own notification to a regular one with the
  capture as its thumbnail. My proposal, which the user accepted.
- 2026-10-12: SUPER+ALT+SPACE hides and shows the island on its own,
  like the main bar, now that login starts only the island. The key
  presses both main's bar-toggle and the island's island-toggle; main,
  when it runs, still decides. The user's request.
- 2026-10-13: the dictation face: while voxtype records or transcribes,
  the pill shows a cancel button, a live waveform and a stop button,
  main's dictation pill in the island's black and white. Main was the
  only thing showing a recording, so SUPER+V recorded unseen after login
  moved to the island. Picked by the user from a list of what the
  island lacks.
- 2026-10-13: quick settings under a notch at the bottom of the settings
  panel: dragging it down reveals a second fused pill with Stay awake,
  Do not disturb, Night light and the microphone, for the toggles that
  don't fit the top. The user's request, a scope change: Do not disturb
  comes back (dunst's pause now, not main's), and the frozen panel gets
  the row. The user named Stay awake and Do not disturb; Night light and
  the microphone are my picks for "those kind of quick settings".
- 2026-10-13: the critical battery and disk-full warnings are built
  (see System alerts), as the Notifications rule laid them out: dunst,
  critical, until dismissed, taken back once the problem is gone.
  Battery critical below 5%, also flashed in the pill; disk almost full
  under 5 GB and 10% free, checked every 10 minutes. The user's request;
  the thresholds are mine.
- 2026-10-13: a Caps Lock notice, "Caps Lock – on/off" for 1.5 seconds
  like the layout's, from a non-consuming Caps_Lock bind. The user's
  request, from the list of what the island lacks.
- 2026-10-13: the Caps Lock notice never showed (the user's report): the
  release bind without modifiers didn't match with Caps Lock on. Now a
  press bind with and one without CAPS, read 150ms later from any
  keyboard. Confirmed by the user.
- 2026-10-13: no screen recording indicator (offered as a live state
  like dictation): the user doesn't need one.
- 2026-10-13: scrolling on the pill for the volume (5% a notch, on
  every view) was built and reverted the same day: the user didn't like
  it. The pill does nothing on scroll.
- 2026-10-13: no song-changed flash ("Title – Artist" for 2 seconds on
  a new track): the user doesn't need one.
- 2026-10-13: no mic, camera or screen-share indicator and no low-battery
  flash for Bluetooth devices: the user doesn't need them. That closes
  the list of ideas from 2026-10-13.
- 2026-10-13: the user tried the brief-built `../island` and found it
  worse; the dynamic-island is the shell at login again. Its privacy
  dots and notices are brought over at the user's request ("I like the
  dots that indicate if something is recording"), reversing the same
  day's "no mic, camera or screen-share indicator". Mine: the
  announcement as a regular notice (3 s, not while a panel is open),
  the dots kept while the island is hidden, no mic notice while
  dictating.
- 2026-10-13: slimming the shell down, at the user's request: the app
  launcher is fuzzel now ("I don't need Quickshell to do everything; I
  can have another application for that"), not a Quickshell config.
