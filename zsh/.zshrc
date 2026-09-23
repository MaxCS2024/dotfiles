# ╭──────────────────────────────────────────────╮
# │ Aliases                                      │
# ╰──────────────────────────────────────────────╯

alias nv="nvim"

# Files
alias ls="eza --color=always --icons always"
alias ll="eza -lah --color=always --icons always"
alias la="eza -a --color=always --icons always"
alias lt="eza --tree --icons always"

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
# │ Zoxide                                       │
# ╰──────────────────────────────────────────────╯

if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi


# ╭──────────────────────────────────────────────╮
# │ Colors                                       │
# ╰──────────────────────────────────────────────╯

autoload -U colors
colors


# ╭──────────────────────────────────────────────╮
# │ History                                      │
# ╰──────────────────────────────────────────────╯

HISTFILE="$ZDOTDIR/.histfile"
HISTSIZE=10000
SAVEHIST=10000

setopt HIST_IGNORE_SPACE
setopt HIST_IGNORE_DUPS
setopt HIST_REDUCE_BLANKS

setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY


# ╭──────────────────────────────────────────────╮
# │ Completion                                   │
# ╰──────────────────────────────────────────────╯

autoload -Uz compinit
compinit


# ╭──────────────────────────────────────────────╮
# │ Starship prompt                              │
# ╰──────────────────────────────────────────────╯

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi


# ╭──────────────────────────────────────────────╮
# │ Autosuggestions                              │
# ╰──────────────────────────────────────────────╯

source "$ZDOTDIR/zsh-autosuggestions/zsh-autosuggestions.zsh"

# ╭──────────────────────────────────────────────╮
# │ Quality of Life                              │
# ╰──────────────────────────────────────────────╯

# Reload shell configuration
alias reload="source ~/.config/zsh/.zshrc"

# FZF integration
if command -v fzf >/dev/null 2>&1; then
    source <(fzf --zsh)
fi

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
            --preview='bat -p --color=always {}' \
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
