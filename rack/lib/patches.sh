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
    while read -r f; do
        label=$(rack::patches::__header "$f" Patch)
        printf '  %-18s %-14s %s\n' "$(rack::patches::__name "$f")" \
            "$(rack::patches::__state "$f")" "${label:-$(rack::patches::__name "$f")}"
    done < <(rack::patches::__files)
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
    if ((${#pkgs[@]})); then
        rig::proc::run sudo pacman -S --needed -- "${pkgs[@]}" || return "$RIG_EX_FAIL"
    fi
    rig::proc::run sudo install -m644 -t "$(rack::patches::__target)" -- "${files[@]}" ||
        return "$RIG_EX_FAIL"
    rig::proc::run sudo udevadm control --reload || return "$RIG_EX_FAIL"
    # So a device already plugged in gets it now, not on its next plug-in.
    # read -a splits the header into words without globbing sr*.
    for trigger in "${triggers[@]}"; do
        read -ra args <<<"$trigger"
        rig::proc::run sudo udevadm trigger --action=add "${args[@]}" || return "$RIG_EX_FAIL"
    done
    rig::log::success "installed $*"
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
    for name in "$@"; do
        f=$(rack::patches::__file "$name") || return
        installed="$(rack::patches::__target)/${f##*/}"
        if [[ -f $installed ]]; then
            gone+=("$installed")
        else
            printf '  %s: not installed\n' "$name"
        fi
    done
    ((${#gone[@]})) || return 0
    printf '\nRemoving would delete:\n'
    printf '  %s\n' "${gone[@]}"
    if [[ $RIG_DRY_RUN == 0 ]] && ! rig::check::confirm "remove?"; then
        printf '  left installed\n'
        return 0
    fi
    rig::proc::run sudo rm -f -- "${gone[@]}" || return "$RIG_EX_FAIL"
    rig::proc::run sudo udevadm control --reload || return "$RIG_EX_FAIL"
    rig::log::success "removed $*"
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
