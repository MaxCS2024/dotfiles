#!/usr/bin/env bash
#
# Install rack into ~/.local. Links by default, so editing a module in the
# repo takes effect immediately with no reinstall step.
#
# rack needs rig. It does NOT need relay: relay is only ever invoked as a
# command from the manifest's reload column, so deploy and diff work fine on a
# machine that has no relay at all.
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
for candidate in "${RIG_EXE:-}" "$(command -v rig 2>/dev/null || true)" \
    "$HERE/../rig/rig" "$HOME/.local/bin/rig"; do
    [[ -n $candidate && -f $candidate ]] && {
        RIG_EXE=$(readlink -f -- "$candidate")
        break
    }
done

if [[ -z ${RIG_EXE:-} || ! -f ${RIG_EXE:-} ]]; then
    cat >&2 <<'MSG'
install: rack needs rig, and I cannot find it.

Install rig first:

    cd ../rig && ./install.sh

or point me at it with RIG_EXE=/path/to/rig
MSG
    exit 127
fi

# shellcheck disable=SC1090
source "$RIG_EXE"

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
LIB_DIR="$PREFIX/lib/rack"
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

    # None of these are hard requirements — each module reports its own
    # missing tool when you actually use it — but naming them now saves a
    # confusing failure at 2am from a keybind with no terminal.
    local opt
    for opt in git diff find; do
        rig::check::has "$opt" || rig::log::warn "not installed: $opt"
    done

    # The manifest is the thing rack cannot work without. A fresh checkout
    # that has not been edited yet is fine; a missing one is not.
    if [[ ! -r $HERE/manifest.conf ]]; then
        rig::log::warn "no manifest.conf in $HERE — rack will have nothing to deploy"
    fi

    rig::log::debug "using rig at $RIG_EXE"
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
    local exe="$BIN_DIR/rack"
    [[ -x $exe ]] || {
        rig::log::error "installed, but $exe is not executable"
        return 1
    }
    "$exe" version >/dev/null || {
        rig::log::error "installed, but 'rig version' failed"
        return 1
    }
    "$exe" manifest names >/dev/null
    rig::log::success "rack $("$exe" version | head -1 | awk "{print \$2}") is installed, on rig $RIG_VERSION"
}

# ----------------------------------------------------------------------- go

if ((UNINSTALL)); then
    rig::log::info "removing rack from ${PREFIX/#$HOME/\~}"
    remove "$BIN_DIR/rack"
    remove "$LIB_DIR"
    # The completion file is generated rather than linked, so `ours` cannot
    # recognise it. Its first line is the marker we wrote; anything else at
    # that path is someone else's and stays put.
    if [[ -f $COMP_DIR/rack ]] &&
        [[ $(head -n1 -- "$COMP_DIR/rack") == "# generated by: rack completion bash" ]]; then
        run rm -f -- "$COMP_DIR/rack"
        printf '  removed %s\n' "${COMP_DIR/#$HOME/\~}/rack"
    else
        remove "$COMP_DIR/rack"
    fi
    # Copy-mode installs are not symlinks, so say so rather than guessing.
    [[ -e $BIN_DIR/rack || -e $LIB_DIR ]] &&
        rig::log::warn "some files were copied, not linked — remove them by hand if you want them gone"
    exit 0
fi

preflight || exit $?
rig::log::info "installing into ${PREFIX/#$HOME/\~} (${MODE})"

# A symlink to a non-executable file is a non-executable command, and archives
# and some filesystems drop the bit. Cheaper to fix than to diagnose.
for f in "$HERE/rack" "$HERE/install.sh" "$HERE/tests/run"; do
    [[ -f $f && ! -x $f ]] && run chmod +x -- "$f"
done

place "$HERE/rack" "$BIN_DIR/rack" || exit 1
place "$HERE/lib" "$LIB_DIR" || exit 1

if ((COMPLETION)); then
    # Generated from module metadata, so it can never drift from the code.
    if ((DRY)); then
        printf '  would: write %s\n' "$COMP_DIR/rack"
    else
        mkdir -p -- "$COMP_DIR"
        RACK_LIB_DIR="$HERE/lib" "$HERE/rack" completion bash >"$COMP_DIR/rack" &&
            printf '  %s (generated)\n' "${COMP_DIR/#$HOME/\~}/rack"
    fi
fi

check_path
verify
