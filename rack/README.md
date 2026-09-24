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

Most modules have one obvious verb, so `rack deploy` means `rack deploy run`
and `rack reload hypr` means `rack reload run hypr`.

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
tests/run            # everything
```

61 tests against a throwaway dotfiles tree rebuilt between files, so no test
can leave the next one deploying into a half-broken home. They cover manifest
parsing, every deploy state, drift detection, template rendering and the
rig handoff.

## Next

`wallpaper` is commented out of the manifest until you pick a daemon — swww,
hyprpaper and swaybg need different reload commands, and guessing is worse
than waiting. Once relay grows a `wallpaper` module, it becomes one line here.
