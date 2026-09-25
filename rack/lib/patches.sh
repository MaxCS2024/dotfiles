# patches — fixes for one piece of hardware, installed only where it is.
#
# A patch is one udev rule in udev/ at the repo root. The Apple SuperDrive
# is the first: it spits every disc back out until the host sends Apple's
# wake-up command, and the rule sends it. These aren't features: nothing
# in the shell shows them and there is nothing to switch off, and most
# machines never see the device.
#
# The rule's first comment lines say what the patch is:
#
#   # Patch: Apple SuperDrive                 the label list and Conf show
#   # Needs: sg3_utils                         repo packages the rule runs
#   # Trigger: --subsystem-match=block ...     udevadm trigger arguments that
#                                              apply it to devices already
#                                              plugged in (optional)
#
# The name is the file's, without the number and .rules: apple-superdrive.
#
# Copied into /etc/udev/rules.d rather than linked: udev reads its rules
# before /home is guaranteed to be mounted, so a link back into this repo
# can dangle at boot. A rule edited here reads "out of date" in list until
# it is installed again.
#
# Conf › System › Patches (quickshell/main/menu/ConfMenu.qml) reads list
# and opens install or remove in a terminal, for sudo.

rig::load log check proc
rack::load ui

RACK_MODULE_SUMMARY[patches]="hardware fixes, one udev rule per device"
RACK_MODULE_ACTIONS[patches]="list install remove"
RACK_MODULE_STATUS[patches]="ready"
RACK_MODULE_TIER[patches]="general"

rack::patches::__source() {
    rack::load manifest
    printf '%s\n' "${RACK_PATCHES:-$(rack::manifest::dotfiles)/udev}"
}

rack::patches::__target() {
    printf '%s\n' "${RACK_PATCHES_TARGET:-/etc/udev/rules.d}"
}

# Every patch's rule file, sorted, one per line.
rack::patches::__files() {
    local f
    for f in "$(rack::patches::__source)"/*.rules; do
        [[ -f $f ]] && printf '%s\n' "$f"
    done
}

rack::patches::__name() {
    local base=${1##*/}
    base=${base%.rules}
    printf '%s\n' "${base#[0-9][0-9]-}"
}

rack::patches::__file() {
    local f
    while read -r f; do
        [[ $(rack::patches::__name "$f") == "$1" ]] && {
            printf '%s\n' "$f"
            return 0
        }
    done < <(rack::patches::__files)
    rig::log::error "no patch called '$1' (try: rack patches list)"
    return "$RIG_EX_USAGE"
}

# The value of one header line (`# Patch: …`), from the leading comments.
rack::patches::__header() {
    local line
    while IFS= read -r line; do
        [[ $line == '#'* ]] || return 0
        [[ $line =~ ^#[[:space:]]*$2:[[:space:]]*(.*)$ ]] && {
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        }
    done <"$1"
}

rack::patches::__state() {
    local installed
    installed="$(rack::patches::__target)/${1##*/}"
    if [[ ! -f $installed ]]; then
        echo "not installed"
    elif cmp -s -- "$1" "$installed"; then
        echo installed
    else
        echo "out of date"
    fi
}

rack::patches::list() {
    local f label
    rack::ui::rich && {
        rack::patches::__rich_list
        return
    }
    while read -r f; do
        label=$(rack::patches::__header "$f" Patch)
        printf '  %-18s %-14s %s\n' "$(rack::patches::__name "$f")" \
            "$(rack::patches::__state "$f")" "${label:-$(rack::patches::__name "$f")}"
    done < <(rack::patches::__files)
}

# The list on a terminal, by label, with the name the commands take on the
# right. The Conf menu parses the plain list, which stays as it is.
rack::patches::__rich_list() {
    local f label state n=0 installed=0
    local -a rows=()
    local RACK_UI_NAME_WIDTH=20 RACK_UI_TEXT_WIDTH=14
    local -A level=([installed]=ok ["out of date"]=warn ["not installed"]=skip)
    while read -r f; do
        n=$((n + 1))
        state=$(rack::patches::__state "$f")
        [[ $state == installed ]] && installed=$((installed + 1))
        label=$(rack::patches::__header "$f" Patch)
        rows+=("${level[$state]}"$'\t'"${label:-$(rack::patches::__name "$f")}"$'\t'"$state"$'\t'"$(rack::patches::__name "$f")")
    done < <(rack::patches::__files)
    rack::ui::header "Patches" "hardware fixes · $installed of $n installed on this machine"
    printf '\n'
    local row lvl text name
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r lvl label text name <<<"$row"
        rack::ui::row "$lvl" "$label" "$text" "$name"
    done
    ((n)) || rack::ui::note "no patches in $(rack::patches::__source)"
}

# Header for install and remove on a terminal: the labels of what is being
# done, which is also the window title the Conf menu gives it.
rack::patches::__title() {
    rack::ui::rich || return 0
    local doing=$1
    shift
    rack::ui::header "Patches" "$doing $(rack::patches::__labels "$@")"
}

# "Apple SuperDrive, Other thing" for the names given.
rack::patches::__labels() {
    local name f label labels=""
    for name in "$@"; do
        f=$(rack::patches::__file "$name" 2>/dev/null) || continue
        label=$(rack::patches::__header "$f" Patch)
        labels+="${labels:+, }${label:-$name}"
    done
    printf '%s' "${labels:-$*}"
}

# The closing line of install or remove on a terminal.
rack::patches::__done() {
    local verb=$1
    shift
    if [[ $RIG_DRY_RUN != 0 ]]; then
        rack::ui::finish info "Dry run — nothing $verb"
    else
        rack::ui::finish ok "$(rack::patches::__labels "$@") $verb"
    fi
}

rack::patches::install() {
    (($#)) || {
        rig::log::error "install which patch? (try: rack patches list)"
        return "$RIG_EX_USAGE"
    }
    local name f trigger
    local -a files=() pkgs=() needs=() triggers=() args=()
    for name in "$@"; do
        f=$(rack::patches::__file "$name") || return
        files+=("$f")
        read -ra needs <<<"$(rack::patches::__header "$f" Needs)"
        pkgs+=("${needs[@]}")
        trigger=$(rack::patches::__header "$f" Trigger)
        [[ -n $trigger ]] && triggers+=("$trigger")
    done
    rack::patches::__title "installing" "$@"
    if ((${#pkgs[@]})); then
        rack::ui::rule "" "Packages" "${pkgs[*]}"
        rig::proc::run sudo pacman -S --needed -- "${pkgs[@]}" || return "$RIG_EX_FAIL"
    fi
    rack::ui::rule "" "Rules" "$(rack::patches::__target)"
    rig::proc::run sudo install -m644 -t "$(rack::patches::__target)" -- "${files[@]}" ||
        return "$RIG_EX_FAIL"
    if rack::ui::rich; then
        for f in "${files[@]}"; do rack::ui::say ok "${f##*/}"; done
    fi
    rig::proc::run sudo udevadm control --reload || return "$RIG_EX_FAIL"
    # So a device already plugged in gets it now, not on its next plug-in.
    # read -a splits the header into words without globbing sr*.
    for trigger in "${triggers[@]}"; do
        read -ra args <<<"$trigger"
        rig::proc::run sudo udevadm trigger --action=add "${args[@]}" || return "$RIG_EX_FAIL"
    done
    rack::ui::rich && ((${#triggers[@]})) && rack::ui::say ok "applied to devices already plugged in"
    if rack::ui::rich; then
        rack::patches::__done installed "$@"
    else
        rig::log::success "installed $*"
    fi
}

# Takes the rule out and asks first. The packages stay: sg3_utils is
# small, and something else may use it.
rack::patches::remove() {
    (($#)) || {
        rig::log::error "remove which patch? (try: rack patches list)"
        return "$RIG_EX_USAGE"
    }
    local name f installed
    local -a gone=()
    for name in "$@"; do rack::patches::__file "$name" >/dev/null || return; done
    rack::patches::__title "removing" "$@"
    rack::ui::rich && printf '\n'
    for name in "$@"; do
        f=$(rack::patches::__file "$name") || return
        installed="$(rack::patches::__target)/${f##*/}"
        if [[ -f $installed ]]; then
            gone+=("$installed")
        elif rack::ui::rich; then
            rack::ui::say skip "$name: not installed"
        else
            printf '  %s: not installed\n' "$name"
        fi
    done
    ((${#gone[@]})) || return 0
    if rack::ui::rich; then
        rack::ui::rule "" "Removing would delete"
        for f in "${gone[@]}"; do rack::ui::say warn "$f" 2>&1; done
        printf '\n'
    else
        printf '\nRemoving would delete:\n'
        printf '  %s\n' "${gone[@]}"
    fi
    if [[ $RIG_DRY_RUN == 0 ]] && ! rig::check::confirm "remove?"; then
        if rack::ui::rich; then
            rack::ui::finish info "Nothing removed" "left installed"
        else
            printf '  left installed\n'
        fi
        return 0
    fi
    rig::proc::run sudo rm -f -- "${gone[@]}" || return "$RIG_EX_FAIL"
    rig::proc::run sudo udevadm control --reload || return "$RIG_EX_FAIL"
    if rack::ui::rich; then
        rack::patches::__done removed "$@"
    else
        rig::log::success "removed $*"
    fi
}

rack::patches::__default() {
    case ${1-} in
        '') rack::patches::list ;;
        *)
            rig::log::error "unknown action '$1' (try: ${RACK_MODULE_ACTIONS[patches]})"
            return "$RIG_EX_USAGE"
            ;;
    esac
}

rack::patches::__usage() {
    cat <<'EOF'
  rack patches                 same as list
  rack patches list            every patch: installed, out of date, or not
  rack patches install <p>...  its packages, then the rule into /etc/udev/rules.d
  rack patches remove <p>...   the rule out of /etc again (asks first)

A patch is a udev rule in udev/ for one piece of hardware; its header
comments name it (Patch:), its packages (Needs:) and how to apply it to a
device already plugged in (Trigger:). RIG_DRY_RUN=1 prints what
install/remove would do.
EOF
}
