# hypr

Hyprland (Lua config, 0.56), hypridle and hyprlock. `~/.config/hypr` links here.

The config files carry no comments. Everything worth knowing about a line
lives in this file instead, under the file the line is in, and is found by
the name of the rule, bind, function or setting. When you change a line
whose reason is written here, change the note here too.

Dispatches are Lua: `hyprctl dispatch 'hl.dsp.exit()'`, not
`hyprctl dispatch exit`. Type stubs are in `/usr/share/hypr/stubs/hl.meta.lua`,
the stock config with real usage in `/usr/share/hypr/hyprland.lua`.

## Files

| File | Owns |
|---|---|
| `hyprland.lua` | Entry point. Requires the modules in order, then `local.lua` |
| `local.lua` | This machine's monitors and input. Generated, not in git |
| `modules/env.lua` | Session environment variables, `PATH` |
| `modules/monitors.lua` | Monitor defaults for a machine with no `local.lua` |
| `modules/input.lua` | Keyboard, pointer, touchpad defaults; the 3-finger gesture |
| `modules/decorations.lua` | Gaps, borders, rounding, shadow, blur, animations |
| `modules/colors.lua` | Border colours |
| `modules/layout.lua` | dwindle, master and scrolling layout options |
| `modules/misc.lua` | Hyprland's default wallpaper and logo, both off |
| `modules/autostart.lua` | What starts at login |
| `modules/windowrules.lua` | Window and layer rules |
| `modules/snap.lua` | Spots window drags for the `snap` Quickshell config and places the window it drops |
| `modules/features.lua` | Reads which optional features are on (all, since rack left) |
| `modules/defaults.lua` | Default apps per role |
| `modules/vars.lua` | `mainMod` and the app roles the binds share |
| `modules/binds.lua` | Requires every file in `modules/binds/` |
| `modules/binds/*.lua` | One file per group of keys, see [Keymap](#keymap) |
| `hypridle.conf` | Idle timers: lock, screen off, suspend |
| `hypridle.local.conf` | This machine's timers. Generated, not in git |
| `hyprlock.conf` | The lock screen |

## Machine-local files

`local.lua` and `hypridle.local.conf` are written by the settings window
(SUPER+COMMA, in the dynamic island) from `~/.local/state/dynamic-island/settings.json`,
by `quickshell/dynamic-island/LocalConfig.qml` (with `Displays.qml` and
`InputSettings.qml`). Edits by hand are lost on its next save. Both are
ignored by git, since each laptop has its own screens, touchpad and timers.
The comments inside them come from that generator, not from this repo.

`hyprland.lua` requires `local.lua` last, and only if it exists, so it wins
over every module. Monitors in it are keyed by description (`desc:...`), so
each screen gets its own settings back whenever it is plugged in. Touchpad
speed is set per device with `hl.device`, because Hyprland has no
touchpad-wide sensitivity.

## Keymap

`SUPER` is `vars.mainMod`.

| Keys | Does | File | Why this key / notes |
|---|---|---|---|
| SUPER+RETURN | Default terminal | `binds/apps.lua` | |
| SUPER+E | Default file manager | `binds/apps.lua` | |
| SUPER+B | Default browser | `binds/apps.lua` | Browser is preloaded at login |
| SUPER+M | Log out | `binds/apps.lua` | See [apps.lua](#bindsappslua) |
| SUPER+P | App launcher | `binds/apps.lua` | fuzzel, as it comes; a second press closes it |
| SUPER+C | Clipboard history | `binds/apps.lua` | cliphist in fuzzel; C for copy |
| SUPER+COMMA | Settings window | `binds/apps.lua` | Where GNOME and macOS keep settings |
| SUPER+ALT+W | Island wallpaper gallery | `binds/apps.lua` | W for wallpaper; ALT because SUPER+W closes |
| SUPER+V | Dictation start/stop | `binds/apps.lua` | V for voice. Only with the `dictation` feature |
| SUPER+ALT+SPACE | Hide/show the island | `binds/apps.lua` | |
| SUPER+W | Close window | `binds/window.lua` | |
| SUPER+SHIFT+W | Kill window (`hyprctl kill`) | `binds/window.lua` | For one that doesn't answer |
| SUPER+T | Float toggle | `binds/window.lua` | |
| SUPER+H/J/K/L | Move focus | `binds/window.lua` | |
| SUPER+SHIFT+H/J/K/L | Move window, flipping the split if needed | `binds/window.lua` | See [window.lua](#bindswindowlua) |
| SUPER+F | Floating zoom toggle | `binds/alt-fullscreen.lua` | |
| SUPER+SHIFT+F | Zen toggle | `binds/zen.lua` | |
| SUPER+R | Rotate the focused monitor | `binds/monitor.lua` | |
| SUPER+1..0 | Go to workspace 1..10 | `binds/workspaces.lua` | 0 is workspace 10 |
| SUPER+SHIFT+1..0 | Move window to workspace | `binds/workspaces.lua` | |
| SUPER+TAB, SUPER+scroll | Next/previous existing workspace | `binds/workspaces.lua` | |
| SUPER+S / SUPER+SHIFT+S | Scratchpad (`special:magic`) / move window to it | `binds/workspaces.lua` | |
| SUPER+SHIFT+R | `hyprctl reload` | `binds/workspaces.lua` | |
| SUPER+left drag / right drag | Move / resize window | `binds/mouse.lua` | |
| Print / SHIFT+Print | Screenshot a region / the focused screen | `binds/media.lua` | |
| Volume, mute, mic mute | wpctl | `binds/media.lua` | |
| Brightness keys | brightnessctl, ramped | `binds/media.lua` | |
| Play, pause, next, previous | playerctl | `binds/media.lua` | |
| XF86RFKill | Wifi on/off (nmcli) | `binds/media.lua` | |
| Caps Lock | Tells the island it toggled (key still works) | `binds/media.lua` | |

SUPER+Q is free.

## hyprland.lua

Requires each module for its side effects, then `local.lua` if
`package.searchpath` finds it (see [Machine-local files](#machine-local-files)).

## modules/env.lua

Grouped as cursor size, toolkit backends, XDG session names, Qt.

- **`QT_QPA_PLATFORMTHEME = "qt5ct"`**. qt5ct is the Qt5 tool and isn't
  installed. Qt6 apps that need icon lookups override it per process; see
  `QT_QPA_PLATFORMTHEME=gtk3` in [autostart](#modulesautostartlua). It isn't changed here
  on purpose: `gtk3` session-wide would also move every Qt app onto GTK file
  dialogs instead of the portal.
- **`PATH`**. Hyprland hands `sh -c` the environment it was started in, and
  `~/.local/bin` is exported from `.zshrc`, which only interactive shells
  read. Without this, a bind that calls `relay` or `rack` fails with
  "command not found", and a bind's stderr goes nowhere you see. It is
  guarded with `string.find` because this file runs again on every
  `hyprctl reload` and `os.getenv` sees the `PATH` the previous run already
  extended: unguarded, it grows by one copy per reload.
- **`XDG_DATA_DIRS`** adds both flatpak export dirs and `~/.local/share`,
  so flatpak apps show up in launchers.

## modules/monitors.lua

The defaults for a machine with no `local.lua`.

- **`eDP-1`, `mode = "preferred"`**: the panel's own best mode rather than
  one laptop's numbers, so the same line suits any built-in screen.
- **`output = ""`**: the fallback, so an unknown or replugged display still
  comes up.

## modules/input.lua

Defaults; `local.lua` overrides the keyboard layout, sensitivity and
touchpad. `sensitivity` runs -1.0 to 1.0, and 0 means unchanged. Per-device
settings (`hl.device`, names from `hyprctl devices`) belong in `local.lua`,
which the settings window writes.

## modules/decorations.lua

- **`blur.enabled = false`**. Compositor-wide. While it is off, no layer rule
  can blur anything (see `blur-bar` in [windowrules](#moduleswindowruleslua)).
  When it is on, normal windows such as the terminal get blur behind their
  own transparency with no rule needed.
- **Curves and animations** are Hyprland's stock set
  (https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/), plus:
- **`specialWorkspaceIn` / `specialWorkspaceOut`**: the scratchpad rises from
  the bottom edge and drops back down. `slidevert bottom/top` names the edge
  it comes in from; on the way out it leaves by the opposite edge, which is
  why Out says `top`.

## modules/colors.lua

Border colours as fixed values: the active border a gradient, the inactive
one a single colour. They are the palette matugen last made from the
wallpaper, frozen on 2026-10-13 when the old bar (which ran matugen and
kept them in step with the wallpaper) was removed. Edit them freely.

## modules/layout.lua

`dwindle.preserve_split = true` keeps a split's direction when windows
around it change. Wiki pages: Layouts/Master-Layout, Layouts/Scrolling-Layout.

## modules/misc.lua

`force_default_wallpaper = 0` and `disable_hyprland_logo = true` turn off
Hyprland's own wallpapers and logo; awww draws the wallpaper.

## modules/autostart.lua

Runs once, on `hyprland.start`.

- **`qs -n -c dynamic-island`**: the shell at login (brief in
  `quickshell/dynamic-island/AGENTS.md`). `-n` refuses a second copy.
  From 2026-10-13 the brief-built `quickshell/island` replaced it for a
  few hours; the user found it worse and the dynamic-island came back,
  with that island's privacy dots. The island still runs by hand:
  `env QT_QPA_PLATFORMTHEME=gtk3 qs -n -c island -d` (it then takes
  notifications over from dunst while it runs). The dynamic-island also
  holds the settings window (SUPER+COMMA) and runs the login jobs:
  reverting an unconfirmed display trial, writing back a forgotten charge
  limit, restoring the night light. (On 2026-10-13 the window was split
  out as `quickshell/settings` for a day, then removed as a duplicate.)
- Notifications need no shell (dunst, started by D-Bus), and neither do
  Print or the media keys ([media.lua](#bindsmedialua)). Other configs
  under `quickshell/` are run by hand with `qs -c <name>` until they earn
  a line here.
- **`env QT_QPA_PLATFORMTHEME=gtk3`** for Quickshell configs that look up
  icons (`quickshell/island`, run by hand). Under the session's
  `qt5ct`, Qt6 fails to load the theme plugin, falls back to the generic
  Unix theme and never learns an icon theme name. Then `hasThemeIcon(name)`
  is false and `iconPath(name, true)` is `""` for *every* name, installed or
  not (measured with `foot` and `org.gnome.Nautilus`). `gtk3` reads
  `gtk-icon-theme-name` from `~/.config/gtk-3.0/settings.ini` and fixes
  both. It does not affect the `image://icon` provider, which
  works under either value, so it never explains an icon drawn as a broken
  placeholder; that is a malformed source URL.
- **`hypridle`**: config in `hypridle.conf`.
- **`hyprpolkitagent`**: the password dialog for apps that ask for rights
  over D-Bus (Impression writing a USB stick, a disk tool formatting a
  drive). Without it they fail with `NotAuthorizedCanObtain`. The shell's own
  admin actions don't use it (`services/PrivilegedExec.qml` runs `sudo -S`
  with its own window). It is a systemd user unit, and gets this session's
  `WAYLAND_DISPLAY` because Hyprland exports it.
- **`hyprsunset`**: blue-light filter, driven live with
  `hyprctl hyprsunset ...` (the settings window's night light).
- **No `color-scheme` is set here.** GTK4/libadwaita picks light or dark from
  that setting alone; the old bar set it to match its palette, and the
  value it last set stays in gsettings.
- **`voxtype.service`**, only with the `dictation` feature. `voxtype setup
  systemd` installs the unit as `WantedBy=graphical-session.target`, and
  nothing activates that target here (ly starts Hyprland, not uwsm), so the
  enabled unit never started after a reboot. The feature check stops
  `rack features off dictation` from being undone at the next login.
- **Browser preload** (`defaults.preloadArgv()`): the default browser with no
  window, so SUPER+B only has to open one. Measured on the T480s in
  power-saver: a cold Brave window ~2.8s, first window from a preloaded Brave
  ~1.5s, later ones ~0.9s. Costs a few hundred MB of RAM. Only browsers that
  support it (see [defaults.lua](#modulesdefaultslua)).

## modules/windowrules.lua

By rule `name`:

- **`suppress-maximize-events`**: ignores every app's maximize requests. It
  is kept in the local `suppressMaximizeRule` so it can be switched off with
  `suppressMaximizeRule:set_enabled(false)`.
- **`fix-xwayland-drags`**: fixes dragging with XWayland (stock rule).
- **`move-hyprland-run`**: floats the `hyprland-run` prompt near the bottom left.
- **`float-island-settings`**: the settings window
  (`quickshell/dynamic-island/SettingsWindow.qml`) opens floating and
  centred at the 880x600 it asks for. Every Quickshell window has the class
  `org.quickshell`, so the title (`Settings`) tells it apart.
- **`center-floating-dialogs`**: centres XWayland dialogs. Wayland clients
  can't ask for a position, so Hyprland already centres their floating
  windows; X11 clients can, and plenty ask for [0,0], under the bar. All
  three match keys are needed:
  - `float`: only windows already floating when map-time rules run. A window
    floated later with SUPER+T never matches, and doesn't need to: it keeps
    its tiled position, already clear of the bar.
  - `xwayland`: Wayland floats are already placed right.
  - `modal`: keeps menus and tooltips out. They are override-redirect
    surfaces that match `float` + `xwayland` and place themselves on
    purpose; without `modal` every dropdown is dragged to the middle (tested
    with a probe at +300+800). They don't set the modal hint.

  `center` respects the reserved area (a 300x225 dialog lands at [810,445],
  not [810,427]). A popup that still lands wrong is probably not modal: find
  it with `hyprctl clients` and add a rule for its class.
- **`float-calculator`**: GNOME Calculator (flatpak), floating at the
  smallest size it allows. `"1 1"` is less than the app takes, and Hyprland
  raises it to the app's own minimum rather than ignoring it, so this
  follows the app if that minimum changes ("200 200" and "1 1" both gave
  360x616; "700 800" gave 700x800).

## modules/features.lua

Since 2026-10-13 rack is gone from the dotfiles, so nothing writes
`~/.config/rack/features.conf` any more: without it every feature counts
as on, and one written earlier still counts. What follows is how it worked.
Which optional features this machine has on. `rack features`
(`rack/lib/features.sh`) writes `~/.config/rack/features.conf`, one
`name on|off` per line, then reloads Hyprland, so binds that belong to a
feature appear and disappear with it.

- A feature with no line, or no file at all, is **on**, so a machine that
  never ran the picker keeps every bind.
- `M.on` reads the file on every call rather than caching it, so nothing
  stale can outlive the file. It is a few lines, read a few times per load.

## modules/vars.lua

`mainMod`, and the four app roles (`terminal`, `editor`, `fileManager`,
`browser`) as `defaults.lua` resolves them at config load. The app binds
don't use these: they ask `defaults.lua` again on each press, so an
uninstalled default hands over without a reload.

## modules/defaults.lua

Which app does each role (terminal, editor, browser, file-manager). It is the
only place that knows the candidates, their order and how each is launched.
Terms: "Default apps" in `quickshell/CONTEXT.md`. Why it is Lua and lives
here: `docs/adr/0001-default-apps-owned-by-lua.md`.

relay left the dotfiles with rack on 2026-10-13: the binds still read this
file, and the defaults it stored in `$XDG_STATE_HOME/rack/defaults/` still
hold, but nothing sets them from a command any more. What follows describes
how it worked.

Two callers only: Hyprland (through `vars.lua` and `binds/apps.lua`), and
`relay default`, which runs this file as a script. The shell, the Conf menu
and everything else go through relay, so there is one interface to test.

**Resolving a role**, most deliberate first:

1. What the user set, in `$XDG_STATE_HOME/rack/defaults/<role>`: a
   candidate's name, or anything else, which is a custom command and runs as
   written. A set candidate is used whether or not it is installed.
2. The first candidate this machine has installed, so a fresh checkout opens
   the terminal it actually has.
3. The first candidate anyway, so a bind always names something and
   `relay default list` can show it as not installed.

It is state, not config, so picking a terminal doesn't dirty a tracked file,
and `relay default unset` (deleting the state file) brings back step 2.

**`ROLES`, the candidate tables.** The order is step 2's order.
- `name`: what a set default stores and `relay default set` takes.
- `desktop`: a list, since the id isn't always guessable; the first that
  exists wins.
- `wrap = false`: a command, not an app, so no `uwsm-app` in front (terminal
  editors).
- `handler`: how the XDG side is told, written by `relay/lib/default.sh`.
  It is the terminal list `xdg-terminal-exec` reads, a MIME default, or
  `xdg-settings` `default-web-browser`, which sets http, https and text/html
  together.
- **terminal**: kitty leads because a stock Hyprland install brings it, so on
  an unconfigured machine SUPER+RETURN opens what's there. `terminal` says
  how each takes a command and an app-id, and getting it wrong breaks
  things: kitty rejects `-e` ("Unknown flag") and takes the program as
  trailing arguments; ghostty and alacritty take the app-id as `--class`,
  foot and kitty as `--app-id`.
- **editor**: `text/plain` only. `nvim.desktop` has `Terminal=true`, so a
  terminal editor is a valid handler.
- **browser**: `appMode` means it takes `--app=<url>` (chromium family only),
  opening a page as its own window. `preload` means it takes
  `--no-startup-window`, starting with no window and staying alive after the
  last one closes (chromium only; firefox quits). `--password-store=basic`
  keeps brave off a keyring nothing in this session unlocks.
- **file-manager**: no flatpaks, since a sandboxed file manager is a poor one.

**Is it installed?** (`present`, `whereOnPath`, `exported`, `installedVia`).
It walks directories instead of spawning `command -v` or `flatpak info`: this
runs on every config load, and a process per candidate would be a dozen.
Opening the file is a fair test for both a packaged binary and a flatpak
export, which is a symlink to one. Flatpaks are checked in both
installations, not through `PATH`: the per-user export dir usually isn't on
`PATH`. `installedVia` tries the native binary before the flatpak (faster
start), per candidate, so how an app is installed never outranks the
ranking. `FLATPAK_SYSTEM_DIR` / `FLATPAK_USER_DIR` are flatpak's own
variables, honoured so tests can point at a fake installation.

**Launching.**
- `UWSM`: `uwsm-app` puts each app in its own systemd scope. Left out when
  uwsm isn't installed, so the bind works instead of failing silently.
- `argvFor`: a candidate that isn't installed is spelled as its binary; a
  command that fails is better than an empty bind.
- `desktopFor`: the `.desktop` id the handler is set to. A flatpak's is its
  ref; a native one's is the first of its ids found in an applications dir;
  nil leaves the handler alone.
- `local unpack = table.unpack or unpack`: `table.unpack` is Lua 5.2+, and
  LuaJIT has only the global.
- `M.terminalArgv(command, appId, title)`: opens the terminal, optionally
  running a command, with app-id and title if given. A custom terminal gets
  none of those flags, only `-e`, which most terminals take.
- `customArgv`: `sh -c` splits the custom command and `"$@"` keeps each extra
  word whole.
- `M.webAppArgv(url)`: an app window when the browser has `appMode`, else
  `xdg-open`.
- `M.preloadArgv()`: nil when the browser can't preload. Later launches hand
  their window to this process, so it must use the browser's own argv,
  flags included: the first process's `--password-store` applies to every
  window.

**`M.describe(role, stored)`.** `stored` means "what if the user had set
this": nil reads the state file, false means nothing set, a string is what
the file would hold. That lets `relay default set` report and write the
handler before writing the file, dry run or not. Returns nil for an unknown
role, else `role`, `resolvedBy` (`set` | `missing` | `custom` | `fallback`),
`command`, and unless custom: `name`, `label`, `installed`, `via`, `desktop`,
`argv`, `app`. **`missing`** is a set candidate that has since been
uninstalled: the first installed candidate stands in, `wanted` /
`wantedLabel` name the one that was set, and the choice is kept, so
reinstalling brings it back. With nothing installed at all, the set
candidate is named anyway, as `set`.

**Script mode** (bottom of the file). `relay/lib/default.sh` runs
`lua defaults.lua <verb> ...`. This is a private protocol; the user-facing
words are relay's.

```
describe <role> [--stored <value> | --unset]   key<TAB>value lines
list [--json]                                   every role
candidates <role>                               one role's candidates
argv <role>                                     NUL-separated argv
argv terminal <app-id> <title> [command]
argv webapp <url>
```

An unknown role or verb exits 2 with a message on stderr. In `public`,
`path` is the binary's path so pacman can name its package (the app manager
marks that row), and `flatpak` is the ref. The file runs as a script only
when it *is* the script (`debug.getinfo(1).source == "@" .. arg[0]`);
required by Hyprland or dofile'd, it is just the module. Hyprland's Lua may
have neither `arg` nor `debug`, which also means "not a script".

## binds/apps.lua

- `global` binds press a shortcut a Quickshell config registered over
  Hyprland's global-shortcuts protocol, instead of spawning
  `qs ipc call` per press. The string is `appid:name` and must match the
  registration exactly; a name nobody registered does nothing, silently.
  Registered in `dynamic-island/`: `SettingsWindow.qml`
  (`island-settings`), `Controls.qml` and `Wallpapers.qml`.
- **`run(role)`** asks `defaults.lua` on every press, not at config load,
  so a default uninstalled from the app manager hands over to the next
  installed candidate at once. It costs a few file opens, no process.
- **SUPER+M** runs `hyprshutdown` (leaves the session the way the power menu
  does) and falls back to Hyprland's own exit when it isn't installed. Not
  `uwsm stop`: that only ends a session uwsm started, and ly starts this
  one. Same line as Hyprland's default config.
- **SUPER+COMMA**: opens the dynamic island's settings window,
  focuses it, or closes it if it already has focus.
- **SUPER+ALT+W**: images in `~/Pictures/Wallpapers`; ← and → to move, Enter
  sets one on every screen.
- **SUPER+V**: press to record, press again to stop; voxtype types the text
  into the focused window through wtype. The dynamic island shows its
  dictation face while it records.
- **SUPER+ALT+SPACE** presses the dynamic island's `island-toggle`.

## binds/window.lua

**SUPER+SHIFT+H/J/K/L (`moveOrStack`)** move the window, and flip the split
when the pair isn't arranged along the axis asked for. dwindle splits a new
pair along the wider axis, so on 16:9 two windows sit side by side and J/K
did nothing until a third window came. Now SUPER+SHIFT+J puts the window
under its neighbour and K over it; H and L take a stacked pair back to side
by side.

Each key only ever moves the window towards its own direction. That is why
`splitAlong` is checked instead of just trying the move: dwindle answers a
move off the far end of a split by undoing the split, so an unguarded J at
the bottom of a stack would unstack it, and the key would flip between two
layouts. In order:

1. Floating: plain move (it nudges the window; there is no split).
2. A neighbour that way: plain move.
3. Alone on the workspace: plain move, since another monitor may take it
   (asking for `togglesplit` here only makes Hyprland warn).
4. Already split along this axis with nothing that way: at the far end, do
   nothing.
5. Otherwise `togglesplit`, then re-read the window (the flip moved
   everything) and move if a neighbour is now that way. `togglesplit` keeps
   the pair's order.

## binds/workspaces.lua

`key = i % 10`, so workspace 10 is on 0. The scratchpad is `special:magic`;
its slide animation is in `decorations.lua`.

## binds/monitor.lua

**SUPER+R** turns the focused monitor a quarter turn, back to upright after
four. Transforms 0–3 are 0°, 90°, 180°, 270°; 4–7 are the flipped versions,
which nothing here sets, and landing on one sends the next press to upright.
`hl.monitor` with only `output` and `transform` is a patch, so mode,
position and scale are left as they were.

## binds/alt-fullscreen.lua

**SUPER+F** floats the window at 92% (`ZOOM`) of the monitor and centres it;
again, it goes back to tiled. Unlike fullscreen it keeps the border and
stays above other floating windows. `usable_area` divides by `scale`
(geometry is in physical pixels, layout in logical) and subtracts
`reserved` (bars), so the window doesn't slide under them.

## binds/zen.lua

**SUPER+SHIFT+F** sets gaps and border width to 0 and both border colours
to transparent (so a rule that forces its own border width still draws
nothing), and puts every value back on the next press. The old values are
read from the live config (`capture`), not hard-coded, because the border
colours can be edited. `saved` is nil while chrome shows.

- **`config.reloaded`** clears `saved`. A reload re-reads `decorations.lua`
  and brings the chrome back; without it the next press would "restore"
  values that are already live.
- Returns `{ toggle = toggle }`, so it can run from outside a key:
  `hyprctl eval 'require("modules.binds.zen").toggle()'`.

## binds/media.lua

- **Print / SHIFT+Print**: Hyprland runs grim, slurp and wl-copy itself, so
  it works under any shell or none. Each capture is saved in
  `~/Pictures/Screenshots`, copied to the clipboard, and announced by a
  regular notification with the capture as its thumbnail (dunst; low
  urgency, 3 s, as for anything finished that needs nothing more, see
  `quickshell/dynamic-island/AGENTS.md`, Notifications). Cancelling slurp
  (Esc) exits before grim runs; pressing Print while a selection is open
  cancels it instead of opening a second one. Not `repeating`, or holding
  the key would take a capture per repeat.
- **Volume**: wpctl, capped at 100% (`-l 1.0`). Each press also triggers the
  island's volume display (`quickshell:island-osd-volume`), so it shows even
  at 0% or 100%, where wpctl changes nothing and the island would hear
  nothing.
- **Brightness**: one 10% step on press, then a timer steps 2% every 35 ms
  until release. A `repeating` bind starts a new brightnessctl on every
  key-repeat tick with no back-pressure, and the process spawn and sysfs
  round trip can't keep up with a fast repeat: big steps feel steppy, small
  ones drop or queue ticks. The timer gives an even fade, independent of
  `repeat_rate`/`repeat_delay`. Every step also triggers the island's
  brightness display, as volume does.
- **Media keys**: playerctl, so they work under any shell. playerctld
  (started on demand over D-Bus) puts the most recently used player first,
  which is the one these control.
- **Caps Lock**: two `non_consuming` binds, so the key still reaches XKB
  and toggles as usual: `Caps_Lock` and `CAPS + Caps_Lock`, since Caps
  Lock being on counts as the CAPS modifier held and a bind without it
  doesn't match then. Either triggers `quickshell:island-capslock`; the
  island reads the new state from `hyprctl devices` a moment later and
  flashes "Caps Lock – on/off". Hyprland has no event for it.

## hypridle.conf

- Dispatches go through Lua (`hl.dsp.dpms({ action = ... })`), and `action`
  must be given: a dpms dispatch without one toggles.
- **`$lock_after`, `$screen_off_after`, `$suspend_after`**: seconds; empty
  means never. These are the defaults. The settings window (Power) writes
  this machine's own in `hypridle.local.conf` and restarts hypridle. On a
  machine without that file, hypridle logs one "no match" for the `source`
  line and keeps these.
- `# hyprlang noerror` / `# hyprlang if` / `# hyprlang endif` are hyprlang
  directives, not comments. Each listener only exists when its variable is
  non-empty.

## hyprlock.conf

The wallpaper, a Swedish date, a large HH:MM, a short rule and an underline-only
password field. hyprlock stays the real lock, with PAM and fingerprint.

- **`auth.fingerprint`**: fingerprint and password both unlock, whichever
  comes first. It uses fprintd's D-Bus API, not PAM, so nothing in
  `/etc/pam.d`. Without fprintd, hyprlock logs that it couldn't connect and
  the password works as usual.
- **`$qs_*` colours**: `hyprlock-colors.conf` beside this file, sourced
  right after: the old bar's last palette, frozen on 2026-10-13.
- **`background`**: a fixed wallpaper (the one on screen on 2026-10-13),
  blurred and dimmed; the old bar kept a link to the current wallpaper,
  which went with it. `color` shows if the file is missing. `brightness = 0.45`
  is what the brightest wallpapers need for the text to stay readable.
  Blur and brightness are one shader, so `blur_passes` must stay above 0 or
  the dimming stops too.
- **Date label**: the shell's own Swedish day and month names (as in
  `bar/Clock.qml`), so no `sv_SE` locale is needed.
- **`$FPRINTPROMPT` label**: empty until the reader is listening, so nothing
  shows on a machine without one.
- **Password row**: the field and the → arrow are centred as a pair.

## Loose ends

Found while moving the comments here; nothing was changed for these.

- No bind reads `vars.lua`'s `terminal`, `editor`, `fileManager` or
  `browser` (they ask `defaults.lua` directly); only
  `relay/tests/relay-default.test.sh` checks them against `relay default get`.
- A TODO to float the Quickshell launcher was dropped: the launcher is now
  its own config (SUPER+P). If it ever tiles, find its class with
  `hyprctl clients` and add a rule.

## History

Kept from the old comments; the commits have the details.

- 2026-09-21: the dashboard (SUPER+Q) and its blur rule were removed; its
  two toggles went to the network rail, then on 2026-09-29 to
  Conf › Triggers › Toggles.
- 2026-09-24: `missing` added to `defaults.lua`. Before, a set default that
  was uninstalled kept being named, and its key and every terminal the
  shell opened failed until another was set. Same day: dictation was found
  to stop working after the first reboot (the voxtype unit note above).
- 2026-09-27: the polkit agent added after apps failed with
  `NotAuthorizedCanObtain`. hyprlock took the shell's lock screen look.
- 2026-09-29: hyprlock's ground became the blurred wallpaper (was plain
  `$qs_bar`); the date lost its faked small caps (JetBrains Mono has none)
  and the prompts their italics; the account name left the password row and
  the field and arrow moved 22px left. hyprlock 0.9 dropped
  `disable_loading_bar`, `grace` and `no_fade_in`; grace is now the
  `--grace` flag, which nothing passes.
- 2026-10-13: the Quickshell clipboard window went too, at the user's
  request: SUPER+C shows cliphist's history in fuzzel
  (`cliphist list | fuzzel --dmenu | cliphist decode | wl-copy`).
- 2026-10-13: the old bar (`quickshell/main`) was removed, at the user's
  request, with matugen and the bar's window rules and binds; its last
  colours were frozen into each app's config.
- 2026-10-13: fuzzel replaced the Quickshell launcher on SUPER+P, at the
  user's request ("I don't need Quickshell to do everything"); the
  launcher config was removed.
- 2026-10-09: the launcher and the clipboard became their own Quickshell
  configs, so they work without main's bar.
- 2026-10-10: the dynamic island replaced main at login. Print and the media
  keys moved off main's services (screenshot service, MPRIS client) to
  grim/slurp and playerctl, since they went dead with main.
- `center-floating-dialogs` replaced `float-below-bar`
  (`match = { float = true }`, `move = "window_x 27"`, half size). It was
  meant for SUPER+T windows, which it could never match; it hit the
  XWayland popups instead and pinned them 8px into the 35px bar (27 was a
  stale `Theme.barHeight`) at half size.
- `blur-bar` replaced a `^quickshell:.*` blur rule with `noblur-*`
  exceptions (quicksettings, powermenu, launcher, osd-wallpaper,
  osd-volume, osd-brightness, systemsettings; osd-mic and others were never
  added).
