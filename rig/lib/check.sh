# check — is the thing we are about to use actually here?

rig::load log

RIG_MODULE_SUMMARY[check]="dependency and environment checks"
RIG_MODULE_ACTIONS[check]="has require root tty interactive confirm"
RIG_MODULE_STATUS[check]="ready"
RIG_MODULE_TIER[check]="core"

# Quiet: for branching. `rig::check::has fzf && ...`
rig::check::has() { command -v -- "${1:-}" >/dev/null 2>&1; }

# Which package would provide this command. Needs the file database
# (`pacman -Fy`); silently gives up if it is missing or we are not on Arch.
rig::check::__provider() {
    rig::check::has pacman || return 1
    local hit
    hit=$(pacman -Fq -- "/usr/bin/$1" 2>/dev/null | head -n1) || return 1
    [[ -n $hit ]] && printf '%s\n' "$hit"
}

# Loud: for the top of a script. Names everything missing at once rather than
# one per run, and exits 127 so callers can tell a missing tool from a failure.
rig::check::require() {
    local cmd pkg
    local -a missing=()

    for cmd in "$@"; do
        rig::check::has "$cmd" || missing+=("$cmd")
    done
    ((${#missing[@]})) || return 0

    for cmd in "${missing[@]}"; do
        if pkg=$(rig::check::__provider "$cmd"); then
            rig::log::error "missing: $cmd  (pacman -S ${pkg##*/})"
        else
            rig::log::error "missing: $cmd"
        fi
    done

    [[ $- == *i* ]] && return "${RIG_EX_NODEP:-127}"
    exit "${RIG_EX_NODEP:-127}"
}

rig::check::root() { ((EUID == 0)); }

# Default to stderr: the question is almost always "is anyone watching?",
# not "is stdout a pipe?"
rig::check::tty() { [[ -t ${1:-2} ]]; }

rig::check::interactive() { [[ $- == *i* ]]; }

# confirm <prompt> — true when the action should proceed.
#
# Honours RIG_DRY_RUN and RIG_YES: a dry run never proceeds, RIG_YES always
# does. With neither, and no terminal to ask on, it declines rather than
# hanging on a prompt nobody can answer — which is the behaviour a repair
# running from a keybind or a unit file needs.
rig::check::confirm() {
    ((${RIG_DRY_RUN:-0})) && return 1
    ((${RIG_YES:-0})) && return 0
    rig::check::tty 0 || {
        printf '  skipped (no tty, set RIG_YES=1)\n' >&2
        return 1
    }
    local reply
    read -rp "  ${1:-proceed?} [y/N] " reply
    [[ $reply == [Yy]* ]]
}

rig::check::__usage() {
    cat <<'EOF'
  rig require jq curl        dies 127, naming the package that provides each
  rig has fzf                quiet; status only
  rig check root             true when EUID is 0
  rig check tty [fd]         default fd 2
  rig check confirm "go?"    honours RIG_DRY_RUN and RIG_YES
EOF
}
