# notify — desktop notifications, falling back to the log when nobody is home.
#
# Generic freedesktop only. The on-screen volume/brightness bar is presentation
# policy and belongs to relay, not here.

rig::load log check

RIG_MODULE_SUMMARY[notify]="desktop notifications, with a log fallback"
RIG_MODULE_ACTIONS[notify]="send error available"
RIG_MODULE_STATUS[notify]="ready"
RIG_MODULE_TIER[notify]="core"

# A notification daemon needs a session bus to talk to. Without one,
# notify-send blocks or fails, so check before reaching for it.
rig::notify::available() {
    rig::check::has notify-send || return 1
    [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} || -S ${XDG_RUNTIME_DIR:-/nonexistent}/bus ]]
}

# send [-u low|normal|critical] [-i icon] [-t ms] [-a app] [-r id] <summary> [body]
rig::notify::send() {
    local -a args=()
    local urgency=normal

    while (($#)); do
        case $1 in
            -u | --urgency)
                urgency=${2:-normal}
                shift 2
                ;;
            -i | --icon)
                args+=(-i "${2:-}")
                shift 2
                ;;
            -t | --expire)
                args+=(-t "${2:-}")
                shift 2
                ;;
            -a | --app)
                args+=(-a "${2:-}")
                shift 2
                ;;
            -r | --replace)
                args+=(-r "${2:-}")
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                rig::log::error "notify: unknown option: $1"
                return "${RIG_EX_USAGE:-2}"
                ;;
            *) break ;;
        esac
    done

    local summary=${1:-}
    local body=${2:-}
    [[ -n $summary ]] || {
        rig::log::error "notify: no summary given"
        return "${RIG_EX_USAGE:-2}"
    }

    if rig::notify::available; then
        notify-send -u "$urgency" -a "${RIG_TAG}" "${args[@]}" -- "$summary" "$body"
    else
        # Not a failure: a script run over ssh or from a systemd unit should
        # still say its piece, just somewhere else.
        case $urgency in
            critical) rig::log::error "${summary}${body:+ — $body}" ;;
            low) rig::log::debug "${summary}${body:+ — $body}" ;;
            *) rig::log::info "${summary}${body:+ — $body}" ;;
        esac
    fi
}

# Always logs as well as notifying: errors are the ones you want in the journal
# after the toast has gone.
rig::notify::error() {
    local summary=${1:-}
    local body=${2:-}
    rig::log::error "${summary}${body:+ — $body}"
    rig::notify::available && rig::notify::send -u critical "$summary" "$body"
    return 0
}

rig::notify::__usage() {
    cat <<'EOF'
  rig notify send "Backup done" "412 files"
  rig notify send -u critical -i dialog-error "Mount failed"
  rig notify error "Screenshot failed" "no output selected"

Falls back to rig log when there is no notification daemon or session bus.
EOF
}
