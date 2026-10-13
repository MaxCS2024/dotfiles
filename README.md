# dotfiles

A Hyprland desktop whose shell is [Quickshell](https://quickshell.org): the
dynamic island at the top centre, with a clipboard window and a settings
window beside it. The app launcher is fuzzel. Configs are linked into place
with [GNU stow](https://www.gnu.org/software/stow/).

```
hypr/         the compositor — .config/hypr/hyprland.lua sources modules/
quickshell/   the shell configs, in .config/quickshell/:
                dynamic-island (the shell at login), clipboard, settings,
                island (a brief-built island, run by hand), main (the old
                bar, run by hand), shared (files clipboard links to)
matugen/      turns a wallpaper into the palette the shell writes out
gtk-3.0/ gtk-4.0/  GTK theming, and the icon theme Qt reads through gtk3
foot/ kitty/ ghostty/  terminals
btop/ starship/ wireplumber/ zsh/ autostart/
nvim/         LazyVim's options, keymaps and plugins; nvim/install.sh
fingerprint/ secureboot/ gpg/  guided setups, each an install.sh
udev/         hardware fixes, one rule per device (see below)
bin/ docs/
```

Each folder above the line `nvim/` is a stow package: inside it, the files sit
where they go under `~` (`hypr/.config/hypr/…` becomes `~/.config/hypr`).
Adding an application is adding a folder laid out the same way.

## On a new machine

```bash
git clone https://github.com/MaxCS2024/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
stow autostart btop foot ghostty gtk-3.0 gtk-4.0 hypr kitty matugen \
     quickshell starship wireplumber zsh
```

`.stowrc` points stow at `~`, so it is always run from the repo. A config
the application wrote on its first launch (Hyprland, ghostty) is in the way:
move it aside first, or let stow take it into the repo with `stow --adopt`
and look at the diff.

btop rewrites its own config whenever you change a setting in its UI, and
that file is a link back into this repo. This keeps your local edits out of
the repo; it lives in `.git/index`, so it is set once per clone:

```bash
git update-index --skip-worktree btop/.config/btop/btop.conf
```

The optional parts are their own scripts, run when you want them, after
their packages:

```bash
# LazyVim, with this repo's options, keymaps and plugins
sudo pacman -S --needed neovim ripgrep fd lazygit && nvim/install.sh
# Oh-My-Zsh
zsh/.config/zsh/install.sh
# The fingerprint reader and sudo's finger (--validity says if the reader
# needs python-validity from the AUR; --remove takes it out of PAM again)
fingerprint/install.sh --prepare && sudo pacman -S --needed fprintd && fingerprint/install.sh
# Secure Boot: sbctl keys and a signed UKI, guided
sudo pacman -S --needed sbctl efibootmgr && secureboot/install.sh
# A GPG signing key
gpg/install.sh
# Dictation (SUPER+V)
sudo pacman -S --needed wtype && yay -S voxtype-bin && voxtype setup --download \
  && voxtype config set hotkey.enabled false && voxtype config set osd.enabled false \
  && voxtype setup systemd
```

The font must be `ttf-jetbrains-mono-nerd`, the patched Nerd Font build: the
island draws glyphs that exist nowhere else.

Then log into Hyprland. `hypr/.config/hypr/modules/autostart.lua` starts the
dynamic island, the clipboard and settings configs, and the wallpaper,
clipboard, idle and night-light daemons.

## Hardware fixes

`udev/` holds one rule per device, copied into `/etc` where it applies (udev
reads only its own folder):

```bash
sudo install -m644 -t /etc/udev/rules.d udev/92-battery-charge-limit.rules
sudo udevadm control --reload
sudo udevadm trigger --action=add --subsystem-match=power_supply
```

Each rule's header says what it is for and which `udevadm trigger` arguments
apply it to a device already plugged in. The settings window's Power section
runs the charge-limit one for you.

## Day to day

Stow links whole folders, so a file added to a config is live at once; a new
config needs `stow <name>`. `stow -D <name>` takes one away again, and
`stow -R <name>` puts its links right after a move.

Quickshell watches its own files and reloads a second or two after a save.
An edit that replaces the file's inode — `sed -i`, most formatters — does not
trip that watch; `touch` a file it still holds to force one. After editing
Hyprland's config, `hyprctl reload`.

## Moving from rack

Until 2026-10-13 a tool of its own, rack (with rig and relay), linked these
configs. On a machine set up that way, the old links point at paths that no
longer exist after a pull. Remove the ones into this repo, then stow:

```bash
cd ~/.dotfiles && git pull
find ~ ~/.config ~/.config/quickshell ~/.config/autostart ~/.local/share/applications \
     ~/.local/bin ~/.local/lib -maxdepth 1 -type l -lname '*.dotfiles/*' ! -exec test -e {} \; -print -delete
stow autostart btop foot ghostty gtk-3.0 gtk-4.0 hypr kitty matugen \
     quickshell starship wireplumber zsh
hyprctl reload
```

The `find` deletes only links that point into `.dotfiles` and lead nowhere.

## Reading further

- `quickshell/.config/quickshell/dynamic-island/AGENTS.md` — the island's design
- `quickshell/.config/quickshell/STYLE.md` — the shell's style guide
- `hypr/.config/hypr/README.md` — the Hyprland config, bind by bind
