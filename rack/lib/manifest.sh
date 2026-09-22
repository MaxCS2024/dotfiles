# manifest — one table saying what goes where, and how to reload it.
#
# This file is the reason rack is worth writing rather than being a pile of
# symlink commands. deploy, diff, validate, edit and reload all read it, so
# adding an application is adding a line.

rig::load log path

RACK_MODULE_SUMMARY[manifest]="the table of app, target and reload command"
RACK_MODULE_ACTIONS[manifest]="show names get check path dotfiles"
RACK_MODULE_STATUS[manifest]="ready"
RACK_MODULE_TIER[manifest]="core"

rack::manifest::path() {
    printf '%s\n' "${RACK_MANIFEST:-$RACK_ROOT/manifest.conf}"
}

# What the manifest's sources are relative to. Defaults to the directory above
# the manifest, because the natural layout is dotfiles/rack/manifest.conf with
# dotfiles/hypr, dotfiles/nvim and friends beside rack.
rack::manifest::dotfiles() {
    if [[ -n ${RACK_DOTFILES:-} ]]; then
        readlink -f -- "$RACK_DOTFILES"
        return 0
    fi
    local dir
    dir=$(rack::manifest::path)
    dir=${dir%/*}
    readlink -f -- "$dir/.."
}

rack::manifest::__expand() {
    local path=$1
    path=${path/#\~\//$HOME/}
    path=${path//\$HOME/$HOME}
    printf '%s' "$path"
}

# Each line: name  target  reload-command (or - for nothing to reload).
# Emits tab-separated name, source, target, reload — the shape every other
# module consumes, so the parsing lives here and nowhere else.
rack::manifest::entries() {
    local file name target reload dotfiles source line
    file=$(rack::manifest::path)

    [[ -r $file ]] || {
        rig::log::error "no manifest at $file"
        return "$RIG_EX_FAIL"
    }
    dotfiles=$(rack::manifest::dotfiles)

    while IFS= read -r line || [[ -n $line ]]; do
        # Whole-line comments only, matching the theme files — a reload
        # command is a shell string and may legitimately contain a #.
        [[ ${line} =~ ^[[:space:]]*# ]] && continue
        [[ -z ${line//[[:space:]]/} ]] && continue

        read -r name target reload <<<"$line"
        [[ -n $name && -n $target ]] || {
            rig::log::warn "manifest: skipping malformed line: $line"
            continue
        }
        [[ ${reload:-} == "-" ]] && reload=""

        source="$dotfiles/$name"
        printf '%s\t%s\t%s\t%s\n' \
            "$name" "$source" "$(rack::manifest::__expand "$target")" "${reload:-}"
    done <"$file"
}

rack::manifest::names() {
    rack::manifest::entries | cut -f1
}

# get <name> — one entry, or nothing and a non-zero status.
rack::manifest::get() {
    local want=${1:-} name rest
    [[ -n $want ]] || {
        rig::log::error "manifest get: no name given"
        return "$RIG_EX_USAGE"
    }
    while IFS=$'\t' read -r name rest; do
        [[ $name == "$want" ]] && {
            printf '%s\t%s\n' "$name" "$rest"
            return 0
        }
    done < <(rack::manifest::entries)
    return "$RIG_EX_FAIL"
}

# Selected entries, or all of them when nothing is named. Every module that
# takes optional names uses this, so they all behave the same way.
rack::manifest::select() {
    local -a wanted=("$@")
    local entry name found

    ((${#wanted[@]})) || {
        rack::manifest::entries
        return 0
    }

    local status=0
    for name in "${wanted[@]}"; do
        found=0
        while IFS= read -r entry; do
            [[ ${entry%%$'\t'*} == "$name" ]] && {
                printf '%s\n' "$entry"
                found=1
            }
        done < <(rack::manifest::entries)
        ((found)) || {
            rig::log::error "not in the manifest: $name"
            status=$RIG_EX_USAGE
        }
    done
    return "$status"
}

rack::manifest::show() {
    local name source target reload
    printf '%-14s %-34s %s\n' "APP" "TARGET" "RELOAD"
    while IFS=$'\t' read -r name source target reload; do
        printf '%-14s %-34s %s\n' "$name" "${target/#$HOME/\~}" "${reload:-—}"
    done < <(rack::manifest::entries)
}

# The one that catches a typo before deploy does something surprising with it.
rack::manifest::check() {
    local name source target reload problems=0
    local -A seen=()

    while IFS=$'\t' read -r name source target reload; do
        if [[ -n ${seen[$name]:-} ]]; then
            rig::log::error "duplicate entry: $name"
            problems=$((problems + 1))
        fi
        seen[$name]=1

        if [[ ! -e $source ]]; then
            rig::log::error "$name: no such source: ${source/#$HOME/\~}"
            problems=$((problems + 1))
        fi
        if [[ $target != /* ]]; then
            rig::log::error "$name: target is not an absolute path: $target"
            problems=$((problems + 1))
        fi
    done < <(rack::manifest::entries)

    if ((problems)); then
        rig::log::error "$problems problem(s) in $(rack::manifest::path)"
        return "$RIG_EX_FAIL"
    fi
    rig::log::success "manifest is fine"
}

rack::manifest::__default() { rack::manifest::show "$@"; }

rack::manifest::__usage() {
    cat <<'EOF'
  rack manifest              the table
  rack manifest check        missing sources, duplicates, relative targets
  rack manifest names        one per line, for scripts
  rack manifest get hypr

format — name, target, and the rest of the line as the reload command
  hypr      ~/.config/hypr      hyprctl reload
  waybar    ~/.config/waybar    pkill -SIGUSR2 waybar
  nvim      ~/.config/nvim      -

Sources are relative to RACK_DOTFILES, which defaults to the directory above
the manifest.
EOF
}
