# path — XDG directories, created when first asked for.
#
# Every function takes an optional subpath and prints an absolute path, so
# `mkdir -p` never appears in a calling script again.

RIG_MODULE_SUMMARY[path]="XDG directories, created on demand"
RIG_MODULE_ACTIONS[path]="config cache data state runtime bin lib self"
RIG_MODULE_STATUS[path]="ready"
RIG_MODULE_TIER[path]="core"

rig::path::__under() {
    local base=$1 sub=${2:-}
    local dir="$base${sub:+/$sub}"
    mkdir -p -- "$dir" 2>/dev/null || {
        echo "rig: cannot create $dir" >&2
        return "${RIG_EX_FAIL:-1}"
    }
    printf '%s\n' "$dir"
}

rig::path::config() { rig::path::__under "${XDG_CONFIG_HOME:-$HOME/.config}" "${1:-}"; }
rig::path::cache() { rig::path::__under "${XDG_CACHE_HOME:-$HOME/.cache}" "${1:-}"; }
rig::path::data() { rig::path::__under "${XDG_DATA_HOME:-$HOME/.local/share}" "${1:-}"; }
rig::path::state() { rig::path::__under "${XDG_STATE_HOME:-$HOME/.local/state}" "${1:-}"; }
rig::path::bin() { rig::path::__under "$HOME/.local/bin" "${1:-}"; }
rig::path::lib() { rig::path::__under "$HOME/.local/lib" "${1:-}"; }

# Runtime state dies with the session, which is exactly what locks want. The
# fallback is mode 0700 because /tmp is shared.
rig::path::runtime() {
    local base=${XDG_RUNTIME_DIR:-}
    if [[ -z $base || ! -d $base ]]; then
        base="/tmp/rig-$(id -u)"
        mkdir -p -- "$base" 2>/dev/null && chmod 700 -- "$base" 2>/dev/null
    fi
    rig::path::__under "$base" "${1:-}"
}

# The directory of the script that is running, symlinks resolved — for a script
# that keeps assets beside itself.
rig::path::self() {
    local src=${BASH_SOURCE[-1]:-$0}
    local real
    real=$(readlink -f -- "$src" 2>/dev/null) || real=$src
    printf '%s\n' "${real%/*}"
}

rig::path::__usage() {
    cat <<'EOF'
  rig path cache rig            ~/.cache/rig        (created if absent)
  rig path runtime rig/locks    $XDG_RUNTIME_DIR/rig/locks
  rig path config waybar        ~/.config/waybar
  rig path self                 directory of the running script
EOF
}
