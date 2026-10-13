# Island

A standalone Quickshell config (`qs -c island`, in
`~/.dotfiles/quickshell/island`, linked to `~/.config/quickshell/island`
by the rack manifest): a dynamic island built to the project brief
below, from scratch, next to `../dynamic-island`, which it doesn't touch
or share code with. It isn't started at login; run it by hand with
`qs -n -c island -d`.

This file is the design brief. Read it before creating or changing
anything here. The project brief (the user's, 2026-10-13) is kept as
given; Implementation and Decisions below record how it was built and
every choice made on the way. `../STYLE.md` applies too, unless a
section below overrides it.

## Status

The brief's build order, one step at a time; the user looks at each
step before the next starts.

1. Priority queue + size states + input mask: **built 2026-10-13**;
   the user went on to step 2. Clicking through the mask is unconfirmed.
2. OSD: **built 2026-10-13**, awaiting the user's try with the real
   keys (only faked readings were tested).
3. Media: **built 2026-10-13**, tested with `fake-player.py`; the
   buttons and click-to-open await the user's pointer (no clicking from
   here).
4. Battery events and Hyprland state changes: **built 2026-10-13**,
   tested with simulated readings and events; awaiting a real
   plug/unplug and layout switch.
5. Privacy indicators
6. Notifications
7. IPC live-activities API
8. Split state

---

# Project brief: Dynamic island for Hyprland (Quickshell)

## Vision
Build a macOS/iOS-style "dynamic island" for Hyprland using Quickshell (QML).
It is a glanceable, transient status surface at the top-center of the screen:
it shows what is happening right now, offers one or two quick actions, then
gets out of the way. It is NOT a status bar, control center, or launcher.

## The inclusion test (apply to every feature request)
A feature belongs in the island only if it is ALL of:
1. Time-sensitive or event-driven (not persistent information)
2. Readable at a glance
3. Usable with at most one or two clicks, no typing
If it needs browsing, searching, typing, or settings, a standalone tool does
it better and it is out of scope. When in doubt, leave it out and point users
to the IPC interface (below) so they can build it themselves.

## v1 features

**Media (MPRIS)** — flagship. Compact: album art + animated playing indicator.
Expanded: title, artist, progress bar, previous/play-pause/next. Use
Quickshell's Mpris service; works with any MPRIS player.

**Notifications** — the island IS the notification daemon (Quickshell
Notifications server), replacing mako/dunst/swaync. Show incoming notifications
briefly with app icon, summary, and action buttons; support dismiss and
default action. Include a do-not-disturb toggle. No history center, grouping,
or DND scheduling.

**OSD** — brief level indicator when volume, brightness, or mic mute changes.
Volume/mute via Quickshell's Pipewire service; brightness via brightnessctl
or ddcutil. Replaces swayosd.

**Battery events** — charger plugged/unplugged, low and critical battery,
charging complete (UPower). Events only, never a constant percentage.

**Privacy indicators** — mic, camera, and screen sharing/recording in use,
detected through Pipewire nodes. See special rules below.

**Hyprland state changes** — brief indicator on submap enter/exit and keyboard
layout change, via Quickshell's Hyprland IPC events. No persistent workspaces.

**IPC "live activities" API** — the key scope-control feature. Expose an
IpcHandler so any script can push an activity (icon, label, optional progress,
optional timeout) and remove it, e.g. `qs ipc call island show ...`. Timers,
build progress, downloads, etc. are user scripts, not built-in features.

## Explicitly out of scope
App launcher (fuzzel/rofi), Wi-Fi/Bluetooth management (nmtui, impala,
bluetui), notification history center, calendar/weather/system stats (bar,
btop), clipboard history (cliphist), workspace overview (bar, hyprexpo),
system tray (bar), power menu (wlogout), built-in timer/stopwatch (use IPC),
per-app volume mixer, app permission management, GUI settings panel (use a
config file).

## Visual design
One island, not multiple bars. A single dark pill at top-center that morphs
between states with smooth size/shape animations:

- **Idle** — small pill with a clock, or a tiny notch (configurable)
- **Compact** — one persistent activity (e.g. art + waveform for media)
- **Split** — main pill plus one small detached circle when two activities
  must show at once. Maximum two shapes; a third activity waits in the queue
- **Expanded** — on hover or click; full controls for the current activity
- **Transient** — OSD, notifications, events temporarily take over, then revert

## Privacy indicator rules (special case)
Privacy indicators do NOT participate in the priority queue. They live on a
separate overlay layer that nothing can suppress: not DND, not the expanded
state, not fullscreen apps.
1. On first activation, the island expands for ~2s naming the app
   ("Firefox is using the microphone")
2. While active, a small colored dot sits at the island's right edge, pinned
   to the same position in every state
3. When inactive, the dot disappears entirely (no idle indicator)
Colors: orange = microphone, green = camera, red = screen sharing. Show one
dot per active type side by side; never merge. Clicking a dot lists which
apps are using the device.

## Architecture

**Activity priority queue (build this first).** Every feature submits
activities into one queue. Each activity has a priority and a lifetime
(persistent or timed). Transient activities temporarily override persistent
ones; when they expire, the island falls back to the highest-priority
persistent activity. Features must never manipulate the island directly.

**Window and input.** Use a layer-shell PanelWindow. The window is larger than
the visible pill to leave room for animation, so set Quickshell's `mask` with
a Region matching the visible shape. Clicks outside the pill must pass through
to windows underneath. This is the most common bug in island projects.

**Privacy dots** are drawn inside the same window as the island so they
animate with it.

**Fullscreen.** When the focused Hyprland window is fullscreen, hide the
island and shrink the input mask to only the privacy dots (which stay visible).

**Multi-monitor.** Show the island on the focused monitor only (default).

**Standalone.** The island is its own component and must coexist with any bar
the user already runs. It does not replace a bar.

**Configuration.** A single config file (JSON or a QML properties file) for
colors, sizes, timeouts, idle-state choice, and per-feature enable/disable.

## Build order
1. Priority queue + size states (idle/compact/expanded) + input mask
2. OSD (simplest feature; good for testing the queue and animations)
3. Media
4. Battery events and Hyprland state changes
5. Privacy indicators (overlay layer + fullscreen behavior)
6. Notifications (most edge cases; needs a stable framework)
7. IPC live-activities API
8. Split state

## v2 candidates (only after v1 is stable)
Wi-Fi/Bluetooth connection events (no management), screenshot confirmation
with thumbnail, per-app notification rules. Each must still pass the
inclusion test.

## Notes for the implementer
Verify Quickshell API names (services, IpcHandler, mask/Region, layer-shell
properties) against current Quickshell documentation before relying on them,
since the API evolves.

---

# Implementation

## Files

- `shell.qml`: the entry point; one `Island`.
- `Config.qml`: the config file (a QML singleton of read-only
  properties). Every colour, size, timeout and the idle choice; each
  feature's on/off switch is added with the feature.
- `ActivityQueue.qml`: the queue. Features call `submit()` and
  `remove()`; nothing else.
- `Island.qml`: the window, the pill, its states, the mask, the pointer.
- `Face.qml`: draws an activity with the face it names (`face`).
- `ActivityFace.qml`: the generic face (icon, label, progress) in the
  compact, transient and expanded layouts.
- `Osd.qml`: the OSD feature (see OSD); `OsdFace.qml` its face.
- `Media.qml`: the media feature (see Media); `MediaFace.qml` its face.
- `Battery.qml`: battery events (see Battery events).
- `HyprlandEvents.qml`: submap and layout notices (see Hyprland events).
- `fake-player.py`: a silent MPRIS player for testing (see Testing).
- `test-queue.sh`: walks every state and queue rule (see Testing).

## Quickshell API (checked against the installed 0.3.2)

From the qmltypes in `/usr/lib/qt6/qml/Quickshell`:
- `Region` has `item`, `x/y/width/height`, `radius` (and per-corner
  radii), `shape`, `intersection` and `regions`, so the mask can follow
  the pill's rounded shape and, in step 5, add the dots as more regions.
- `IpcHandler` (`Quickshell.Io`): `target`, `enabled`; functions with
  typed arguments. A function can't be called `show`: `qs ipc` reserves
  it (found in dynamic-island). So step 7 can't use the brief's
  `qs ipc call island show ...` literally; it needs another verb.
- `Pipewire` (`Quickshell.Services.Pipewire`): `defaultAudioSink`,
  `defaultAudioSource`, `ready`; a `PwNode` has `id`, `ready` and
  `audio.volume` / `audio.muted`, bound through `PwObjectTracker`.
- `Mpris` (`Quickshell.Services.Mpris`): `players` (an ObjectModel;
  `.values` is the array). `MprisPlayer` has `trackTitle`, `trackArtist`,
  `trackArtUrl`, `isPlaying`, `playbackState` (`MprisPlaybackState`
  Stopped / Playing / Paused), `position` and `length` in seconds,
  `lengthSupported`, `canGoNext`, `canGoPrevious`, `canTogglePlaying`,
  `next()`, `previous()`, `togglePlaying()`. `position` doesn't move on
  its own: emitting `positionChanged()` each second is what updates it.
- `UPower` (`Quickshell.Services.UPower`): `displayDevice`, `devices`,
  `onBattery`. `UPowerDevice` has `percentage` (0–1), `state`
  (`UPowerDeviceState`: Unknown, Charging, Discharging, Empty,
  FullyCharged, PendingCharge, PendingDischarge), `isLaptopBattery`,
  `isPresent`, `ready`.
- `ClippingRectangle` (`Quickshell.Widgets`) puts its children in an
  inner item, so their `parent` isn't the rectangle; use an id.
- Inline components (`component X: …`) can't see the file's other ids;
  pass what they need in as properties.
- `TextMetrics` has `advanceWidth` and `width`, no `implicitWidth`
  (binding that is silently undefined).
- `Hyprland` (`Quickshell.Hyprland`): `focusedMonitor`, `focusedWorkspace`,
  `activeToplevel`, `monitors`, `workspaces`, `toplevels`, `rawEvent`,
  `dispatch`. `HyprlandWorkspace.hasFullscreen` serves step 5;
  `rawEvent` serves submap and layout events in step 4.

## Activity queue

An activity is a plain object: `key`, `transient`, `priority`, `timeout`
(ms), `icon`, `label`, `progress` (0–1, or -1 for none), `face` ("osd",
or "" for the generic one) and `waits`. The queue keeps them sorted,
best first.

- **Same key, same activity.** Submitting a key already in the queue
  updates it; fields left out keep their value. The volume changing
  again updates the volume OSD instead of queueing a second one.
- **Order.** Higher priority first. Ties: transients first come, first
  shown (notifications keep their order); persistents newest first.
- **Transient.** Takes the island over from any persistent activity.
  Its timeout runs only while it is on screen, and restarts when it is
  submitted again. One waiting behind a higher transient gets its full
  time when its turn comes. No timeout given means
  `Config.transientTimeout` (2.5 s).
- **Persistent.** Shown in the compact state when no transient is up.
  A timeout is its lifetime, counted from the last submit; 0 means until
  removed.
- **Expanded holds transients.** While the island is open, transients
  wait with their timers stopped, so the controls under the pointer
  don't swap out. Privacy indicators (step 5) are outside the queue and
  not held. A transient with `waits: false` (the OSD) is dropped
  instead, both when it arrives and when the island opens over it: a
  level is stale by the time the island closes.

### Priorities

Proposed, set as each feature is built:

| Priority | Activity                                      |
|----------|-----------------------------------------------|
| 60       | notifications                                 |
| 50       | OSD                                           |
| 45       | Hyprland submap and layout                    |
| 40       | battery events                                |
| 30       | IPC live activities (the default for scripts) |
| 20       | media                                         |

## Window

- One `PanelWindow` on the focused monitor (`Hyprland.focusedMonitor`
  matched to `Quickshell.screens` by name); it moves with focus.
- Anchored top, layer `Top`, namespace `quickshell:island`. Step 5 moves
  it to `Overlay` for the privacy dots, and then hides the pill itself
  over fullscreen windows.
- The window is the expanded size plus room for the spring's overshoot
  (448 × 183). The mask is a `Region` on the pill with the pill's radius,
  so only the visible pill takes clicks.
- With `Config.reserveSpace` it reserves the top margin plus the compact
  pill's height (39px), so tiled windows start below a compact pill.
  Idle is smaller; expanded and transient overlap the windows.

## States

| State     | When                                   | Size                         |
|-----------|----------------------------------------|------------------------------|
| idle      | the queue is empty (or only transients held) | clock: time + 16px each side × 24; notch: 120 × 8 |
| compact   | a persistent activity, no transient up | content + 16px each side, 160–400 × 32 |
| transient | a transient is up                      | content + 16px each side, 160–400 × 40 |
| expanded  | clicked (or hovered, `Config.expandOn`) on a compact pill | 400 × 152 |

- Expanded opens only from compact (idle and transients have nothing to
  expand) and closes when the pointer has been off the pill for 400ms,
  on a second click, or when the last persistent activity goes.
- The generic face: compact is icon + label; transient adds a 64px level
  bar when there is a progress; expanded is a 32px icon, the label (two
  lines) and a full-width bar.

## OSD

`Osd.qml` watches three things and submits a transient whenever one
changes, from anywhere (keys, a mixer, a script); it never changes them.

- **Volume** of the default PipeWire sink, mute included. Muted reads 0%
  with the muted speaker; otherwise the speaker shows low (< 34%),
  medium (< 67%) or high.
- **Microphone mute** of the default source: "Microphone muted" or
  "Microphone on", on the generic face.
- **Brightness** of the first `/sys/class/backlight` device, read every
  200ms (sysfs sends no change events for it).

All three share the key `osd`, priority 50, `waits: false`, for
`Config.osdTimeout` (1.5 s) after the last change: the newest replaces
the one on screen. Each device's first reading only sets the baseline,
so startup and switching the output device stay quiet. `Config.osd`
turns it off.

The face (`OsdFace.qml`): the icon in 16px, 12px, a 120 × 4 bar (white
on white at 20%, easing 120ms), 12px, the percentage right-aligned in
the width of "100%". One width (224px) for every reading, and for
volume and brightness alike, so the pill holds still.

Not covered: external screens (no ddcutil; there is none to test with);
a key press at 0% or 100%, which changes nothing and so shows nothing.

## Media

`Media.qml` keeps one persistent activity, key `media`, priority 20,
face `media`, for the current MPRIS player. The activity carries the
player itself, so the face reads its position and sends its controls.

- **Which player:** the one playing; else the one that played last (so
  a pause doesn't hand the island to another open player); else any
  with a title.
- **When:** while it plays. Paused, it stays `Config.mediaPausedTimeout`
  (60 s), then leaves. A new title or art while it's gone doesn't bring
  it back; playing again does. Stopped, or no title: gone at once.
- No flash on a track change: the face updates in place.

The face (`MediaFace.qml`):
- **Compact** (200 × 32, fixed): the art at the left end (20px, 6px
  corners, 8px in), four playing bars at the right (3px wide, 2px apart,
  12px in). The bars dance (random heights 4–14px, 180ms) while playing
  and lie flat at 3px when paused, and stop while not on screen. They're
  made up, not the audio.
- **Expanded** (400 × 152): the art (56px, 12px corners) at 20, 20; the
  title, and the artist in `foregroundSoft`, beside it, cut with "…";
  the bars at the top right; a progress row (elapsed, 4px bar,
  "-remaining" in 11px) at y 88 when the player knows the length; and
  previous / play-pause / next as 36px round buttons, 24px apart, at
  y 108, a faint fill on hover, dim when the player can't. Laid out at
  full size from the top, so nothing reflows while the pill grows.
- No art: a music note on a dark square.

The pill's own MouseArea sits under the content, so the buttons take
their clicks; a click elsewhere on the pill opens or closes it. Hover
comes from a `HoverHandler`, which the buttons don't hide.

## Battery events

`Battery.qml` compares each UPower reading of the display device (both
of the T480's batteries combined) with the one before and submits a
transient on a change. Key `battery`, so the newest replaces the last;
priority 40, 3 s, the generic face.

| Event | When | Notice |
|-------|------|--------|
| charger in | `onBattery` turns false | 󰂄 "Charger connected – 46%" |
| charger out | `onBattery` turns true | 󰚦 "On battery – 46%" |
| charged | Charging → FullyCharged | 󰁹 "Fully charged" |
| charged | Charging → PendingCharge (the charge limit, 80% here) | 󰁹 "Charged to 80%" |
| low | on battery, crossing below `batteryLowPercent` (20) | 󰁺 "Low battery – 19%" |
| critical | on battery, crossing below `batteryCriticalPercent` (5), or already below it at start | 󰂃 "Battery critical – 4%", priority 55, 6 s |

The first reading, and any in the first 2 seconds, only sets the
baseline. A charger plugged in at the limit goes straight to
PendingCharge without Charging, so it says "Charger connected" only.
`Config.battery` turns it off.

## Hyprland events

`HyprlandEvents.qml` reads Hyprland's raw events. Priority 45, 1.5 s,
the generic face.

- **Submap** (`submap>>name`, "" on leaving): 󰌨 "Submap – resize",
  then "Submap – resize off". Key `submap`. There are no submaps in the
  hypr config yet; only tested with made-up events.
- **Keyboard layout** (`activelayout>>keyboard,layout`): 󰌌 "Layout –
  Swedish", key `layout`. Each keyboard device has a layout of its own
  (here the built-in keyboard is English (US), the extra buttons
  Swedish), so a change counts only against that same keyboard's last
  layout, read from `hyprctl devices -j` at start; a keyboard's first
  report only sets it, and virtual keyboards (`hl-virtual-keyboard…`)
  are left out. The dynamic-island learnt this: comparing against the
  "main" keyboard flashed whenever another device was used.

`Config.hyprlandEvents` turns both off.

## Look

The dynamic-island's look, since it is the user's: a black pill, white
text in JetBrainsMono Nerd Font Bold 13px, fully rounded (radius height
/ 2) up to 32px once expanded. Colours are `Config`'s own, not
`Appearance` tokens (overrides `STYLE.md` §2), and the pill is fully
round (overrides §5's 2px corners).

## Motion

- The pill's width and height follow the state on a spring (`spring 4`,
  `damping 0.36`), with a slight overshoot; it grows down and outward
  from the top centre.
- The content fades out (80ms), swaps, and fades in (140ms, OutCubic)
  while the pill is still moving. An update to the activity on screen
  (a new progress) changes in place, without the fade.
- Level bars ease to a new value (120ms, OutCubic).

## Testing

`./test-queue.sh` walks idle, compact, transient over compact, an update
in place, two transients in priority order, a higher persistent and the
fall back, expanded holding a transient, a persistent's lifetime, and
idle again. It uses two test-only IPC targets, which step 7's API
doesn't replace:

- `qs -c island ipc call queue persist|flash key icon label progress priority ms`,
  `drop key`, `clear`, `list`.
- `qs -c island ipc call view expand|collapse|current`.
- `qs -c island ipc call battery simulate <onBattery> <percent> <state>`
  (state: charging, discharging, full, pending) feeds made-up readings
  through the same comparison, the first against the real reading;
  `battery real` goes back to UPower without an event.
- `qs -c island ipc call hyprland submap <name>` ("" leaves) and
  `hyprland layout "<keyboard>,<layout>"` feed made-up events. Put the
  layout back afterwards, or the next real event compares against it.
- `./fake-player.py [--art FILE] [--paused]`: a silent MPRIS player
  ("Island test player", three tracks, one with a long title) that
  `playerctl -p islandtest play|pause|next|previous` drives. Never play
  real audio to test.
- `qs -c island ipc call osd volume <0–1> <muted>`, `brightness <0–1>`,
  `mic <muted>`: the OSD for made-up readings. Never change the real
  volume, microphone or brightness to test.

The file watcher often misses saves made with the Edit tool: check the
log for "Reloading configuration", else restart (`qs kill -c island`,
then `qs -n -c island -d`). Calls made mid-reload answer "Function not
found". In zsh, a loop's `$args` doesn't split into words; use
`${=args}`.

Running it next to the dynamic-island puts two pills at the top centre;
SUPER+ALT+SPACE hides the dynamic-island meanwhile.

# Decisions

- 2026-10-13: a new config built from this brief, next to the
  dynamic-island, not a rework of it. The user's pick over adopting the
  brief's good parts into the dynamic-island, replacing its brief, or a
  comparison only. The two disagree on notifications, privacy dots,
  Wi-Fi/Bluetooth pages, the settings window, the power menu and
  replacing the bar; this config follows the brief.
- 2026-10-13: named `island` (after the brief's `qs ipc call island`);
  not started at login. Mine.
- 2026-10-13: the config file is a QML singleton (`Config.qml`), which
  the brief allows: it reloads on save and can carry comments. Mine.
- 2026-10-13: the queue rules above (same key updates, tie order,
  transient time counted only on screen, expanded holds transients,
  priorities). Mine; the brief leaves them open.
- 2026-10-13: expanded opens on click by default, closes 400ms after the
  pointer leaves. Mine.
- 2026-10-13: the focused-monitor rule is built in step 1 with the
  window, not later. Mine.
- 2026-10-13: the dynamic-island's look (black, white, bold, round). Mine.
- 2026-10-13: step 2, the OSD, at the user's go-ahead. Mine: one key for
  volume, brightness and the mic (newest wins); a fixed-width level face
  with no label; muted reads 0%; the mic as a text notice; `waits:
  false`; brightness polled every 200ms.
- 2026-10-13: step 3, media, at the user's go-ahead. Mine: which
  player; a paused player leaves after 60 s; no track-changed flash
  (the user turned one down for the dynamic-island); made-up playing
  bars in white rather than tinted from the art; the progress bar shows
  only, no seeking.
- 2026-10-13: step 4, battery and Hyprland events, at the user's
  go-ahead. Mine: the wording; one key per kind (newest wins); critical
  above the OSD (55) and 6 s; the charge limit counts as charged; the
  submap as a brief notice on entering and leaving, as the brief says,
  not a standing activity while in it.
- 2026-10-13: no global shortcuts from the volume and brightness keys
  (the dynamic-island's way of answering a press at 0% or 100%). It
  would mean new shortcut names and edits to `hypr/modules/binds`;
  open, for the user.
