# network — wifi and ethernet state, why it is broken, and the safe repairs.
#
# Reads sysfs directly wherever it can, so "is there a card" and "is it
# blocked" are answerable without iw, iwconfig, or a running backend. The
# findings and the doctor/fix flow come from rig's diag module; everything here
# is the knowledge about what to look at and in what order.
#
# fix only ever performs actions that the checks attached to a finding, so
# doctor is always an accurate preview of it.
#
# Ported from bin/orbit-network.

rig::load log check proc diag

RELAY_MODULE_SUMMARY[network]="wifi and ethernet state, diagnosis, and repairs"
RELAY_MODULE_ACTIONS[network]="status doctor fix"
RELAY_MODULE_STATUS[network]="ready"
RELAY_MODULE_TIER[network]="general"

# Overridable so the checks can be run against a fake tree in tests without
# touching real hardware state.
: "${RELAY_SYSFS:=/sys}"

# Every backend this knows about, as "service:package".
declare -ga RELAY_NETWORK_BACKENDS=(
    "NetworkManager.service:networkmanager"
    "iwd.service:iwd"
    "systemd-networkd.service:systemd"
)

# ---- helpers -----------------------------------------------------------------

# Interfaces with a wireless/ subdirectory are wifi; the rest (minus loopback)
# are treated as wired.
relay::network::__wifi_ifaces() {
    local d
    for d in "$RELAY_SYSFS"/class/net/*/wireless; do
        [[ -e $d ]] || continue
        basename "$(dirname "$d")"
    done
}

relay::network::__wired_ifaces() {
    local d name
    for d in "$RELAY_SYSFS"/class/net/*/; do
        name=$(basename "$d")
        [[ $name == lo ]] && continue
        [[ -e $d/wireless ]] && continue
        # Virtual interfaces (docker0, veth, br-) have no device link.
        [[ -e $d/device ]] || continue
        printf '%s\n' "$name"
    done
}

relay::network::__iface_state() {
    local f="$RELAY_SYSFS/class/net/$1/operstate"
    [[ -r $f ]] && cat "$f" || printf 'unknown\n'
}

relay::network::__service_active() { systemctl is-active --quiet "$1" 2>/dev/null; }
relay::network::__service_exists() {
    systemctl list-unit-files "$1" >/dev/null 2>&1 &&
        systemctl cat "$1" >/dev/null 2>&1
}

# Human output goes to stderr under --json so stdout stays one document.
relay::network::__say() {
    if ((${RIG_DIAG_JSON:-0})); then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi
}

# ---- checks ------------------------------------------------------------------

relay::network::__check_backend() {
    local entry svc pkg
    local -a active=() installed=() pkgs=()

    for entry in "${RELAY_NETWORK_BACKENDS[@]}"; do
        svc=${entry%%:*}
        pkg=${entry##*:}
        pkgs+=("$pkg")
        relay::network::__service_exists "$svc" || continue
        installed+=("$svc")
        relay::network::__service_active "$svc" && active+=("$svc")
    done

    if ((${#installed[@]} == 0)); then
        rig::diag::add backend problem \
            "no network backend installed (one of: ${pkgs[*]})"
        return 0
    fi

    if ((${#active[@]} > 1)); then
        # Two backends managing one interface is worse than none: they fight
        # over it and the symptoms look random. Never auto-resolve this — which
        # one to keep is the user's call.
        rig::diag::add backend problem \
            "${#active[@]} backends running at once (${active[*]}) — stop all but one"
        return 0
    fi

    if ((${#active[@]} == 0)); then
        if ((${#installed[@]} == 1)); then
            rig::diag::add backend problem \
                "${installed[0]} installed but not running" \
                "start_service:${installed[0]}"
        else
            # Ambiguous which to start, so report and stop.
            rig::diag::add backend problem \
                "none of ${installed[*]} are running — enable the one you want"
        fi
        return 0
    fi

    rig::diag::add backend ok "${active[0]} running"
}

relay::network::__check_interface() {
    local -a wifi wired
    mapfile -t wifi < <(relay::network::__wifi_ifaces)
    mapfile -t wired < <(relay::network::__wired_ifaces)

    if ((${#wifi[@]} == 0 && ${#wired[@]} == 0)); then
        # Almost always a missing firmware package rather than dead hardware.
        rig::diag::add interface problem \
            "no network interfaces found — check that firmware for your card is installed"
        return 0
    fi

    local parts=""
    ((${#wifi[@]})) && parts+="wifi: ${wifi[*]}"
    ((${#wired[@]})) && parts+="${parts:+, }wired: ${wired[*]}"
    rig::diag::add interface ok "$parts"
}

relay::network::__check_rfkill() {
    local d type soft hard
    local -a blocked_soft=() blocked_hard=()

    for d in "$RELAY_SYSFS"/class/rfkill/rfkill*; do
        [[ -d $d ]] || continue
        type=$(cat "$d/type" 2>/dev/null) || continue
        [[ $type == wlan ]] || continue
        soft=$(cat "$d/soft" 2>/dev/null || printf '0')
        hard=$(cat "$d/hard" 2>/dev/null || printf '0')
        [[ $soft == 1 ]] && blocked_soft+=("$(basename "$d")")
        [[ $hard == 1 ]] && blocked_hard+=("$(basename "$d")")
    done

    if ((${#blocked_hard[@]})); then
        # A hard block is a physical switch or a BIOS/firmware setting. No
        # amount of software can clear it, and saying so saves a lot of time.
        rig::diag::add rfkill problem \
            "wifi hard-blocked — a physical switch or BIOS setting, not fixable in software"
        return 0
    fi

    if ((${#blocked_soft[@]})); then
        rig::diag::add rfkill problem \
            "wifi soft-blocked by rfkill" \
            "rfkill_unblock"
        return 0
    fi

    rig::diag::add rfkill ok "not blocked"
}

relay::network::__check_link() {
    local iface state
    local -a down=()
    local any=0

    while read -r iface; do
        [[ -n $iface ]] || continue
        any=1
        state=$(relay::network::__iface_state "$iface")
        [[ $state == up ]] || down+=("$iface")
    done < <(relay::network::__wifi_ifaces)

    ((any)) || {
        rig::diag::add link ok "no wifi interface to bring up"
        return 0
    }

    if ((${#down[@]})); then
        rig::diag::add link warn \
            "interface down: ${down[*]}" \
            "link_up:${down[0]}"
        return 0
    fi

    rig::diag::add link ok "interfaces up"
}

relay::network::__check_connectivity() {
    local iface has_ip=0 addrs=""

    while read -r iface; do
        [[ -n $iface ]] || continue
        # `ip -4 addr` rather than parsing sysfs: addresses are not exposed
        # there, and ip(8) is part of iproute2, which is always present.
        addrs=$(ip -4 -brief addr show "$iface" 2>/dev/null | awk '{print $3}') || addrs=""
        [[ -n $addrs ]] && has_ip=1
    done < <(cat <(relay::network::__wifi_ifaces) <(relay::network::__wired_ifaces))

    if ((has_ip == 0)); then
        rig::diag::add address problem "no IPv4 address on any interface"
        return 0
    fi
    rig::diag::add address ok "have an address"

    if ip route show default 2>/dev/null | grep -q .; then
        rig::diag::add route ok "default route present"
    else
        rig::diag::add route problem "no default route — associated but no DHCP lease?"
        return 0
    fi

    # Only worth testing once there is a route to send it over. Timed out so a
    # broken resolver cannot hang the whole command.
    if timeout 3 getent ahostsv4 archlinux.org >/dev/null 2>&1; then
        rig::diag::add dns ok "resolving"
    else
        rig::diag::add dns warn "cannot resolve names — check /etc/resolv.conf"
    fi
}

relay::network::__run_checks() {
    relay::network::__check_backend
    relay::network::__check_interface
    relay::network::__check_rfkill
    relay::network::__check_link
    relay::network::__check_connectivity
}

# ---- fix ---------------------------------------------------------------------

relay::network::__apply_fix() {
    local action=$1 kind arg
    kind=${action%%:*}
    arg=${action#*:}

    case "$kind" in
        rfkill_unblock)
            relay::network::__say "  rfkill unblock wifi"
            ((${RIG_DRY_RUN:-0})) && return 0
            rig::check::require rfkill || return "$RIG_EX_NODEP"
            sudo rfkill unblock wifi
            ;;
        start_service)
            relay::network::__say "  systemctl enable --now $arg"
            ((${RIG_DRY_RUN:-0})) && return 0
            sudo systemctl enable --now "$arg"
            ;;
        link_up)
            relay::network::__say "  ip link set $arg up"
            ((${RIG_DRY_RUN:-0})) && return 0
            sudo ip link set "$arg" up
            ;;
        *)
            rig::log::error "internal: unknown fix action '$kind'"
            return "$RIG_EX_FAIL"
            ;;
    esac
}

# ---- actions -----------------------------------------------------------------

# Shared option parsing. Sets the RIG_* knobs diag reads, so an action body is
# just the diag call it wraps.
relay::network::__opts() {
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
    rig::check::require ip || return "$RIG_EX_NODEP"
    return 0
}

relay::network::status() {
    relay::network::__opts "$@" || return $?
    rig::diag::status network relay::network::__run_checks
}

relay::network::doctor() {
    relay::network::__opts "$@" || return $?
    rig::diag::doctor network relay::network::__run_checks "relay network fix"
}

relay::network::fix() {
    relay::network::__opts "$@" || return $?
    rig::diag::fix relay::network::__run_checks relay::network::__apply_fix
}

relay::network::__usage() {
    cat <<'EOF'
  relay network status      what the network is doing right now
  relay network doctor      walk the failure chain and report what is broken
  relay network fix         apply the repairs doctor found

fix only ever performs actions doctor flagged — it takes no independent
action, so doctor is always an accurate preview of it.

options
  --json          machine-readable output (status, doctor)
  --dry-run, -n   show what fix would do, change nothing
  --yes, -y       skip confirmations

env
  RELAY_SYSFS   where to read interface state from (default: /sys)

exit status
  0  no problems
  1  at least one problem found
EOF
}
