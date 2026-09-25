# ╭──────────────────────────────────────────────╮
# │ Oh-My-Zsh                                    │
# ╰──────────────────────────────────────────────╯

# Not in the repo: `rack features on ohmyzsh` (zsh/install.sh) clones it
# from upstream, and zsh-autosuggestions into its custom/plugins.
export ZSH="${XDG_DATA_HOME:-$HOME/.local/share}/oh-my-zsh"

# ZDOTDIR is a link into the repo, and Oh-My-Zsh's default completion dump
# goes there, into the working tree.
ZSH_CACHE_DIR="$XDG_CACHE_HOME/oh-my-zsh"
ZSH_COMPDUMP="$ZSH_CACHE_DIR/.zcompdump-${HOST%%.*}-$ZSH_VERSION"

# It updates itself, without asking, when an update is due.
zstyle ':omz:update' mode auto

# Set before Oh-My-Zsh loads, or it picks ~/.zsh_history.
HISTFILE="$ZDOTDIR/.histfile"

# The prompt is starship, started below.
ZSH_THEME=""

plugins=(
    fzf
    zoxide
    zsh-autosuggestions
)

# On a machine that hasn't installed it yet, say how rather than fail on
# the source line at every start.
if [[ -f $ZSH/oh-my-zsh.sh ]]; then
    source "$ZSH/oh-my-zsh.sh"
else
    print -u2 "Oh-My-Zsh isn't installed: rack features on ohmyzsh (or Conf › Features)"
fi


# ╭──────────────────────────────────────────────╮
# │ Aliases                                      │
# ╰──────────────────────────────────────────────╯

alias nv="nvim"

# Files. Guarded so a machine without eza keeps a working ls.
if command -v eza >/dev/null 2>&1; then
    alias ls="eza --color=always --icons always"
    alias ll="eza -lah --color=always --icons always"
    alias la="eza -a --color=always --icons always"
    alias lt="eza --tree --icons always"
fi

# Navigation
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

alias c="clear"
alias q="exit"

# tmux
alias tls="tmux ls"
alias ta="tmux attach"

# Git
alias gs="git status"
alias ga="git add"
alias gc="git commit"
alias gp="git push"
alias gl="git log --oneline --graph --decorate"
alias gd="git diff"
alias gds="git diff --staged"

# Useful
alias grep="grep --color=auto"
alias df="df -h"
alias du="du -h"

# Compression
alias compress='tar -czvf'
alias decompress='tar -xzvf'


# ╭──────────────────────────────────────────────╮
# │ tmux                                         │
# ╰──────────────────────────────────────────────╯

tat() {
    local session

    session=$(tmux ls -F '#{session_name}' 2>/dev/null \
        | fzf --query="$1" --select-1 --exit-0)

    if [[ -z "$session" ]]; then
        session="${1:-main}"
    fi

    tmux new-session -A -s "$session"
}


# ╭──────────────────────────────────────────────╮
# │ History                                      │
# ╰──────────────────────────────────────────────╯

HISTSIZE=10000
SAVEHIST=10000

setopt HIST_IGNORE_SPACE
setopt HIST_IGNORE_DUPS
setopt HIST_REDUCE_BLANKS

setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY


# ╭──────────────────────────────────────────────╮
# │ Starship prompt                              │
# ╰──────────────────────────────────────────────╯

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi


# ╭──────────────────────────────────────────────╮
# │ Quality of Life                              │
# ╰──────────────────────────────────────────────╯

# Reload shell configuration
alias reload="source ~/.config/zsh/.zshrc"

# Fastfetch
if command -v fastfetch >/dev/null 2>&1; then
    alias ffetch="fastfetch"
fi

# ─────────────────────────────────────────────
# Arch Linux
# ─────────────────────────────────────────────

if command -v pacman >/dev/null 2>&1; then
    alias update="sudo pacman -Syu"
fi

# ─────────────────────────────────────────────
# Useful shortcuts
# ─────────────────────────────────────────────

alias ports="ss -tulpn"
alias myip="curl -s https://ipinfo.io/ip"
alias weather="curl -s 'wttr.in/?format=3'"

# ╭──────────────────────────────────────────────╮
# │ Coloured man pages                           │
# ╰──────────────────────────────────────────────╯

# less draws bold, underline and standout with these instead of plain
# attributes: bold (headings, options) red, underline (arguments) green,
# the search/status line yellow on blue.
export LESS_TERMCAP_mb=$'\e[1;31m'
export LESS_TERMCAP_md=$'\e[1;31m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;33;44m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[4;1;32m'
export LESS_TERMCAP_mr=$'\e[7m'
export LESS_TERMCAP_mh=$'\e[2m'
export LESS_TERMCAP_ZN=$'\e[74m'
export LESS_TERMCAP_ZV=$'\e[75m'
export LESS_TERMCAP_ZO=$'\e[73m'
export LESS_TERMCAP_ZW=$'\e[75m'
export MANPAGER='less'
# groff 1.23+ writes bold and underline as SGR escapes, which less passes
# through untouched, so the colours above never apply. -P -c makes grotty
# fall back to overstrike (x\bx, _\bx), which is what less recolours.
export MANROFFOPT='-P -c'

# ╭──────────────────────────────────────────────╮
# │ Fuzzy directory finder                      │
# ╰──────────────────────────────────────────────╯

fcd() {
    local dir

    dir=$(
        find . \
            -type d \( \
                -name .git \
                -o -name .cache \
                -o -name .local \
                -o -name .var \
            \) -prune -o \
            -type d -print 2>/dev/null |
        fzf
    )

    [[ -n "$dir" ]] && cd "$dir"
}


# ╭──────────────────────────────────────────────╮
# │ Fuzzy file finder                           │
# ╰──────────────────────────────────────────────╯

ff() {
    local file

    file=$(
        find . \
            -type d \( \
                -name .git \
                -o -name .cache \
                -o -name .local \
                -o -name .var \
            \) -prune -o \
            -type f -print 2>/dev/null |
        fzf \
            --style=full \
            --border=rounded \
            --preview='bat -p --color=always {} 2>/dev/null || cat {}' \
            --preview-window=right:55%:wrap \
            --bind='ctrl-p:toggle-preview' \
            --bind='ctrl-u:preview-page-up' \
            --bind='ctrl-d:preview-page-down' \
            --height=100% \
            --info=inline
    )

    [[ -n "$file" ]] && nvim "$file"
}


# opencode
export PATH="$HOME/.opencode/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# repo scripts that are not installed anywhere else (bin/nerdfont-picker).
# rig, relay and rack install themselves into ~/.local/bin, above. Found
# through ZDOTDIR, which is a link into the repo: :A resolves it and :h
# steps up from zsh/, so this holds wherever the repo was cloned.
export PATH="${ZDOTDIR:A:h}/bin:$PATH"

export PATH="$PATH:$HOME/.spicetify"
