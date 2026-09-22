# hypr — talking to Hyprland.
#
# Planning note, corrected: I said this would hit the IPC socket directly
# instead of spawning hyprctl, and be faster for it. That was wrong. bash
# cannot open a unix socket, so "direct" means spawning socat — the same one
# process hyprctl costs. There is no win, and hyprctl tracks protocol changes
# for us, so requests go through hyprctl.
#
# The socket is still worth having for `events`, where a persistent connection
# is the entire feature and spawning per line is not an option.

rig::load log check proc

RELAY_MODULE_SUMMARY[hypr]="query and drive Hyprland"
RELAY_MODULE_ACTIONS[hypr]="dispatch get active clients monitors workspaces events signature running"
RELAY_MODULE_STATUS[hypr]="ready"
RELAY_MODULE_TIER[hypr]="core"

relay::hypr::signature() {
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || {
        rig::log::error "not inside a Hyprland session (no HYPRLAND_INSTANCE_SIGNATURE)"
        return "$RIG_EX_FAIL"
    }
    printf '%s\n' "$HYPRLAND_INSTANCE_SIGNATURE"
}

relay::hypr::running() { [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && rig::check::has hyprctl; }

relay::hypr::__require() {
    relay::hypr::running || {
        rig::log::error "Hyprland is not running, or hyprctl is not installed"
        return "$RIG_EX_FAIL"
    }
}

# dispatch <dispatcher> [args...]
#   relay hypr dispatch workspace 3
relay::hypr::dispatch() {
    relay::hypr::__require || return $?
    (($#)) || {
        rig::log::error "dispatch: nothing to dispatch"
        return "$RIG_EX_USAGE"
    }
    rig::proc::run hyprctl dispatch "$@"
}

# get <endpoint> — always JSON, because parsing hyprctl's human output is a
# trap that breaks on the next release.
relay::hypr::get() {
    relay::hypr::__require || return $?
    local endpoint=${1:-}
    [[ -n $endpoint ]] || {
        rig::log::error "get: no endpoint given (clients, monitors, workspaces, activewindow…)"
        return "$RIG_EX_USAGE"
    }
    hyprctl -j "$endpoint"
}

relay::hypr::active() { relay::hypr::get activewindow; }
relay::hypr::clients() { relay::hypr::get clients; }
relay::hypr::monitors() { relay::hypr::get monitors; }
relay::hypr::workspaces() { relay::hypr::get workspaces; }

relay::hypr::__event_socket() {
    local sig=${HYPRLAND_INSTANCE_SIGNATURE:-} candidate
    for candidate in \
        "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/$sig/.socket2.sock" \
        "/tmp/hypr/$sig/.socket2.sock"; do
        [[ -S $candidate ]] && {
            printf '%s\n' "$candidate"
            return 0
        }
    done
    return 1
}

# events — stream compositor events, one per line, forever.
#   relay hypr events | while read -r line; do ...; done
relay::hypr::events() {
    relay::hypr::__require || return $?
    rig::check::require socat

    local socket
    if ! socket=$(relay::hypr::__event_socket); then
        rig::log::error "cannot find Hyprland's event socket for this instance"
        return "$RIG_EX_FAIL"
    fi

    rig::log::debug "streaming events from $socket"
    socat -U - "UNIX-CONNECT:$socket"
}

relay::hypr::__usage() {
    cat <<'EOF'
  relay hypr dispatch workspace 3
  relay hypr dispatch togglefloating
  relay hypr active                     activewindow, as JSON
  relay hypr get devices                any hyprctl endpoint, as JSON
  relay hypr events                     persistent stream, one event per line

Queries go through hyprctl. Only `events` opens the socket, because there a
persistent connection is the whole point. Needs socat.
EOF
}
