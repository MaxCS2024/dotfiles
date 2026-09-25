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
# A feature with `"switch": false` (lazyvim) is installed or it isn't: it has
# no daemon to stop and nothing in the shell to hide, so there is no off.
# `off` refuses it, `list` shows "-" for its state, and in the picker its tick
# means installed — unticking it goes straight to the question remove asks.
#
# setup and teardown commands run from the repo root, so a feature can name a
# script of its own by its path in the repo (nvim/install.sh).
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
rack::load ui

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

# False only for a feature that says `"switch": false` (see the header).
rack::features::__switchable() {
    jq -e --arg n "$1" '.features[$n].switch != false' "$(rack::features::__registry)" >/dev/null
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
        (cd -- "$RACK_ROOT/.." && rig::proc::run "${argv[@]}") || {
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

# The header for on and remove, on a terminal: "Features", and what is
# being done to which. Opened from the Conf menu these run in a window of
# their own, and this is what that window opens with.
rack::features::__header() {
    rack::ui::rich || return 0
    local doing=$1 name labels=""
    shift
    for name in "$@"; do
        labels+="${labels:+, }$(rack::features::__field "$name" label)"
    done
    rack::ui::header "Features" "$doing $labels"
}

rack::features::on() {
    local name
    rack::features::__require || return
    (($#)) || {
        rig::log::error "usage: rack features on <feature>..."
        return "$RIG_EX_USAGE"
    }
    for name in "$@"; do rack::features::__known "$name" || return; done
    rack::features::__header "turning on" "$@"
    local label
    for name in "$@"; do
        label=$(rack::features::__field "$name" label)
        if ! rack::features::__installed "$name"; then
            if rack::ui::rich; then
                rack::ui::rule "" "Installing ${label:-$name}"
            else
                rig::log::info "installing $name"
            fi
            rack::features::__install "$name" || {
                rack::ui::rich && rack::ui::finish bad "${label:-$name} did not install" "see above"
                return "$RIG_EX_FAIL"
            }
        fi
        rack::features::__units "$name" enable
        rack::features::__set "$name" on
        if rack::ui::rich; then
            if [[ $RIG_DRY_RUN != 0 ]]; then
                rack::ui::finish info "Dry run — ${label:-$name} unchanged"
            elif rack::features::__switchable "$name"; then
                rack::ui::finish ok "${label:-$name} is on"
            else
                rack::ui::finish ok "${label:-$name} is installed"
            fi
        else
            rack::features::__switchable "$name" && rig::log::success "$name is on" ||
                rig::log::success "$name is installed"
        fi
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
    for name in "$@"; do
        rack::features::__known "$name" || return
        rack::features::__switchable "$name" || {
            rig::log::error "$name has nothing to switch off; 'rack features remove $name' uninstalls it"
            return "$RIG_EX_USAGE"
        }
    done
    for name in "$@"; do
        rack::features::__set "$name" off
        rack::features::__units "$name" disable
        if rack::ui::rich; then
            rack::ui::say ok "$(rack::features::__field "$name" label) is off"
            rack::ui::note "still installed — rack features remove $name uninstalls it"
        else
            rig::log::success "$name is off (still installed; 'rack features remove $name' uninstalls it)"
        fi
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
    local -a switchable=()
    for name in "$@"; do
        rack::features::__known "$name" || return
        rack::features::__switchable "$name" && switchable+=("$name")
    done
    rack::features::__header "removing" "$@"
    rack::ui::rich && printf '\n'
    if ((${#switchable[@]})); then
        rack::features::off "${switchable[@]}" || return
    fi
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
    local label
    label=$(rack::features::__field "$name" label)
    if ((${#pkgs[@]} + ${#data[@]} == 0)); then
        if rack::ui::rich; then
            rack::ui::say skip "${label:-$name}: nothing installed to remove"
        else
            printf '  %s: nothing installed to remove\n' "$name"
        fi
        return 0
    fi
    if rack::ui::rich; then
        RACK_UI_NAME_WIDTH=8
        rack::ui::rule "" "Removing ${label:-$name} would delete"
        for p in "${pkgs[@]}"; do rack::ui::row warn "package" "$p"; done
        for p in "${data[@]}"; do
            rack::ui::row warn "files" "${p/#$HOME/\~}" "$(du -sh -- "$p" 2>/dev/null | cut -f1)"
        done
        printf '\n'
    else
        printf '\nRemoving %s would delete:\n' "$name"
        for p in "${pkgs[@]}"; do printf '  package  %s\n' "$p"; done
        for p in "${data[@]}"; do
            printf '  files    %s (%s)\n' "${p/#$HOME/\~}" "$(du -sh -- "$p" 2>/dev/null | cut -f1)"
        done
    fi
    if [[ $RIG_DRY_RUN == 0 ]] && ! rig::check::confirm "remove these?"; then
        if rack::ui::rich; then
            rack::ui::finish info "Nothing removed" "${label:-$name} is off and still installed"
        else
            printf '  %s is off and still installed\n' "$name"
        fi
        return 0
    fi
    # Teardown runs while the packages are still there to run it
    # (voxtype uninstalls its own unit).
    rack::features::__run_each "$name" teardown || true
    if ((${#pkgs[@]})); then
        rig::proc::run sudo pacman -Rns -- "${pkgs[@]}" || return "$RIG_EX_FAIL"
    fi
    for p in "${data[@]}"; do rig::proc::run rm -rf -- "$p"; done
    if rack::ui::rich && [[ $RIG_DRY_RUN != 0 ]]; then
        rack::ui::finish info "Dry run — nothing removed"
    elif rack::ui::rich; then
        rack::ui::finish ok "${label:-$name} removed"
    else
        rig::log::success "$name removed"
    fi
}

rack::features::list() {
    local name installed state
    rack::features::__require || return
    rack::ui::rich && {
        rack::features::__rich_list
        return
    }
    while read -r name; do
        rack::features::__installed "$name" && installed=installed || installed="not installed"
        rack::features::__switchable "$name" && state=$(rack::features::__state "$name") || state=-
        printf '  %-12s %-4s %-14s %s\n' "$name" "$state" "$installed" \
            "$(rack::features::__field "$name" label)"
    done < <(rack::features::__names)
}

# The list on a terminal: each feature by its label, ✓ when it is installed
# and on, · when off or not installed, its name (what the commands take) on
# the right. Only here — the Conf menu parses the plain list above.
rack::features::__rich_list() {
    local name label on_count=0 total=0
    local RACK_UI_NAME_WIDTH=16 RACK_UI_TEXT_WIDTH=14
    local -a rows=()
    while read -r name; do
        total=$((total + 1))
        label=$(rack::features::__field "$name" label)
        if ! rack::features::__installed "$name"; then
            rows+=("skip"$'\t'"$label"$'\t'"not installed"$'\t'"$name")
        elif ! rack::features::__switchable "$name"; then
            on_count=$((on_count + 1))
            rows+=("ok"$'\t'"$label"$'\t'"installed"$'\t'"$name")
        elif [[ $(rack::features::__state "$name") == on ]]; then
            on_count=$((on_count + 1))
            rows+=("ok"$'\t'"$label"$'\t'"on"$'\t'"$name")
        else
            rows+=("skip"$'\t'"$label"$'\t'"off"$'\t'"$name")
        fi
    done < <(rack::features::__names)
    rack::ui::header "Features" "$on_count of $total in use · rack features to pick"
    printf '\n'
    local row level text
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r level label text name <<<"$row"
        rack::ui::row "$level" "$label" "$text" "$name"
    done
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
        if ! rack::features::__switchable "${names[$i]}"; then
            rack::features::__installed "${names[$i]}" && ticks[i]=1 || ticks[i]=0
        elif ((first)); then
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
    rack::ui::init
    printf '\n  %s┏━━┓┏┓┏━━┓%s  \e[1mFeatures\e[0m\n' "$C_ACCENT" "$C_OFF"
    printf '  %s┗━━┛┗┛┗━━┛%s  \e[2mthe optional parts of this desktop\e[0m\n\n' "$C_ACCENT" "$C_OFF"
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
    local -a turn_on=() turn_off=() uninstall=()
    for i in "${!_names[@]}"; do
        name=${_names[$i]}
        was=$(rack::features::__state "$name")
        # Installed or not: a tick installs it, an untick asks to remove it.
        if ! rack::features::__switchable "$name"; then
            if ((_ticks[i])); then
                rack::features::__installed "$name" || turn_on+=("$name")
            elif rack::features::__installed "$name"; then
                uninstall+=("$name")
            fi
        elif ((_ticks[i])); then
            if ((first)) || [[ $was == off ]] || ! rack::features::__installed "$name"; then
                turn_on+=("$name")
            fi
        elif ((first)) || [[ $was == on ]]; then
            turn_off+=("$name")
        fi
    done
    if ((${#turn_on[@]} + ${#turn_off[@]} + ${#uninstall[@]} == 0)); then
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
    for name in "${uninstall[@]}"; do
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
