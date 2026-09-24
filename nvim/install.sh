#!/usr/bin/env bash
#
# LazyVim, fresh from upstream, with this repo's tweaks on top.
#
# The starter (github.com/LazyVim/starter) is cloned into ~/.config/nvim and
# stops being a checkout: it is your config from then on, and LazyVim itself
# updates through lazy.nvim, not through this repo. What the repo keeps is
# only what differs from LazyVim — lua/config/options.lua,
# lua/config/keymaps.lua and lua/plugins/ — and those are linked back here,
# so editing one takes effect with no reinstall.
#
# `rack features on lazyvim` runs this (rack/features.json). It is safe to
# run by hand, and again: a config that is already the starter is kept, and
# only the links are put right.

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}/nvim
STARTER=https://github.com/LazyVim/starter

is_starter() {
    grep -qs 'LazyVim/LazyVim' "$CONFIG/lua/config/lazy.lua"
}

# What rack deploy used to link here was this directory itself; a link is
# ours and goes. A real directory is somebody's config and is moved, never
# deleted, to where rack deploy puts what it replaces.
if [[ -L $CONFIG ]]; then
    rm -- "$CONFIG"
elif [[ -e $CONFIG ]] && ! is_starter; then
    backup="$HOME/.local/state/rack/backups/$(date +%Y%m%d-%H%M%S)/.config/nvim"
    mkdir -p -- "${backup%/*}"
    mv -- "$CONFIG" "$backup"
    printf 'moved the old config to %s\n' "$backup"
fi

if ! is_starter; then
    git clone --depth 1 "$STARTER" "$CONFIG"
    rm -rf -- "$CONFIG/.git"
fi

# The starter's own copies are empty placeholders (and lua/plugins/ holds
# one example that returns nothing), so they are replaced outright.
for rel in lua/config/options.lua lua/config/keymaps.lua lua/plugins; do
    [[ $(readlink -- "$CONFIG/$rel" 2>/dev/null) == "$HERE/$rel" ]] && continue
    rm -rf -- "${CONFIG:?}/$rel"
    ln -s -- "$HERE/$rel" "$CONFIG/$rel"
done

# Extras live in lazyvim.json, which LazyVim writes itself (:LazyExtras), so
# it is seeded rather than linked. Version 8 is the format these names are
# in; a later LazyVim migrates it forward on first start.
if [[ ! -f $CONFIG/lazyvim.json ]]; then
    printf '%s\n' '{ "extras": [ "lazyvim.plugins.extras.lang.python" ], "version": 8 }' \
        >"$CONFIG/lazyvim.json"
fi

printf 'LazyVim is in %s; the plugins install the first time nvim starts\n' "$CONFIG"
