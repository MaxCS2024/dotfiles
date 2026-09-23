# dotfiles

A Hyprland desktop whose shell is [Quickshell](https://quickshell.org): bar,
launcher, notifications, lockscreen, and the panels behind them all live in
`quickshell/main`. Everything else here exists to support that.

```
hypr/             the compositor — hyprland.lua sources modules/
quickshell/main/  the shell — shell.qml is the entry point
rig/              shell library: logging, locking, linking, process handling
rack/             the config tool — deploys this repo, checks, themes
relay/            the runtime CLI — what binds and panels call to do things
matugen/          templates that turn a wallpaper into a colour scheme
gtk-3.0/ gtk-4.0/ GTK theming, and the icon theme Qt reads through gtk3
foot/             terminal, and Theme.terminal's default
kitty/ ghostty/   terminals, colours only — the same palette foot gets
bin/ btop/ nvim/ starship/ zsh/ zshenv/
```

`rack/manifest.conf` is the table of what gets deployed where. Adding an
application is adding a line to it.

## On a new machine

You need `git`, `jq` and `flock` (util-linux) before anything else; the rest
gets named for you in step 3.

```bash
git clone --recurse-submodules https://github.com/MaxCS2024/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

./rig/install.sh      # rack and relay both sit on rig, so it goes first
./rack/install.sh
./relay/install.sh

rack setup            # what is missing, grouped by how much it matters
rack deploy           # link every manifest entry into ~/.config

# btop rewrites its own config whenever you change a setting in its UI, and
# that file is deployed as a link back into this repo. This keeps your local
# edits from showing up as repo changes. It lives in .git/index rather than
# in the repo, so it has to be set once per clone.
git update-index --skip-worktree btop/btop.conf
```

All three installers link back into the repo rather than copying, so editing a
file here takes effect with no reinstall step. They put their executables in
`~/.local/bin`; `hypr/modules/env.lua` prepends that to Hyprland's `PATH`, which
is why binds can call `relay` by bare name.

`rack setup` is the dependency list in executable form — it checks everything
`quickshell/main/DEPENDENCIES.md` names and installs nothing. A gap in
**required** means the shell will not work; **optional** means some feature
quietly never runs. The one thing it names rather than probes is the font:
`ttf-jetbrains-mono-nerd`, which must be the patched Nerd Font build, because
the bar draws glyphs that exist nowhere else.

Then log into Hyprland. `hypr/modules/autostart.lua` starts the shell itself
(`qs -c main`) along with the wallpaper, clipboard, idle and night-light
daemons.

## Onto a USB

The repo is the deliverable — copy the whole directory, or clone it onto the
stick. On a machine that will not keep the repo around, every installer takes
`--copy` and puts real files in `~/.local` instead of links back to it:

```bash
./rig/install.sh --copy && ./rack/install.sh --copy && ./relay/install.sh --copy
```

Pass `--dry-run` first to see what any of them would touch, and `--uninstall`
to remove exactly what they added.

## Day to day

```bash
rack diff             # has anything drifted from the repo?
rack validate         # would these configs actually load?
rack deploy hypr      # just one entry
rack theme dark       # render templates, then reload what needs it
rack list             # every module and its status
```

`RIG_DRY_RUN=1` in front of any of these prints what would happen and changes
nothing.

Quickshell watches its own files and reloads a second or two after a save, so
there is no reload command for it in the manifest. An edit that replaces the
file's inode — `sed -i`, most formatters — does not trip that watch; `touch` a
file it still holds to force one.

## Reading further

- `quickshell/main/DEPENDENCIES.md` — every dependency, and what breaks without it
- `rack/README.md` — the manifest format and each module
- `rig/README.md` — the library the tooling is built on
- `quickshell/EXPERIMENTS.md` — running experimental shell configs alongside `main`
