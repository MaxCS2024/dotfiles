#!/usr/bin/env bash
# Scaffold a new quickshell config for experimenting with a layout/component
# change without touching the stable "main" config.
#
# Usage: quickshell/new-config.sh <name>
#
# Creates quickshell/<name>/ next to quickshell/main/:
#   - common/, config/, services/ are symlinked to main's copies, so the
#     experiment shares themes, reusable widgets, and backend services
#     (battery, network, mpris, ...) rather than duplicating them. Editing
#     one of those files affects every config that links to it, including
#     main — that's the tradeoff for not duplicating live backend code.
#   - Everything that actually defines layout (shell.qml plus every other
#     top-level directory of main's — see layout_entries below, which is
#     the list) is copied, so it's yours to rewrite freely with zero risk
#     to main. Spelled out there rather than here so there is one copy of
#     it to keep right.
#
# layout_entries below is that list by hand, and `cp` under `set -e` means a
# name in it that main no longer has kills the scaffold outright, while one
# main has gained is quietly missing from the copy — shell.qml imports it,
# the new config won't start, and nothing here says why. Add a new top-level
# directory of main's to it the day you add the directory.
#
# Both halves of that had already happened by 2026-09-21, when the list was
# resynced: it still named quicksettings/ and systemsettings/ (deleted
# 2026-09-21 and 2026-09-13), which was enough to kill the script outright,
# and it had never gained battery/, calendar/, clipboard/, keybinds/,
# network/, packages/ or volume/. dashboard/ came off it the same day.
#
# After scaffolding:
#   cd ~/.dotfiles && stow -R -t ~/.config/quickshell quickshell
#   qs -c <name>          # run it standalone in a terminal to iterate
#
# main's autostart (hypr/modules/autostart.lua) is untouched — nothing here
# runs automatically until you decide to promote it.

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "Usage: $0 <name>" >&2
	exit 1
fi

name="$1"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$here/main"
dst="$here/$name"

if [[ "$name" == "main" ]]; then
	echo "error: 'main' is the stable config, refusing to overwrite it" >&2
	exit 1
fi

if [[ -e "$dst" ]]; then
	echo "error: $dst already exists" >&2
	exit 1
fi

shared_dirs=(common config services)
layout_entries=(shell.qml bar battery calendar clipboard installer keybinds launcher lockscreen menu network notifications osd packages powermenu theme volume wallpaper)

mkdir -p "$dst"

for dir in "${shared_dirs[@]}"; do
	ln -s "../main/$dir" "$dst/$dir"
done

for entry in "${layout_entries[@]}"; do
	cp -r "$src/$entry" "$dst/$entry"
done

echo "Created $dst"
echo "  shared (symlinked to main): ${shared_dirs[*]}"
echo "  yours to edit (copied from main): ${layout_entries[*]}"
echo
echo "Next steps:"
echo "  cd ~/.dotfiles && stow -R -t ~/.config/quickshell quickshell"
echo "  qs -c $name"
