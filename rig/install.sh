#!/usr/bin/env bash
#
# Install rig into ~/.local. Links by default, so editing a module in the repo
# takes effect immediately with no reinstall step.
#
#   ./install.sh                 link from this repo
#   ./install.sh --copy          copy instead (for a machine without the repo)
#   ./install.sh --dry-run       show what would happen
#   ./install.sh --uninstall     remove what we installed, and nothing else

set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Eat our own dog food: if rig cannot be sourced from the repo, the install was
# going to fail anyway, and this way it fails loudly on line three rather than
# halfway through creating symlinks.
RIG_LIB_DIR="$HERE/lib" source "$HERE/rig" || {
    echo "install: cannot source $HERE/rig — is the repo complete?" >&2
    exit 1
}

MODE=link
PREFIX=${PREFIX:-$HOME/.local}
FORCE=0
DRY=0
COMPLETION=1
UNINSTALL=0

usage() {
    cat <<'EOF'
usage: ./install.sh [options]

  --link            symlink from this repo (default)
  --copy            copy files instead
  --prefix DIR      default: $HOME/.local
  --force           replace real files at the target paths
  --uninstall       remove only what points into this repo
  --dry-run         print every action, change nothing
  --no-completion   skip the bash completion file
  -h, --help
EOF
}

while (($#)); do
    case $1 in
        --link) MODE=link ;;
        --copy) MODE=copy ;;
        --prefix)
            PREFIX=${2:?--prefix needs a directory}
            shift
            ;;
        --force) FORCE=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --dry-run) DRY=1 ;;
        --no-completion) COMPLETION=0 ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            rig::log::error "unknown option: $1"
            usage >&2
            exit "$RIG_EX_USAGE"
            ;;
    esac
    shift
done

BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/lib/rig"
COMP_DIR="$PREFIX/share/bash-completion/completions"

run() {
    if ((DRY)); then
        printf '  would: %s\n' "$*"
    else
        "$@"
    fi
}

# ------------------------------------------------------------------ preflight

preflight() {
    rig::check::require flock

    if ! rig::check::has pacman; then
        rig::log::warn "no pacman here — the pkg module's package hints will be quiet"
    fi

    local opt
    for opt in notify-send jq fzf; do
        rig::check::has "$opt" ||
            rig::log::debug "optional: $opt is not installed"
    done

    # A different `rig` already on PATH. The R Installation Manager is the
    # likely one; whichever of the two comes first in PATH wins, silently.
    local found
    found=$(command -v rig 2>/dev/null || true)
    if [[ -n $found && $(readlink -f -- "$found") != "$(readlink -f -- "$HERE/rig")" &&
        $found != "$BIN_DIR/rig" ]]; then
        rig::log::warn "another rig is on your PATH: $found"
        rig::log::warn "whichever directory comes first in PATH will win"
    fi
}

# ----------------------------------------------------------------- placement

# True when the path is a symlink pointing somewhere inside this repo — the
# only thing we are ever allowed to replace or remove without --force.
ours() {
    local path=$1 target
    [[ -L $path ]] || return 1
    target=$(readlink -f -- "$path" 2>/dev/null) || return 1
    [[ $target == "$HERE"/* || $target == "$HERE" ]]
}

place() {
    local src=$1 dst=$2

    if [[ -e $dst || -L $dst ]]; then
        if ours "$dst"; then
            run rm -rf -- "$dst"
        elif ((FORCE)); then
            rig::log::warn "replacing $dst"
            run rm -rf -- "$dst"
        else
            rig::log::error "$dst exists and is not ours — use --force to replace it"
            return 1
        fi
    fi

    run mkdir -p -- "${dst%/*}"
    if [[ $MODE == link ]]; then
        run ln -s -- "$src" "$dst"
    else
        run cp -r -- "$src" "$dst"
    fi
    printf '  %s -> %s\n' "${dst/#$HOME/\~}" "$src"
}

remove() {
    local dst=$1
    if ours "$dst"; then
        run rm -rf -- "$dst"
        printf '  removed %s\n' "${dst/#$HOME/\~}"
    elif [[ -e $dst ]]; then
        rig::log::warn "left alone (not a link into this repo): $dst"
    fi
}

# -------------------------------------------------------------------- checks

check_path() {
    case ":${PATH}:" in
        *":$BIN_DIR:"*) return 0 ;;
    esac
    rig::log::warn "$BIN_DIR is not on your PATH"
    cat <<EOF

  Add this to your shell rc, then open a new shell:

      export PATH="$BIN_DIR:\$PATH"

EOF
}

verify() {
    ((DRY)) && return 0
    local exe="$BIN_DIR/rig"
    [[ -x $exe ]] || {
        rig::log::error "installed, but $exe is not executable"
        return 1
    }
    "$exe" version >/dev/null || {
        rig::log::error "installed, but 'rig version' failed"
        return 1
    }
    "$exe" log debug "install verified" 2>/dev/null
    rig::log::success "rig $("$exe" version | head -1 | cut -d' ' -f2) is installed"
}

# ----------------------------------------------------------------------- go

if ((UNINSTALL)); then
    rig::log::info "removing rig from ${PREFIX/#$HOME/\~}"
    remove "$BIN_DIR/rig"
    remove "$LIB_DIR"
    # The completion file is generated rather than linked, so `ours` cannot
    # recognise it. Its first line is the marker we wrote; anything else at
    # that path is someone else's and stays put.
    if [[ -f $COMP_DIR/rig ]] &&
        [[ $(head -n1 -- "$COMP_DIR/rig") == "# generated by: rig completion bash" ]]; then
        run rm -f -- "$COMP_DIR/rig"
        printf '  removed %s\n' "${COMP_DIR/#$HOME/\~}/rig"
    else
        remove "$COMP_DIR/rig"
    fi
    # Copy-mode installs are not symlinks, so say so rather than guessing.
    [[ -e $BIN_DIR/rig || -e $LIB_DIR ]] &&
        rig::log::warn "some files were copied, not linked — remove them by hand if you want them gone"
    exit 0
fi

preflight || exit $?
rig::log::info "installing into ${PREFIX/#$HOME/\~} (${MODE})"

# A symlink to a non-executable file is a non-executable command, and archives
# and some filesystems drop the bit. Cheaper to fix than to diagnose.
for f in "$HERE/rig" "$HERE/install.sh" "$HERE/tests/run"; do
    [[ -f $f && ! -x $f ]] && run chmod +x -- "$f"
done

place "$HERE/rig" "$BIN_DIR/rig" || exit 1
place "$HERE/lib" "$LIB_DIR" || exit 1

if ((COMPLETION)); then
    # Generated from module metadata, so it can never drift from the code.
    if ((DRY)); then
        printf '  would: write %s\n' "$COMP_DIR/rig"
    else
        mkdir -p -- "$COMP_DIR"
        RIG_LIB_DIR="$HERE/lib" "$HERE/rig" completion bash >"$COMP_DIR/rig" &&
            printf '  %s (generated)\n' "${COMP_DIR/#$HOME/\~}/rig"
    fi
fi

check_path
verify
