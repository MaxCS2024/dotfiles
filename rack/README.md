# rack

The configuration tool. What you run at a terminal, deliberately.

```bash
rack deploy          # make reality match the manifest
rack diff            # has anything drifted from the repo?
rack validate        # would these configs actually load?
```

Sits on [rig](../rig). It does **not** source [relay](../relay) — relay is
invoked as a command from the manifest's reload column, which is a much weaker
coupling, and means deploy and diff work on a machine with no relay at all.

## Install

```bash
cd ../rig && ./install.sh     # rack needs rig
cd ../rack && ./install.sh
```

## The manifest

One table. Everything reads it, so adding an application is adding a line.

```
# name        target                reload command (- for none)
hypr          ~/.config/hypr        hyprctl reload
waybar        ~/.config/waybar      pkill -SIGUSR2 waybar
kitty         ~/.config/kitty       pkill -SIGUSR1 kitty
nvim          ~/.config/nvim        -
```

Sources are relative to `RACK_DOTFILES`, which defaults to the directory above
the manifest — so the natural layout is `dotfiles/rack/manifest.conf` with
`dotfiles/hypr` and friends beside it.

Reload commands live in data rather than code on purpose. Which wallpaper
daemon you run, whether waybar takes SIGUSR2 or a restart, whether kitty
reloads at all — those are facts about your setup, and changing one should be
changing one line.

Comments are whole-line only. `#` is a legitimate value character, as every
hex colour demonstrates.

## Modules

| module     | what it does |
| ---------- | ------------ |
| `manifest` | the table, and `check` for typos in it |
| `deploy`   | link it all into place; `--adopt`, `--force`, `remove` |
| `diff`     | where reality has drifted from the repo |
| `validate` | syntax-check configs before they break a session |
| `reload`   | run the reload commands on their own |
| `edit`     | open the repo copy, validate on exit |
| `features` | pick the optional parts of the desktop; `on`, `off`, `remove` |
| `patches`  | hardware fixes, one udev rule per device; `list`, `install`, `remove` |

Most modules have one obvious verb, so `rack deploy` means `rack deploy run`
and `rack reload hypr` means `rack reload run hypr`.

## Features

Some of the desktop is optional: dictation brings a speech model and a
daemon, the weather module polls a web API, and the earbuds readout keeps a
Bluetooth channel open to a pair of Nothing earbuds. `features.json` says what each
one is made of, which is everything turning it off or removing it has to
touch:

```
provides   binaries that mean it is installed
probe      optional argv that must also exit 0 (for packages with no binary)
packages   repo (pacman) and aur (yay) package names
setup      commands run once, after its packages are installed
units      systemd user units started with it and stopped without it
teardown   commands run before its packages are uninstalled
data       paths under ~ that a remove deletes
```

```bash
rack features                 # the picker: a checklist in the terminal
rack features list            # on/off, installed or not
rack features on dictation    # install what is missing, set it up, start it
rack features off dictation   # stop it; keep it installed
rack features remove dictation   # off, then uninstall and delete its data
```

Off and remove are two steps on purpose: off is instant to undo, remove
shows every package and directory it would delete, with sizes, and asks
first. A package another feature that is still on also lists is kept.

The choices are `~/.config/rack/features.conf`, one `name on|off` per line.
Hyprland reads it for binds (`hypr/modules/features.lua`) and the shell for
everything it draws (`quickshell/main/services/Features.qml`); rack reloads
Hyprland and tells the shell after every change. A feature with no line is
on, so a machine that never ran the picker keeps everything it had.

Adding a feature is an entry in `features.json`, plus a
`features.on("<name>")` around its binds and a `Features.on("<name>")` on
whatever the shell builds for it — a bar module only needs a line in
`bar/Modules.qml`'s `feature` map.

## Colours

rack does not theme anything. The palette is the shell's: the wallpaper, a
preset or a hand-edited palette (see `quickshell/CONTEXT.md`), and the shell
writes it into the terminals itself. A `rack theme` that rendered `{{key}}`
templates from `themes/*.conf` was here until 2026-09-24; no template ever
existed, so it rendered nothing and reloaded everything.

## Safety

`deploy` replaces only symlinks that point into your dotfiles. Anything real
at a target path stops it, and `--force` is you accepting the loss. `--adopt`
does the opposite: moves the existing file into the repo and links it back,
which is the sane first run on a machine that had configuration before it had
a repo. `remove` unlinks only links pointing into the repo and says so when it
leaves something alone.

Everything honours `RIG_DRY_RUN=1`.

## Validation

```bash
rack validate            # everything in the manifest
rack validate known      # what can actually be checked
```

`hypr` asks the running compositor via `hyprctl configerrors`, which means it
is only meaningful *after* a deploy. `nvim` runs headless. `waybar` parses
`config.jsonc` once `//` comments are stripped. Otherwise it falls back to the
file extension: `bash -n`, `luac -p`, `jq empty`.

When nothing knows how to check something it prints **no validator**, which is
not the same as ok. Reporting an unchecked config as passing would make the
whole command worthless.

## Tests

```bash
tests/run            # every suite
tests/run deploy     # just tests/rack-deploy.test.sh
```

`deploy` is covered: each state a target can be in (absent, a stale or
broken link, something real in the way), `--force` and where it keeps what
it moves, the first-launch defaults it moves on its own, `--adopt`, dry run,
`status`, `remove`, and picking entries by name. Every test runs the real
`rack deploy` against a home and a dotfiles tree of its own, made fresh for
it and deleted after, so nothing touches yours.

`diff`, `reload` and `validate` are covered for the entry names they take
(`tests/rack-names.test.sh`): an unknown one stops the command with exit 2,
where it used to be logged and then reported as success. The rest of what
they do, and the other modules, have no tests yet.

`features` is covered (`tests/rack-features.test.sh`) against a registry of
made-up features and stand-ins for pacman, yay, sudo and systemctl, on a PATH
with the real ones taken out: on, off and remove, the package two features
share, a missing yay, dry run, a data path outside `$HOME`, and what the
picker does with its ticks. The checklist's drawing and keys are not.

## Next

`wallpaper` is commented out of the manifest until you pick a daemon — swww,
hyprpaper and swaybg need different reload commands, and guessing is worse
than waiting. Once relay grows a `wallpaper` module, it becomes one line here.
