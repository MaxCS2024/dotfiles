# features — which of the optional parts of this desktop a machine has.
#
# Some of the desktop is something a person may simply not want: dictation
# brings a speech model and a daemon, the weather module polls a web API.
# rack/features.json says what each of those is made of — the packages, the
# setup it needs, its systemd units, the files it leaves behind — and this
# module turns one on, off, or off and gone:
#
#   on      install what is missing, run its setup, start its units
#   off     stop its units; the shell and the binds stop showing it.
#           Packages and data stay, so turning it back on is instant.
#   remove  off, then uninstall its packages and delete its data
#
# What is on is one small file, features.conf, which the shell
# (quickshell/main/services/Features.qml) and Hyprland
# (hypr/modules/features.lua) both read. A feature with no line in it is on:
# that is what this desktop did before there were features, so a machine that
# has never run the picker keeps everything it had.
#
# `rack features` with a terminal is the picker, which is what a new machine
# runs first (README.md, "On a new machine").

rig::load log check proc

RACK_MODULE_SUMMARY[features]="pick which optional features this desktop has"
RACK_MODULE_ACTIONS[features]="pick list on off remove path"
RACK_MODULE_STATUS[features]="ready"
RACK_MODULE_TIER[features]="general"

rack::features::__registry() {
    printf '%s\n' "${RACK_FEATURES:-$RACK_ROOT/features.json}"
}

rack::features::path() {
    printf '%s\n' "${RACK_FEATURES_STATE:-${XDG_CONFIG_HOME:-$HOME/.config}/rack/features.conf}"
}

rack::features::__require() {
    rig::check::require jq || return "$RIG_EX_NODEP"
    [[ -f $(rack::features::__registry) ]] || {
        rig::log::error "no feature registry at $(rack::features::__registry)"
        return "$RIG_EX_FAIL"
    }
}

rack::features::__names() {
    jq -r '.features | keys_unsorted[]' "$(rack::features::__registry)"
}

rack::features::__known() {
    jq -e --arg n "$1" '.features | has($n)' "$(rack::features::__registry)" >/dev/null || {
        rig::log::error "no feature called '$1' (try: rack features list)"
        return "$RIG_EX_USAGE"
    }
}

# One line per element of a string-array field, e.g. `__list dictation provides`.
rack::features::__list() {
    jq -r --arg n "$1" --arg f "$2" '.features[$n][$f] // [] | .[]' "$(rack::features::__registry)"
}

rack::features::__field() {
    jq -r --arg n "$1" --arg f "$2" '.features[$n][$f] // ""' "$(rack::features::__registry)"
}

# ------------------------------------------------------------------ state

# "on" or "off". No file, or no line for the feature, is on (see the header).
rack::features::__state() {
    local file line
    file=$(rack::features::path)
    [[ -f $file ]] && line=$(awk -v n="$1" '$1 == n { print $2 }' "$file")
    [[ ${line:-on} == off ]] && echo off || echo on
}

rack::features::__set() {
    local name=$1 value=$2 file tmp
    file=$(rack::features::path)
    if [[ $RIG_DRY_RUN != 0 ]]; then
        printf 'would set %s %s in %s\n' "$name" "$value" "$file"
        return 0
    fi
    mkdir -p -- "${file%/*}"
    tmp="$file.tmp.$$"
    {
        printf '# Written by `rack features`. One optional feature per line, on or off;\n'
        printf '# one with no line is on. Read by quickshell and Hyprland.\n'
        [[ -f $file ]] && awk -v n="$name" -v v="$value" '
            /^#/ { next }
            $1 == n { print n " " v; done = 1; next }
            NF { print }
            END { if (!done) print n " " v }' "$file"
        [[ -f $file ]] || printf '%s %s\n' "$name" "$value"
    } >"$tmp" && mv -f -- "$tmp" "$file"
}

# Installed means every binary it provides is on PATH. That is the same probe
# `rack setup` makes, and it is what the shell sees too. A feature whose
# packages bring no binary of their own (earbuds: two Python libraries) also
# names a `probe`, one argv that exits 0 only once they are there.
rack::features::__installed() {
    local bin
    local -a probe
    while read -r bin; do
        [[ -n $bin ]] || continue
        rig::check::has "$bin" || return 1
    done < <(rack::features::__list "$1" provides)
    mapfile -t probe < <(rack::features::__list "$1" probe)
    ((${#probe[@]} == 0)) || "${probe[@]}" >/dev/null 2>&1
}

# The feature that provides this binary, if that feature is off. `rack setup`
# asks, so something removed on purpose is not reported as missing.
rack::features::off_owner() {
    local registry
    registry=$(rack::features::__registry)
    [[ -f $registry ]] && rig::check::has jq || return 1
    local name
    name=$(jq -r --arg b "$1" '.features | to_entries[] | select(.value.provides // [] | index($b)) | .key' "$registry" | head -n1)
    [[ -n $name && $(rack::features::__state "$name") == off ]] || return 1
    printf '%s\n' "$name"
}

# ------------------------------------------------------------------ steps

# Runs each command in a field holding a list of argv arrays (setup, teardown).
rack::features::__run_each() {
    local name=$1 field=$2 cmd
    local -a argv
    while read -r cmd; do
        [[ -n $cmd ]] || continue
        mapfile -t argv < <(jq -r '.[]' <<<"$cmd")
        rig::proc::run "${argv[@]}" || {
            rig::log::error "$name: '${argv[*]}' failed"
            return "$RIG_EX_FAIL"
        }
    done < <(jq -c --arg n "$name" --arg f "$field" '.features[$n][$f] // [] | .[]' "$(rack::features::__registry)")
}

rack::features::__install() {
    local name=$1
    local -a repo aur
    mapfile -t repo < <(jq -r --arg n "$name" '.features[$n].packages.repo // [] | .[]' "$(rack::features::__registry)")
    mapfile -t aur < <(jq -r --arg n "$name" '.features[$n].packages.aur // [] | .[]' "$(rack::features::__registry)")

    if ((${#aur[@]})) && ! rig::check::has yay; then
        rig::log::error "$name needs ${aur[*]} from the AUR, and yay is not installed"
        return "$RIG_EX_NODEP"
    fi
    if ((${#repo[@]})); then
        rig::proc::run sudo pacman -S --needed "${repo[@]}" || return "$RIG_EX_FAIL"
    fi
    if ((${#aur[@]})); then
        rig::proc::run yay -S --needed "${aur[@]}" || return "$RIG_EX_FAIL"
    fi
    rack::features::__run_each "$name" setup
}

rack::features::__units() {
    local name=$1 verb=$2 unit
    while read -r unit; do
        [[ -n $unit ]] || continue
        # A unit a feature's own setup installs (voxtype's) is not there
        # until that has run, and is gone again after a remove.
        systemctl --user cat -- "$unit" >/dev/null 2>&1 || continue
        rig::proc::run systemctl --user "$verb" --now -- "$unit" ||
            rig::log::warn "$name: could not $verb $unit"
    done < <(rack::features::__list "$name" units)
}

# Packages this feature installed that are still on the machine, less any
# another feature that is on also lists.
rack::features::__removable_packages() {
    local name=$1 pkg other keep
    while read -r pkg; do
        [[ -n $pkg ]] || continue
        pacman -Q -- "$pkg" >/dev/null 2>&1 || continue
        keep=0
        while read -r other; do
            [[ $other == "$name" ]] && continue
            [[ $(rack::features::__state "$other") == on ]] || continue
            jq -e --arg n "$other" --arg p "$pkg" \
                '.features[$n].packages | (.repo // []) + (.aur // []) | index($p)' \
                "$(rack::features::__registry)" >/dev/null && keep=1
        done < <(rack::features::__names)
        ((keep)) || printf '%s\n' "$pkg"
    done < <(jq -r --arg n "$name" '.features[$n].packages | (.repo // []) + (.aur // []) | .[]' "$(rack::features::__registry)")
}

# Data paths that exist, with ~ expanded. Anything that is not strictly inside
# $HOME is refused rather than deleted.
rack::features::__data() {
    local p
    while read -r p; do
        [[ -n $p ]] || continue
        p=${p/#\~\//$HOME/}
        [[ $p == "$HOME"/?* && $p != *..* ]] || {
            rig::log::warn "$1: refusing to delete $p (not inside \$HOME)"
            continue
        }
        [[ -e $p ]] && printf '%s\n' "$p"
    done < <(rack::features::__list "$1" data)
}

# Hyprland reads features.conf when its config loads, so a bind that should
# come or go needs a reload. The shell watches the file, but a watch set on a
# path that did not exist yet, or on a file since replaced by the mv in
# __set, never fires — so it is told as well (services/Features.qml).
rack::features::__reload() {
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 0
    if rig::check::has hyprctl; then
        rig::proc::run hyprctl reload >/dev/null || true
    fi
    if rig::check::has qs; then
        rig::proc::run qs -c main ipc call features reload >/dev/null 2>&1 || true
    fi
}

# ------------------------------------------------------------------ verbs

rack::features::on() {
    local name
    rack::features::__require || return
    (($#)) || {
        rig::log::error "usage: rack features on <feature>..."
        return "$RIG_EX_USAGE"
    }
    for name in "$@"; do rack::features::__known "$name" || return; done
    for name in "$@"; do
        if ! rack::features::__installed "$name"; then
            rig::log::info "installing $name"
            rack::features::__install "$name" || return
        fi
        rack::features::__units "$name" enable
        rack::features::__set "$name" on
        rig::log::success "$name is on"
    done
    rack::features::__reload
}

rack::features::off() {
    local name
    rack::features::__require || return
    (($#)) || {
        rig::log::error "usage: rack features off <feature>..."
        return "$RIG_EX_USAGE"
    }
    for name in "$@"; do rack::features::__known "$name" || return; done
    for name in "$@"; do
        rack::features::__set "$name" off
        rack::features::__units "$name" disable
        rig::log::success "$name is off (still installed; 'rack features remove $name' uninstalls it)"
    done
    rack::features::__reload
}

rack::features::remove() {
    local name
    rack::features::__require || return
    (($#)) || {
        rig::log::error "usage: rack features remove <feature>..."
        return "$RIG_EX_USAGE"
    }
    for name in "$@"; do rack::features::__known "$name" || return; done
    rack::features::off "$@" || return
    for name in "$@"; do
        rack::features::__purge "$name" || return
    done
}

# Shows exactly what would go — each package, each directory and its size —
# and asks once. A feature that is off stays off whichever way that goes.
rack::features::__purge() {
    local name=$1 p
    local -a pkgs data
    mapfile -t pkgs < <(rack::features::__removable_packages "$name")
    mapfile -t data < <(rack::features::__data "$name")
    if ((${#pkgs[@]} + ${#data[@]} == 0)); then
        printf '  %s: nothing installed to remove\n' "$name"
        return 0
    fi
    printf '\nRemoving %s would delete:\n' "$name"
    for p in "${pkgs[@]}"; do printf '  package  %s\n' "$p"; done
    for p in "${data[@]}"; do
        printf '  files    %s (%s)\n' "${p/#$HOME/\~}" "$(du -sh -- "$p" 2>/dev/null | cut -f1)"
    done
    if [[ $RIG_DRY_RUN == 0 ]] && ! rig::check::confirm "remove these?"; then
        printf '  %s is off and still installed\n' "$name"
        return 0
    fi
    # Teardown runs while the packages are still there to run it
    # (voxtype uninstalls its own unit).
    rack::features::__run_each "$name" teardown || true
    if ((${#pkgs[@]})); then
        rig::proc::run sudo pacman -Rns -- "${pkgs[@]}" || return "$RIG_EX_FAIL"
    fi
    for p in "${data[@]}"; do rig::proc::run rm -rf -- "$p"; done
    rig::log::success "$name removed"
}

rack::features::list() {
    local name installed
    rack::features::__require || return
    while read -r name; do
        rack::features::__installed "$name" && installed=installed || installed="not installed"
        printf '  %-12s %-4s %-14s %s\n' "$name" "$(rack::features::__state "$name")" "$installed" \
            "$(rack::features::__field "$name" label)"
    done < <(rack::features::__names)
}

# ------------------------------------------------------------------ picker
#
# A checklist in the terminal's alternate screen: ↑/↓ (or k/j) to move,
# space to tick, enter to apply, q to leave without changing anything.
# Plain bash rather than whiptail or gum, because this runs before anything
# else is installed.
#
# On a machine with no features.conf yet, a feature starts ticked if it is
# `recommended` or already installed — enter on a machine that had dictation
# before features existed must not take it away. Every feature gets a line
# when that first run is applied, so the next run starts from what was
# chosen. After that the ticks start at what is on.

rack::features::pick() {
    local first=0 i key rest cursor=0 n saved_traps
    local -a names ticks
    rack::features::__require || return
    rig::check::tty 0 && rig::check::tty 1 || {
        rig::log::error "the picker needs a terminal; use 'rack features on|off|remove <feature>'"
        return "$RIG_EX_USAGE"
    }
    [[ -f $(rack::features::path) ]] || first=1
    mapfile -t names < <(rack::features::__names)
    n=${#names[@]}
    for i in "${!names[@]}"; do
        if ((first)); then
            if [[ $(jq -r --arg n "${names[$i]}" '.features[$n].recommended' "$(rack::features::__registry)") == true ]] ||
                rack::features::__installed "${names[$i]}"; then
                ticks[i]=1
            else
                ticks[i]=0
            fi
        else
            [[ $(rack::features::__state "${names[$i]}") == on ]] && ticks[i]=1 || ticks[i]=0
        fi
    done

    saved_traps=$(trap -p EXIT INT TERM)
    printf '\e[?1049h\e[?25l'
    trap 'printf "\e[?25h\e[?1049l"' EXIT INT TERM

    while true; do
        rack::features::__draw "$cursor" "$first" names ticks
        IFS= read -rsn1 key || key=q
        if [[ $key == $'\e' ]]; then
            IFS= read -rsn2 -t 0.05 rest || rest=
            key+=$rest
        fi
        case $key in
            $'\e[A' | k) cursor=$(((cursor + n - 1) % n)) ;;
            $'\e[B' | j) cursor=$(((cursor + 1) % n)) ;;
            ' ') ticks[cursor]=$((1 - ticks[cursor])) ;;
            '') break ;;
            q | $'\e') cursor=-1 && break ;;
        esac
    done

    printf '\e[?25h\e[?1049l'
    trap - EXIT INT TERM
    eval "$saved_traps"
    ((cursor >= 0)) || {
        printf 'nothing changed\n'
        return 0
    }
    rack::features::__apply "$first" names ticks
}

rack::features::__draw() {
    local cursor=$1 first=$2 i name tag
    local -n _names=$3 _ticks=$4
    printf '\e[H\e[2J'
    printf '\n  \e[1mFeatures\e[0m\n\n'
    if ((first)); then
        printf '  Pick the parts of this desktop you want. You can change this later\n'
        printf '  with \e[1mrack features\e[0m.\n\n'
    fi
    for i in "${!_names[@]}"; do
        name=${_names[$i]}
        rack::features::__installed "$name" && tag=installed || tag=$(rack::features::__field "$name" size)
        [[ -n $tag ]] || tag="not installed"
        if ((i == cursor)); then
            printf '  \e[7m %s %-14s\e[0m  \e[2m%s\e[0m\n' \
                "$( ((_ticks[i])) && echo '[x]' || echo '[ ]')" "$(rack::features::__field "$name" label)" "$tag"
        else
            printf '   %s %-14s  \e[2m%s\e[0m\n' \
                "$( ((_ticks[i])) && echo '[x]' || echo '[ ]')" "$(rack::features::__field "$name" label)" "$tag"
        fi
    done
    printf '\n  %s\n' "$(rack::features::__field "${_names[$cursor]}" summary | fold -s -w 72 | sed '2,$s/^/  /')"
    printf '\n  \e[2m↑/↓ move   space tick   enter apply   q quit\e[0m\n'
}

# Turns ticks into on/off calls. A feature that goes off while installed gets
# the second question — remove it too? — since off alone keeps its packages
# and data for the next time it is ticked.
rack::features::__apply() {
    local first=$1 i name was
    local -n _names=$2 _ticks=$3
    local -a turn_on=() turn_off=()
    for i in "${!_names[@]}"; do
        name=${_names[$i]}
        was=$(rack::features::__state "$name")
        if ((_ticks[i])); then
            if ((first)) || [[ $was == off ]] || ! rack::features::__installed "$name"; then
                turn_on+=("$name")
            fi
        elif ((first)) || [[ $was == on ]]; then
            turn_off+=("$name")
        fi
    done
    if ((${#turn_on[@]} + ${#turn_off[@]} == 0)); then
        printf 'nothing changed\n'
        return 0
    fi
    if ((${#turn_on[@]})); then
        rack::features::on "${turn_on[@]}" || return
    fi
    if ((${#turn_off[@]})); then
        rack::features::off "${turn_off[@]}" || return
    fi
    for name in "${turn_off[@]}"; do
        [[ -n $(rack::features::__removable_packages "$name")$(rack::features::__data "$name") ]] || continue
        printf '\n%s is off but still installed, so ticking it again later is instant.\n' \
            "$(rack::features::__field "$name" label)"
        rack::features::__purge "$name" || return
    done
}

rack::features::__default() {
    case ${1-} in
        '') if rig::check::tty 0 && rig::check::tty 1; then rack::features::pick; else rack::features::list; fi ;;
        *)
            rig::log::error "unknown action '$1' (try: ${RACK_MODULE_ACTIONS[features]})"
            return "$RIG_EX_USAGE"
            ;;
    esac
}

rack::features::__usage() {
    cat <<'EOF'
  rack features               the picker (a checklist; list without a terminal)
  rack features list          every feature: on/off, installed or not
  rack features on <f>...     install what is missing, run its setup, turn it on
  rack features off <f>...    stop showing it and stop its daemon; keep it installed
  rack features remove <f>... off, then uninstall its packages and delete its data
  rack features path          where the on/off choices are kept

What each feature is made of is rack/features.json. A feature with no line
in the choices file is on, so a machine that never ran the picker keeps
everything. RIG_DRY_RUN=1 prints what on/off/remove would do.
EOF
}
