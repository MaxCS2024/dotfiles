# bluetooth — adapter state, why pairing is not working, and the safe repairs.
#
# Same shape as the network module: sysfs for the hardware questions,
# bluetoothctl only once the daemon is known to be up, and rig's diag module
# for the findings and the doctor/fix flow.
#
# fix only ever performs actions that the checks attached to a finding, so
# doctor is always an accurate preview of it.
#
# Ported from bin/orbit-bluetooth.

rig::load log check proc diag

RELAY_MODULE_SUMMARY[bluetooth]="adapter state, diagnosis, repairs, and devices"
RELAY_MODULE_ACTIONS[bluetooth]="status doctor fix devices"
RELAY_MODULE_STATUS[bluetooth]="ready"
RELAY_MODULE_TIER[bluetooth]="general"

: "${RELAY_SYSFS:=/sys}"

# ---- helpers -----------------------------------------------------------------

relay::bluetooth::__adapters() {
    local d
    for d in "$RELAY_SYSFS"/class/bluetooth/hci*; do
        [[ -e $d ]] || continue
        basename "$d"
    done
}

# bluetoothctl needs the daemon running, so every use is guarded by the
# service check having passed first.
relay::bluetooth::__show() { bluetoothctl show 2>/dev/null; }

relay::bluetooth::__powered() {
    relay::bluetooth::__show | grep -qE '^\s*Powered:\s*yes'
}

relay::bluetooth::__say() {
    if ((${RIG_DIAG_JSON:-0})); then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi
}

# ---- checks ------------------------------------------------------------------

relay::bluetooth::__check_package() {
    if ! rig::check::has bluetoothctl; then
        # bluez is the daemon, bluez-utils supplies bluetoothctl. Installing
        # only bluez is a common half-setup that leaves no way to pair.
        rig::diag::add package problem \
            "bluetoothctl not found (sudo pacman -S bluez bluez-utils)"
        return 0
    fi
    rig::diag::add package ok "bluez present"
}

relay::bluetooth::__check_service() {
    rig::check::has systemctl || {
        rig::diag::add service warn "systemctl not available"
        return 0
    }

    if ! systemctl list-unit-files bluetooth.service >/dev/null 2>&1 ||
        ! systemctl cat bluetooth.service >/dev/null 2>&1; then
        rig::diag::add service problem "bluetooth.service not installed"
        return 0
    fi

    if systemctl is-active --quiet bluetooth.service 2>/dev/null; then
        rig::diag::add service ok "bluetooth.service running"
        return 0
    fi

    rig::diag::add service problem \
        "bluetooth.service not running" \
        "start_service:bluetooth.service"
}

relay::bluetooth::__check_adapter() {
    local -a found
    mapfile -t found < <(relay::bluetooth::__adapters)

    if ((${#found[@]} == 0)); then
        # No hci device usually means missing firmware or a USB dongle that is
        # not plugged in — not something this can repair.
        rig::diag::add adapter problem \
            "no bluetooth adapter found — check firmware, or that the dongle is connected"
        return 0
    fi

    rig::diag::add adapter ok "${found[*]}"
}

relay::bluetooth::__check_rfkill() {
    local d type soft hard soft_blocked=0 hard_blocked=0

    for d in "$RELAY_SYSFS"/class/rfkill/rfkill*; do
        [[ -d $d ]] || continue
        type=$(cat "$d/type" 2>/dev/null) || continue
        [[ $type == bluetooth ]] || continue
        soft=$(cat "$d/soft" 2>/dev/null || printf '0')
        hard=$(cat "$d/hard" 2>/dev/null || printf '0')
        [[ $soft == 1 ]] && soft_blocked=1
        [[ $hard == 1 ]] && hard_blocked=1
    done

    if ((hard_blocked)); then
        # A hard block is a physical switch or a BIOS/firmware setting. No
        # amount of software can clear it, and saying so saves a lot of time.
        rig::diag::add rfkill problem \
            "bluetooth hard-blocked — a physical switch or BIOS setting, not fixable in software"
        return 0
    fi

    if ((soft_blocked)); then
        rig::diag::add rfkill problem \
            "bluetooth soft-blocked by rfkill" \
            "rfkill_unblock"
        return 0
    fi

    rig::diag::add rfkill ok "not blocked"
}

relay::bluetooth::__check_powered() {
    # Only meaningful once the daemon is up; without it bluetoothctl reports
    # nothing and the finding would be misleading.
    rig::check::has bluetoothctl || return 0
    systemctl is-active --quiet bluetooth.service 2>/dev/null || return 0

    if relay::bluetooth::__powered; then
        rig::diag::add powered ok "adapter powered on"
    else
        rig::diag::add powered problem \
            "adapter powered off" \
            "power_on"
    fi
}

relay::bluetooth::__check_audio() {
    # Bluetooth headsets need a PipeWire/PulseAudio bridge. Pairing succeeds
    # without it and then no audio arrives, which reads as a broken headset.
    rig::check::has bluetoothctl || return 0
    if rig::check::has wpctl || rig::check::has pactl; then
        rig::diag::add audio ok "audio bridge present"
    else
        rig::diag::add audio warn \
            "no pipewire/pulse detected — headsets will pair but produce no sound"
    fi
}

relay::bluetooth::__run_checks() {
    relay::bluetooth::__check_package
    relay::bluetooth::__check_service
    relay::bluetooth::__check_adapter
    relay::bluetooth::__check_rfkill
    relay::bluetooth::__check_powered
    relay::bluetooth::__check_audio
}

relay::bluetooth::__apply_fix() {
    local action=$1 kind arg
    kind=${action%%:*}
    arg=${action#*:}

    case "$kind" in
        rfkill_unblock)
            relay::bluetooth::__say "  rfkill unblock bluetooth"
            ((${RIG_DRY_RUN:-0})) && return 0
            rig::check::require rfkill || return "$RIG_EX_NODEP"
            sudo rfkill unblock bluetooth
            ;;
        start_service)
            relay::bluetooth::__say "  systemctl enable --now $arg"
            ((${RIG_DRY_RUN:-0})) && return 0
            sudo systemctl enable --now "$arg"
            ;;
        power_on)
            relay::bluetooth::__say "  bluetoothctl power on"
            ((${RIG_DRY_RUN:-0})) && return 0
            # Not sudo: bluetoothctl talks to the daemon over D-Bus as the
            # logged-in user, and running it as root uses the wrong session.
            bluetoothctl power on >/dev/null
            ;;
        *)
            rig::log::error "internal: unknown fix action '$kind'"
            return "$RIG_EX_FAIL"
            ;;
    esac
}

# ---- actions -----------------------------------------------------------------

relay::bluetooth::__opts() {
    while (($#)); do
        case "$1" in
            --json) RIG_DIAG_JSON=1 ;;
            --dry-run | -n) RIG_DRY_RUN=1 ;;
            --yes | -y) RIG_YES=1 ;;
            *)
                rig::log::error "unknown option: $1"
                return "$RIG_EX_USAGE"
                ;;
        esac
        shift
    done

    ((${RIG_DIAG_JSON:-0})) && { rig::check::require jq || return "$RIG_EX_NODEP"; }
    ((${RIG_DRY_RUN:-0} && ${RIG_YES:-0})) && {
        rig::log::error "--dry-run and --yes are contradictory"
        return "$RIG_EX_USAGE"
    }
    return 0
}

relay::bluetooth::status() {
    relay::bluetooth::__opts "$@" || return $?
    rig::diag::status bluetooth relay::bluetooth::__run_checks
}

relay::bluetooth::doctor() {
    relay::bluetooth::__opts "$@" || return $?
    rig::diag::doctor bluetooth relay::bluetooth::__run_checks "relay bluetooth fix"
}

relay::bluetooth::fix() {
    relay::bluetooth::__opts "$@" || return $?
    rig::diag::fix relay::bluetooth::__run_checks relay::bluetooth::__apply_fix
}

relay::bluetooth::devices() {
    rig::check::require bluetoothctl || return "$RIG_EX_NODEP"

    local -a known connected
    mapfile -t known < <(bluetoothctl devices 2>/dev/null | sed 's/^Device //')
    mapfile -t connected < <(bluetoothctl devices Connected 2>/dev/null | sed 's/^Device //')

    if ((${#known[@]} == 0)); then
        printf 'no known devices — pair one with: bluetoothctl\n'
        return 0
    fi

    local dev mac
    printf 'devices:\n'
    for dev in "${known[@]}"; do
        mac=${dev%% *}
        if printf '%s\n' "${connected[@]}" | grep -q "^$mac"; then
            printf '  %-20s %s (connected)\n' "$mac" "${dev#* }"
        else
            printf '  %-20s %s\n' "$mac" "${dev#* }"
        fi
    done
}

relay::bluetooth::__usage() {
    cat <<'EOF'
  relay bluetooth status     what bluetooth is doing right now
  relay bluetooth doctor     walk the failure chain and report what is broken
  relay bluetooth fix        apply the repairs doctor found
  relay bluetooth devices    list known and connected devices

fix only ever performs actions doctor flagged — it takes no independent
action, so doctor is always an accurate preview of it.

options
  --json          machine-readable output (status, doctor)
  --dry-run, -n   show what fix would do, change nothing
  --yes, -y       skip confirmations

env
  RELAY_SYSFS   where to read adapter state from (default: /sys)

exit status
  0  no problems
  1  at least one problem found
EOF
}
