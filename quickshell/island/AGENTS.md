# Island

A standalone Quickshell config (`qs -c island`, in
`~/.dotfiles/quickshell/island`, linked to `~/.config/quickshell/island`
by the rack manifest): a dynamic island built to the project brief
below, from scratch, next to `../dynamic-island`, which it doesn't touch
or share code with. Since 2026-10-13 it is the shell at login, in the
dynamic-island's place (`hypr/modules/autostart.lua`:
`env QT_QPA_PLATFORMTHEME=gtk3 qs -n -c island`; the GTK theme plugin
gives it the icon theme, the session's qt5ct isn't installed for Qt 6).
By hand, add `-d`. While it runs it is the notification daemon in
dunst's place (see Notifications).

This file is the design brief. Read it before creating or changing
anything here. The project brief (the user's, 2026-10-13) is kept as
given; Implementation and Decisions below record how it was built and
every choice made on the way. `../STYLE.md` applies too, unless a
section below overrides it.

## Status

The brief's build order, one step at a time; the user looks at each
step before the next starts.

Before step 6, the research brief's fixes (2026-10-13): interruption
profiles with their timings, shorter exits, still playing bars, and
dismissing with a right click. Built and measured; awaiting the
user's look and right click.

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
5. Privacy indicators: **built 2026-10-13**, tested with
   `fake-capture.sh` (fake PipeWire devices), wf-recorder and a faked
   fullscreen; clicking a dot awaits the user's pointer.
6. Notifications: **built 2026-10-13**, tested with `notify-send`
   and test calls; clicks, hover and the middle click await the user.
7. IPC live-activities API: **built 2026-10-13**, tested through
   `island-activity`; awaiting the user's own scripts.
8. Split state: **built 2026-10-13**, tested with live activities,
   media and the hold count; clicking the circle awaits the user.

v1 is complete. Next would be tuning with real use, then the brief's
v2 candidates, each through the inclusion test.

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

# Research brief: interruption, motion and privacy

Added 2026-10-13 at the user's request, kept as given. It is binding
next to the project brief; where they disagree, the choice is recorded
under Decisions (or marked _TBD_ until the user makes it). Its numbers
are starting points to tune, not rules.

13 okt. 2026 · @Brandon

## Bottom line

Interrupt less, at better moments, with less motion, and make privacy signals impossible to miss. Research on interruptions, notifications, peripheral motion and privacy indicators points the same way. This brief turns it into design rules for our Quickshell dynamic island on Hyprland.

## Findings and what we do

|Area|Finding|What we do|
|---|---|---|
|Interruption timing|Interruptions cost less at low-workload moments; busy states lasted about 21 s on average before easing (Iqbal and Bailey; Horvitz et al.)|Hold low-priority notifications briefly; release on workspace switch, focus change or window close|
|Notification volume|Batching 3 times a day improved attention and mood; hourly batching did little; no notifications raised anxiety (Fitz et al.)|Replace binary DND with a hold mode that shows a count and releases on demand|
|Peripheral motion|Simple motion beats color and shape for detection in the periphery, but some motion irritates (Bartram et al.)|Morph once on arrival; no constant motion; make the media waveform subtle or optional|
|Animation timing|About 100 ms feels immediate; 200–300 ms suits larger changes; exits can be shorter (NN/g, Material)|Use the timing defaults below|
|Privacy indicators|45% noticed webcam LEDs during computer tasks; on-screen glyphs raised it to 93% (Portnoff et al.)|Keep on-screen dots unsuppressible; expand briefly on first use|
|Live Activities|Activities should have a defined start and end and be user-controlled; two activities show as attached plus detached (Apple HIG)|Require every IPC activity to end (explicit or timeout); let users dismiss any activity; keep the split state|
|Priority model|Notification systems trade off interruption, reaction and comprehension (McCrickard)|Give each activity type an IRC profile that sets its priority and animation intensity|

## Starting defaults

These are starting points to tune in testing, not research-validated values.

|Activity|Interruption|Deferral|Enter animation|Exit animation|
|---|---|---|---|---|
|Privacy event|High, once|None|250 ms expand, ~2 s label|150 ms to dot|
|Urgent notification|High|None|250–300 ms|150–200 ms|
|Normal notification|Medium|Up to 45 s, released at next break|250–300 ms|150–200 ms|
|OSD (volume, brightness, mic)|Low|None|~100 ms|~150 ms|
|Battery and Hyprland events|Low|Up to 45 s, except critical battery|200–250 ms|150 ms|
|IPC activity|Set by caller, capped at Medium|Same as normal notification|250 ms|150–200 ms|

## Caveats

Most of these studies are lab-based, older, or done on phones rather than desktops. The batching study ran for about two weeks with smartphone users in India. Treat the findings as direction and validate the defaults with our own use.

## Sources

- [Iqbal and Bailey, Leveraging Characteristics of Task Structure to Predict the Cost of Interruption (CHI 2006)](https://interruptions.net/literature/Iqbal-CHI06-p741-iqbal.pdf)
- [Cutrell, Czerwinski and Horvitz, Effects of Instant Messaging Interruptions on Computing Tasks (CHI 2000)](https://www.interruptions.net/literature/Cutrell-CHI00.pdf)
- [Horvitz, Apacible and Subramani, Balancing Awareness and Interruption: Notification Deferral Policies (2005)](https://www.erichorvitz.com/bdef_studies.pdf)
- [Fitz et al., Batching Smartphone Notifications Can Improve Well-Being (2019)](https://scholars.duke.edu/publication/1402953)
- [Bartram, Ware and Calvert, Moticons: Detection, Distraction and Task (2003)](https://scholars.unh.edu/ccom/979)
- [Portnoff et al., Somebody's Watching Me? Assessing the Effectiveness of Webcam Indicator Lights (CHI 2015)](https://blues.cs.berkeley.edu/?p=159)
- [McCrickard et al., A Model for Notification Systems Evaluation (TOCHI 2003)](https://www.interruptions.net/literature/McCrickard-TOCHI03.pdf)
- [Apple Live Activities design guidelines, summarized by 9to5Mac](https://9to5mac.com/2022/09/26/iphone-14-pro-live-activities-guidelines/)
- [Animation duration guidance citing NN/g and Material Design](https://lists.w3.org/Archives/Public/public-css-archive/2025Apr/0702.html)

## Where it meets the project brief

Settled by the user, 2026-10-13:
- **A hold mode, not DND.** Step 6 builds the research's hold mode (it
  shows a count and releases on demand) in place of the project brief's
  do-not-disturb toggle.
- **Only low battery is deferred** of the battery and Hyprland events.
  Charger, charged, layout and submap notices answer the user's own
  action and show at once; critical battery never waits.

For step 7 (built): IPC activities must end (a timeout or an explicit
removal) and are capped at medium interruption.

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
- `Notifications.qml`: the notification daemon and the hold mode (see
  Notifications); `NotificationFace.qml` a notification's card,
  `HoldFace.qml` the hold count, `PillButton.qml` their buttons.
- `LiveActivities.qml`: the scripts' API, IPC target `island` (see Live
  activities); `island-activity` the command-line wrapper for it.
- `Privacy.qml`: who is using the microphone, camera and screen, and
  the announcements (see Privacy indicators). Not in the queue.
- `Battery.qml`: battery events (see Battery events).
- `HyprlandEvents.qml`: submap and layout notices (see Hyprland events).
- `fake-player.py`: a silent MPRIS player for testing (see Testing).
- `fake-capture.sh`: fake microphone, camera or screen use through
  PipeWire, no real device (see Testing).
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
- `Pipewire.linkGroups` (`.values`): `PwLinkGroup` has `source`,
  `target` (nodes) and `state` (`PwLinkState`, PipeWire's numbers:
  Error -2, Unlinked -1, Init 0 … Paused 3, Active 4). The state reads
  -1 until the group itself is in a `PwObjectTracker`; so does a node's
  `properties` (`media.class`, `device.api`, `application.name`).
  `.values` is a list type, not a JS array: `Array.from` it.
- Qt's JavaScript has no `Array.prototype.flatMap`.
- `NotificationServer` (`Quickshell.Services.Notifications`) emits
  `notification(n)`; set `n.tracked = true` to keep it. `Notification`
  has `id`, `appName`, `appIcon`, `summary`, `body`, `image`,
  `urgency` (`NotificationUrgency` Low / Normal / Critical),
  `expireTimeout` in **milliseconds** (-1 default, 0 never), `actions`
  (a list type; `NotificationAction` has `identifier`, `text`,
  `invoke()`), `resident`, `transient`, `desktopEntry`, `dismiss()`,
  `expire()` and the `closed` signal. A replacement (`replaces_id`)
  changes the same object; `notification` isn't emitted again. A theme
  icon name arrives as `image` "image://icon/<name>", which draws a
  checkerboard when the name isn't in the theme.
- `Quickshell.iconPath(name, true)` returns "" for every name without
  an icon theme; the island needs `QT_QPA_PLATFORMTHEME=gtk3`.
- The island measures the content it is heading for with an invisible
  copy of the face: in it, `visible` reads false for every child, but
  positioners (Row, Column) still lay out by each item's own
  `visible`. Compute sizes from data, never from a child's `visible`.
- Hyprland sends `activewindowv2` again, with the same address,
  whenever the focused window's title changes (a terminal's spinner:
  several a second). A focus change is a new address.
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

An activity is a plain object: `key`, `transient`, `profile`,
`priority`, `timeout` (ms), `icon`, `label`, `progress` (0–1, or -1 for
none), `face` ("osd", "media", or "" for the generic one), `waits` and
`revive`. The queue keeps them sorted, best first.

- **Profile.** Each activity names its interruption profile (see
  Interruption and motion), which sets its priority unless it gives
  one, and how the pill moves for it.
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

- **Deferral.** A transient whose profile has a `defer` (low battery;
  normal notifications and IPC activities to come) waits, unseen, for
  a break: a workspace switch (`workspace`), focus moving to another
  window (`activewindowv2` with a new address), or a window closing
  (`closewindow`). It shows then, or when `defer` (45 s) runs out, in
  its order of arrival. An update of the same profile keeps it waiting;
  another kind under the same key ("Charger connected" for a waiting
  "Low battery") replaces it and shows at once.
- **Dismissing.** A right click on the pill dismisses what it shows
  (`ActivityQueue.dismiss`): a transient is gone; a persistent one
  leaves and stays away, its feature's updates ignored, until the
  feature submits it with `revive` or removes it. Media revives when
  the player starts or pauses again, or another player takes over; a
  new track doesn't bring it back. A privacy announcement makes way for
  the next; its dot stays.

## Window

- One `PanelWindow` on the focused monitor (`Hyprland.focusedMonitor`
  matched to `Quickshell.screens` by name); it moves with focus.
- Anchored top, layer `Overlay` (so the privacy dots stay over
  fullscreen windows), namespace `quickshell:island`.
- The window is the expanded size plus room for the split's circle and
  the dots on either side, and an overshoot (600 × 183). The mask is a
  `Region` of three: the pill (with its radius), the circle while it is
  out, and the dots. Only those take clicks.
- **Fullscreen:** when the focused workspace has a fullscreen window
  (`Hyprland.focusedWorkspace.hasFullscreen`), the pill fades and
  shrinks away (160ms) and leaves the mask; the expanded state closes.
  The dots stay, and a privacy announcement brings the pill back for its
  2 seconds.
- With `Config.reserveSpace` it reserves the top margin plus the compact
  pill's height (39px), so tiled windows start below a compact pill.
  Idle is smaller; expanded and transient overlap the windows.

## States

| State     | When                                   | Size                         |
|-----------|----------------------------------------|------------------------------|
| idle      | the queue is empty (or only transients held) | clock: time + 16px each side × 24; notch: 120 × 8 |
| compact   | a persistent activity, no transient up | content + 16px each side, 160–400 × 32 |
| transient | a transient is up                      | content + 16px each side, 160–400 × 40 |
| expanded  | clicked (or hovered, `Config.expandOn`) on a compact pill, or the split's circle | 400 × the face's height (152 for media and the generic face) |
| split     | compact, with a second persistent activity | the pill, plus a 32px circle 8px to its right |

- Expanded opens only from compact (idle and transients have nothing to
  expand) and closes when the pointer has been off the pill for 400ms,
  on a second click, or when the last persistent activity goes.
- A right click on the pill dismisses what it shows (see Activity
  queue, Dismissing).

### Split

The brief's two shapes: while compact, a second persistent activity
(the queue's next after the top one) shows in a circle as tall as the
compact pill (32px), 8px right of it, centred on its first line. A
third waits. Transients, announcements and the expanded state take the
whole island; the circle steps back for them and returns after.
- **Motion:** the circle grows out from under the pill's right end
  (scale 0.5 → 1, sliding out) at its activity's enter time, and tucks
  back at its exit time; `splitReach` carries it, and the privacy dots
  ride on it, so they stay at the island's right edge. Another activity
  taking the circle crossfades (60 + 120ms).
- **Minimal faces:** the generic one draws the icon, ringed by the
  level when there is one (2px, white over the 20% track, from 12
  o'clock); media the album art, round (20px); the hold count its
  number, or the bell while none are held; a kept notification its
  picture, round.
- **Pointer:** a click opens the circle's activity expanded (not the
  top one); a right click dismisses it.
- Hidden over fullscreen with the pill.
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
  12px in). Made up, not the audio. `Config.mediaBars`: "still" (the
  default, from the research: no constant motion) stands them at 6, 11,
  8 and 13px while playing; "subtle" swells them ±2px around that every
  0.7s; "dancing" is random 4–14px every 180ms. Flat at 3px when paused;
  moving ones stop while not on screen.
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
| low | on battery, crossing below `batteryLowPercent` (20); waits up to 45 s for a break (profile `lowBattery`) | 󰁺 "Low battery – 19%" |
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

## Privacy indicators

`Privacy.qml`, outside the queue: nothing in the queue, DND, the
expanded state or fullscreen hides it. `Config.privacy` is the only off
switch.

**Detection.** From PipeWire: every active link from a capture device
to an app's stream. The source says what is captured:
- `Audio/Source…` → microphone. A sink's monitor (an `Audio/Sink`,
  playback being captured) doesn't count, nor a level meter
  (`stream.monitor`).
- `Video/Source` with a `device.api` (v4l2, libcamera) → camera. The
  T480's camera is a PipeWire node (`v4l2_input…`), so apps that use it
  through PipeWire show; one that opens `/dev/video0` directly doesn't
  (not covered).
- any other `Video/Source` → screen sharing (xdg-desktop-portal's
  streams).
The app is the stream's `application.name` (or its binary, description
or name). Screen recorders that use wlr-screencopy (wf-recorder) never
touch PipeWire: Hyprland's `screencast` event says only that one started
or stopped, so it counts once it has run 1.5 seconds (a grim screenshot
doesn't light the dot), named "Something".

**Dots.** One per device in use, microphone, camera, screen in that
order, never merged: 8px, orange `#ff9f0a`, green `#30d158`, red
`#ff453a` (`Config.privacy*`), 8px apart in 16px hit areas, starting
4px right of the pill and centred on its first line, so they ride along
as it morphs. A dot pops in (160ms, OutBack) and goes at once. Clicking
one names every app on that device for 3 seconds.

**Announcement.** A device going from unused to used makes the island
name it for 2 seconds, over everything (the expanded state comes back
after): the device's glyph in white (the dot beside it already carries
the colour) and "Firefox is using the microphone", "OBS is sharing the
screen", "Something is recording the screen". Several apps: "Microphone
– Firefox, Discord". Devices starting together take turns. A device
that was off for less than 2 seconds (a stream renegotiating) comes
back without one.

Not covered: the dynamic-island's own level meters (its Sound page,
its dictation waveform) read the microphone and may light the dot as
"quickshell"; untested.

## Notifications

`Notifications.qml` is the notification daemon: a `NotificationServer`
(actions, body with markup, images, persistence; no inline reply, no
links, no action icons).

**Taking over from dunst.** One program can own
`org.freedesktop.Notifications`. dunst is a D-Bus-started user unit, so
the island runs `systemctl --user stop dunst.service` and then
registers; a second later it checks the owner and warns in the log if
it isn't the island. When the island quits, the name is free and the
next notification starts dunst again (checked both ways). While the
island runs, the dynamic-island's Do not disturb (dunstctl) does
nothing, and its critical-battery and disk alerts come to the island.
`Config.notifications` false leaves dunst alone.

**Showing.** Each notification is a transient, key `notification:<id>`,
face `notification`:
- **Critical**: profile `urgent` (70, high: 280ms in with an overshoot),
  never waits, shows 8 s (`notificationUrgentTimeout`), then stays as a
  compact activity (icon + summary) until dismissed. One that asks never
  to expire (timeout 0) stays the same way after its usual time.
- **Normal and low**: profile `notification` (60, medium), waits up to
  45 s for a break; shows its own timeout if it gives one, else 5 s
  (low: 3 s).
- The card: the picture (the notification's image, else the app's icon
  from the theme, else its desktop entry's, else a bell) 32px with 8px
  corners; the summary (one line) and the body (two lines, four
  expanded; basic markup) in `foregroundSoft`; up to three action
  buttons (every action but "default") at the bottom right. Laid out at
  full width from the top. Its height sets the pill's.
- A click on the card runs the default action, or just dismisses it
  when there is none; a button runs its action. Either way it leaves,
  unless it is resident. A right click dismisses it (the app hears
  "dismissed"); running out of time expires it (the app hears
  "expired"). The pointer resting on a transient stops its time, which
  starts over when it leaves.
- An app updating its notification ("Copying… 90%") updates the one up,
  its time started over. An app closing it takes it away.

**Hold mode** (the research brief's, in place of DND). While holding,
every notification but a critical one is kept back unseen, and a
compact activity shows the count: a bell and "3 held" (priority 25,
above media), or "Holding" while none are (10, below media). Expanded:
"3 notifications held", "Show" (shows them now, in order, without
waiting for a break) and "Stop holding" (turns it off and shows them).
A right click on the count stops holding too. On and off: a middle
click on the pill, or IPC (`notifications toggleHold`), which a
Hyprland bind can run; none is bound yet. No `GlobalShortcut` (see
Testing, Stopping).

Not built: notification history, grouping, schedules (the brief rules
them out); inline replies (typing).

## Live activities

The project brief's scope valve: timers, downloads and builds are the
user's scripts, which put activities in the island through IPC target
`island` (`qs -c island ipc call island <function> …`; the brief's
`show` is reserved by `qs ipc`, hence `push`). Keys are `ipc:<id>`, the
generic face (icon, label, progress).

| Function | Does |
|----------|------|
| `push id icon label progress timeout` | a live activity: compact, stays |
| `pushLow …` | the same below media |
| `flash id icon label progress timeout` | a one-off notice, after the next break |
| `flashLow …` | the same at low interruption |
| `progress id value` | updates the level (0–1, -1 none) |
| `label id text` | updates the text |
| `remove id` | ends it |
| `list` | `id<TAB>label` per line |

- `icon` is a Nerd Font glyph, "" for 󰫑; `progress` -1 for none;
  `timeout` ms, 0 for the default. Each returns "" or what was wrong.
- **Every activity ends** (the research brief): a pushed one when the
  script removes it, at its `timeout`, or, given none, 10 minutes
  (`Config.liveActivityIdleTimeout`) after its last push or update, so
  a forgotten one goes away. A flash: after its timeout (2.5 s).
- **Capped at medium:** profile `ipc` (medium, 30, above media) or
  `ipcLow` (low, 15, below it). Nothing a script sends interrupts like a
  critical notification.
- **Deferral:** flashes wait for a break, up to 45 s, like normal
  notifications. Pushed activities show at once: they report on
  something the user started. (Mine; the research's "same as normal
  notification" is read as for the notices.)
- **Dismissing:** a right click ends one for the user; the script's
  later pushes and updates are ignored (and answered "") until it
  removes the id and pushes it again.
- Compact shows the level too (a 40px bar), so a download reads at a
  glance.

`island-activity` (next to this file) fills in the defaults:

```sh
island-activity push download "report.pdf" --icon 󰇚 --progress 0.3
island-activity progress download 0.75
island-activity flash build "Build finished" --icon 󰄬
island-activity remove download
island-activity push tea "Tea – 3:00" --icon 󱎫 --low --timeout 180000
```

It exits 1 with the island's message when something is wrong. Not on
PATH; link it from `~/.local/bin` to use it from anywhere.

## Look

The dynamic-island's look, since it is the user's: a black pill, white
text in JetBrainsMono Nerd Font Bold 13px, fully rounded (radius height
/ 2) up to 32px once expanded. Colours are `Config`'s own, not
`Appearance` tokens (overrides `STYLE.md` §2), and the pill is fully
round (overrides §5's 2px corners).

## Interruption and motion

From the research brief. Every activity type has an interruption
profile in `Config.profiles`: its priority, and the pill's morph when
it arrives (enter) and when the island falls back after it (exit).

| Profile | Interruption | Priority | Enter | Exit | Overshoot | Defer |
|---------|--------------|----------|-------|------|-----------|-------|
| privacy | high | (not queued) | 250 | 150 | yes | – |
| urgent (step 6) | high | 70 | 280 | 180 | yes | – |
| notification (step 6) | medium | 60 | 280 | 180 | no | 45 s |
| criticalBattery | high | 55 | 250 | 150 | yes | – |
| osd | low | 50 | 100 | 150 | no | – |
| hyprland | low | 45 | 220 | 150 | no | – |
| battery | low | 40 | 220 | 150 | no | – |
| lowBattery | low | 40 | 220 | 150 | no | 45 s |
| ipc | medium | 30 | 250 | 180 | no | 45 s (flashes) |
| ipcLow | low | 15 | 220 | 150 | no | 45 s (flashes) |
| media | low | 20 | 250 | 150 | no | – |

- **Which time.** Something arriving (a transient, an announcement, or
  an activity outranking the one up) moves at its enter time. Falling
  back after one leaves moves at the leaver's exit time. Opening the
  expanded state takes 280ms, closing it 180ms; the pill fitting new
  content with nothing arriving or leaving (a longer title) 150ms.
- **How.** OutCubic, decelerating. A high-interruption arrival gets one
  slight overshoot (OutBack, 0.8); nothing else bounces, and nothing
  moves twice: the morph happens once.
- **Content** fades out in the first 30% of that time, swaps, and fades
  in over the rest, while the pill is still moving. An update to the
  activity on screen (a new progress) changes in place, without a fade.
- Measured (to within 1px): OSD in ~90ms, out ~135ms; battery event
  in ~185, out ~120; expand ~235, collapse ~150; privacy and critical
  battery in ~235 with one overshoot.
- Level bars ease to a new value (120ms, OutCubic).
- The pill's size goes through `pillWidth`/`pillHeight`, set once per
  event-loop turn (`Qt.callLater`) after the time is chosen: a Behavior
  reads its duration when it starts, so the time has to be in place
  before the size moves.

## Testing

`./test-queue.sh` walks idle, compact, transient over compact, an update
in place, two transients in priority order, a higher persistent and the
fall back, expanded holding a transient, a persistent's lifetime, and
idle again. It uses two test-only IPC targets, which step 7's API
doesn't replace:

- `qs -c island ipc call queue persist|flash key icon label progress priority ms`,
  `drop key`, `clear`, `list`.
- `notify-send` sends real ones; `-u critical`, `-t <ms>`, `-A id=label`
  (it waits and prints the chosen action), `-p` (prints the id) and
  `-r <id>` (replaces). Normal ones wait for a break: `queue release`.
- `qs -c island ipc call notifications hold <bool>|toggleHold|release|status`,
  `act <id> <action>` (what a click, "default", or a button does), and
  `icon <name>` (what a theme name resolves to).
- Stopping: `qs kill -c island`. In step 6 it crashed on the way out
  three times in five (Qt aborting in `QWindow::unsetCursor`, and a
  Wayland request sent after the connection closed), and Quickshell's
  crash handler started it again. The crashes began with step 6's
  `GlobalShortcut` (the hold toggle), a Wayland object; with it removed,
  five starts and stops in a row were clean. Likely the cause, not
  proven: don't add a `GlobalShortcut`; bind keys to IPC instead. If it
  ever comes back after stopping, `kill -9 <pid>` (from `qs list --all`)
  ends it; only ever the island's own pid.
- `./island-activity …` exercises the live-activities API (see Live
  activities).
- `qs -c island ipc call queue release`: what a break does to waiting
  activities; `queue list` shows them as "deferred Ns".
- `qs -c island ipc call view second` (the circle's activity, "" for
  none), `expandSecond` and `dismissSecond` (a click and a right click
  on the circle).
- `qs -c island ipc call view expand|collapse|current|dismiss`
  (dismiss: what a right click does); `queue dismiss <key>`. `queue
  list` also lists dismissed keys.
- `qs -c island ipc call battery simulate <onBattery> <percent> <state>`
  (state: charging, discharging, full, pending) feeds made-up readings
  through the same comparison, the first against the real reading;
  `battery real` goes back to UPower without an event.
- `qs -c island ipc call hyprland submap <name>` ("" leaves) and
  `hyprland layout "<keyboard>,<layout>"` feed made-up events. Put the
  layout back afterwards, or the next real event compares against it.
- `./fake-capture.sh mic|camera|screen [app]`: a fake device and a fake
  app reading it, both PipeWire nodes, linked by hand; runs until
  Ctrl+C. The reader never connects on its own (`node.autoconnect =
  false`), and the script stops if it finds it linked to anything else.
  Never test with `pw-record --target`: when the target is missing it
  records from the real microphone.
- `qs -c island ipc call privacy add|drop <kind> <app>` (made-up users,
  "" for an unknown app), `clear`, `list <kind>` (what a dot click
  does), `users`, and `links` (every link group as Quickshell sees it).
- `qs -c island ipc call view fullscreen <bool>` pretends a fullscreen
  window is focused; `view fullscreenReal` goes back to Hyprland.
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

- 2026-10-13: the user stopped the dynamic-island and made this island
  the shell at login in its place. Lost with the dynamic-island, and
  not in this island (by the brief, or not yet): the settings window
  (SUPER+COMMA), the wallpaper gallery (SUPER+ALT+W), its power menu,
  Wi-Fi/Bluetooth pages and quick settings, the dictation waveform, the
  Caps Lock notice, the disk-full warning; and its login jobs: writing
  the saved battery charge limit back if a battery forgot it, and
  putting the saved night light back. Its Do not disturb (dunstctl)
  has no dunst to talk to while this island runs.

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
- 2026-10-13: step 5, privacy indicators, at the user's go-ahead.
  Mine: dots outside the pill at its right, on its first line; the
  announcement as the generic face with a white glyph (a coloured dot in
  it too was a double mark, §8); camera vs screen by `device.api`;
  Hyprland's screencast event as a second source for screen recording,
  after 1.5 s; the 2-second grace against re-announcing; the window on
  the Overlay layer from now on.
- 2026-10-13: the research brief added, at the user's request, and its
  fixes made before step 6: interruption profiles (priority and motion
  per activity type) at its starting timings; exits shorter than
  entries; the spring replaced by eased morphs, one overshoot only for
  high interruption; the playing bars still by default ("subtle" and
  "dancing" as options); a right click dismisses any activity. Mine:
  right click as the gesture; media staying dismissed through new
  tracks; the exact numbers within its ranges. Deferral and DND vs hold
  mode left _TBD_ for step 6.
- 2026-10-13: step 8, the split state, at the user's go-ahead. Mine:
  compact only; the circle right of the pill, growing out from under
  its end; the queue's order decides which goes in the circle (so a
  held count above media puts the music in the circle); minimal faces;
  a click expands the circle's activity. v1 complete.
- 2026-10-13: step 7, live activities, at the user's go-ahead. Mine:
  `push`/`flash` (and `Low` forms), `progress`, `label`, `remove`,
  `list`; 10 minutes without an update ends a pushed one; pushed ones
  not deferred, flashes deferred; a dismissal holds until the script
  removes and pushes again; progress shown compact; the
  `island-activity` wrapper. Also: the hold toggle's `GlobalShortcut`
  removed after it was found the likely cause of the crashes on
  quitting.
- 2026-10-13: step 6, notifications, at the user's go-ahead (they had
  been told the island takes over from dunst while it runs). Mine:
  stopping dunst's unit to take the name; critical (and never-expiring)
  ones kept small until dismissed, as dunst kept critical ones; 5 s / 3 s
  / 8 s; a click with no default action dismisses; hover pauses; the
  hold count above media only when something is held; a middle click
  and an unbound shortcut for hold; a right click on the count stops
  holding.
- 2026-10-13: the user chose the research's hold mode over the project
  brief's DND toggle (step 6), and to defer only low battery among the
  battery and Hyprland events. Deferral built in the queue for any
  profile with a `defer`: released by a workspace switch, a focus
  change (a new window address, not a title change) or a window
  closing, else after 45 s.
- 2026-10-13: no global shortcuts from the volume and brightness keys
  (the dynamic-island's way of answering a press at 0% or 100%). It
  would mean new shortcut names and edits to `hypr/modules/binds`;
  open, for the user.
