#!/usr/bin/env bash
#
# oh-my-zsh, fresh from upstream, for the .zshrc in this directory.
#
# oh-my-zsh is cloned into ~/.local/share/oh-my-zsh and updates itself from
# then on (`zstyle ':omz:update' mode auto` in .zshrc), and the one plugin
# it doesn't ship, zsh-autosuggestions, is cloned into its custom/plugins —
# a directory oh-my-zsh's own .gitignore leaves alone, so its updates never
# trip over it. What the repo keeps is only .zshrc, which says which plugins
# to load.
#
# Not upstream's install.sh: that one writes a .zshrc of its own over
# whatever is there, and offers to change the login shell.
#
# `rack features on ohmyzsh` runs this (rack/features.json). It is safe to
# run by hand, and again: what is already cloned is kept.

set -euo pipefail

ZSH=${XDG_DATA_HOME:-$HOME/.local/share}/oh-my-zsh
AUTOSUGGESTIONS=$ZSH/custom/plugins/zsh-autosuggestions

if [[ ! -f $ZSH/oh-my-zsh.sh ]]; then
    # An interrupted clone leaves a directory git won't clone into again.
    rm -rf -- "$ZSH"
    git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$ZSH"
fi

if [[ ! -f $AUTOSUGGESTIONS/zsh-autosuggestions.plugin.zsh ]]; then
    rm -rf -- "$AUTOSUGGESTIONS"
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$AUTOSUGGESTIONS"
fi

printf 'oh-my-zsh is in %s; new shells load it\n' "$ZSH"
