# notif — desktop notifications, with quickshell as the daemon.
#
# Quickshell's NotificationServer (services/Notifications.qml) is the running
# notification daemon, so anything sent here shows up styled like every other
# desktop notification and lands in its history. This module is both the sender
# the rest of the desktop uses (rack sync, rack update, ...) and the
# control surface for the popups already on screen.
#
# Two things it deliberately does NOT do:
#
#   * It never shells out to notify-send. notify-send's argv parsing is the
#     surface that reinterprets a relayed summary like "--hint=..." or "-rf"
#     as options or hints. busctl takes each value as one typed D-Bus
#     parameter instead, so a summary can never become a hint no matter who
#     generated the text.
#   * It never passes a click action as a shell string. `--exec` collects the
#     rest of the line as a real argv vector, ships it as JSON in a hint, and
#     the shell runs it with execDetached (no shell interpretation). Untrusted
#     data in an argument stays one argument and can never become a command.
#
# Ported from bin/orbit-notif. The hint keys are a contract with the QML side
# (services/Notifications.qml reads them by name), so they moved together.

rig::load log check proc

RELAY_MODULE_SUMMARY[notif]="send and control desktop notifications"
RELAY_MODULE_ACTIONS[notif]="send dnd dismiss invoke list history wait"
RELAY_MODULE_STATUS[notif]="ready"
RELAY_MODULE_TIER[notif]="core"

# Which quickshell config answers IPC. `main` is the daily driver; an
# experiment run with `qs -c foo` is reachable as RELAY_QS_CONFIG=foo.
: "${RELAY_QS_CONFIG:=main}"

# ---- IPC ---------------------------------------------------------------------

# Every action except `send` talks to the shell rather than the bus: DND,
# history and the on-screen popup stack are the shell's state, not D-Bus's.
relay::notif::__ipc() {
    rig::check::has qs || {
        rig::log::error "quickshell (qs) not found"
        return "$RIG_EX_NODEP"
    }
    qs -c "$RELAY_QS_CONFIG" ipc call notifications "$@" 2>/dev/null || {
        rig::log::error "quickshell config '$RELAY_QS_CONFIG' is not running (or has no notifications IPC)"
        return "$RIG_EX_FAIL"
    }
}

# ---- send --------------------------------------------------------------------

# Recognize a known option in both `--flag value` and `--flag=value` forms.
# Returns 1 for anything unrecognized so the caller decides whether that is the
# summary or a hard error. Sets _shift to how many words were consumed.
relay::notif::__parse_send_option() {
    local opt val nargs
    if [[ $1 == --?*=* ]]; then
        opt=${1%%=*}
        val=${1#*=}
        nargs=1
    else
        opt=$1
        val=${2-}
        nargs=2
    fi

    # Valueless flags first — they consume one word regardless of form.
    case $opt in
        -p | --print-id)
            print_id=1
            _shift=1
            return 0
            ;;
        --transient)
            transient=1
            _shift=1
            return 0
            ;;
    esac

    case $opt in
        -u | --urgency | -i | --icon | -g | --glyph | --image | -t | --expire-time | -r | --replace-id | -a | --app-name) ;;
        *) return 1 ;;
    esac

    if ((nargs == 2)) && (($# < 2)); then
        rig::log::error "missing value for $opt"
        return 2
    fi

    case $opt in
        -u | --urgency) urgency=$val ;;
        -i | --icon) app_icon=$val ;;
        -g | --glyph) glyph=$val ;;
        --image) image=$val ;;
        -a | --app-name) app_name=$val ;;
        -r | --replace-id)
            [[ $val =~ ^[0-9]+$ ]] || {
                rig::log::error "invalid $opt (want a numeric id): $val"
                return 2
            }
            replaces_id=$val
            ;;
        -t | --expire-time)
            [[ $val =~ ^-?[0-9]+$ ]] || {
                rig::log::error "invalid $opt (want milliseconds): $val"
                return 2
            }
            expire_timeout=$val
            ;;
    esac

    _shift=$nargs
    return 0
}

# True for a word that is an option rather than the body positional.
relay::notif::__send_flag() {
    case $1 in
        -u | --urgency | -i | --icon | -g | --glyph | --image | -t | --expire-time | \
            -r | --replace-id | -a | --app-name | -p | --print-id | --transient | --exec)
            return 0
            ;;
        --urgency=* | --icon=* | --glyph=* | --image=* | --expire-time=* | --replace-id=* | --app-name=*)
            return 0
            ;;
    esac
    return 1
}

relay::notif::send() {
    local summary="" body="" glyph="" image="" app_icon=""
    local urgency=normal app_name=relay
    local expire_timeout=-1 replaces_id=0 print_id=0 transient=0
    local exec_args=() exec_present=0 _shift=0 rc=0

    while (($# > 0)); do
        relay::notif::__parse_send_option "$@" || {
            rc=$?
            ((rc == 2)) && return "$RIG_EX_USAGE"
            break
        }
        shift "$_shift"
    done

    (($# >= 1)) || {
        relay::notif::__usage >&2
        return "$RIG_EX_USAGE"
    }
    summary=$1
    shift

    # The body is the next positional, taken as text even when it starts with a
    # dash — a body like "-3 dB" or "--force was ignored" is content, not an
    # option. Only a real flag in that slot means there is no body.
    if (($# > 0)) && ! relay::notif::__send_flag "$1"; then
        body=$1
        shift
    fi

    while (($# > 0)); do
        if [[ $1 == --exec ]]; then
            # --exec takes the rest of the line as the click command's argv.
            # The caller's shell already split those words for us and the
            # quickshell side runs them verbatim, so nothing is ever
            # re-parsed. Handled only here, after the positionals are taken,
            # so a summary that is literally "--exec" stays text.
            shift
            exec_args=("$@")
            exec_present=1
            break
        fi
        relay::notif::__parse_send_option "$@" || {
            rc=$?
            ((rc == 2)) && return "$RIG_EX_USAGE"
            rig::log::error "unknown option: $1"
            return "$RIG_EX_USAGE"
        }
        shift "$_shift"
    done

    local urgency_byte
    case $urgency in
        low) urgency_byte=0 ;;
        normal) urgency_byte=1 ;;
        critical) urgency_byte=2 ;;
        *)
            rig::log::error "unknown urgency '$urgency' (want low, normal, or critical)"
            return "$RIG_EX_USAGE"
            ;;
    esac

    # a{sv} hints as busctl triples: key, variant type, value.
    local hints=(urgency y "$urgency_byte")
    [[ -n $glyph ]] && hints+=(relay-glyph s "$glyph")
    [[ -n $image ]] && hints+=(image-path s "$image")
    ((transient)) && hints+=(transient b true)

    if ((exec_present)); then
        ((${#exec_args[@]})) && [[ -n ${exec_args[0]} ]] || {
            rig::log::error "--exec needs a command: --exec <program> [args...]"
            return "$RIG_EX_USAGE"
        }
        # One word containing a space is almost always a whole command passed
        # as a single quoted string, which would look for a program literally
        # named that. Splitting it here is exactly the injection this avoids,
        # so point at the unquoted form instead of guessing.
        if ((${#exec_args[@]} == 1)) && [[ ${exec_args[0]} == *[[:space:]]* ]]; then
            rig::log::error "--exec takes the command as separate words, not one quoted string."
            printf '  write:  --exec %s\n' "${exec_args[0]}" >&2
            return "$RIG_EX_USAGE"
        fi
        rig::check::require jq || return "$RIG_EX_NODEP"
        # NUL-delimited into jq so every byte survives as data: jq's own --args
        # would eat a bare "--", and a newline inside an argument must not
        # split the vector.
        local exec_json
        exec_json=$(printf '%s\0' "${exec_args[@]}" | jq -Rsc 'split("\u0000")[:-1]')
        hints+=(relay-exec-argv s "$exec_json")
    fi

    # No bus to talk to (headless, SSH, shell not running) — say it on stderr
    # rather than failing the command that asked for a notification.
    if ! rig::check::has busctl; then
        printf 'relay: %s%s\n' "$summary" "${body:+ — $body}" >&2
        return 0
    fi

    # Signature susssasa{sv}i: app_name, replaces_id, app_icon, summary, body,
    # actions (none), hints, expire_timeout. The leading `--` keeps a
    # dash-leading value (summary, body, a negative timeout) positional instead
    # of being read as a busctl option.
    local notify=(
        busctl --user -- call
        org.freedesktop.Notifications /org/freedesktop/Notifications
        org.freedesktop.Notifications Notify susssasa{sv}i
        "$app_name" "$replaces_id" "$app_icon" "$summary" "$body"
        0
        "$((${#hints[@]} / 3))" "${hints[@]}"
        "$expire_timeout"
    )

    local out
    if ! out=$("${notify[@]}" 2>/dev/null); then
        printf 'relay: %s%s\n' "$summary" "${body:+ — $body}" >&2
        return 0
    fi
    # busctl prints the UINT32 return as "u <id>"; emit just the id.
    ((print_id)) && printf '%s\n' "${out##* }"
    return 0
}

# ---- dnd / dismiss / invoke ---------------------------------------------------

relay::notif::dnd() {
    local action="" json=0 a
    for a in "$@"; do
        case $a in
            --json) json=1 ;;
            *) action=$a ;;
        esac
    done

    local state
    case $action in
        on) state=$(relay::notif::__ipc setDnd true) || return $? ;;
        off) state=$(relay::notif::__ipc setDnd false) || return $? ;;
        toggle) state=$(relay::notif::__ipc toggleDnd) || return $? ;;
        '' | status) state=$(relay::notif::__ipc dndState) || return $? ;;
        *)
            rig::log::error "unknown dnd action '$action' (want on, off, toggle, or status)"
            return "$RIG_EX_USAGE"
            ;;
    esac
    state=${state//[$'\r\n']/}
    if ((json)); then
        printf '{"dnd":%s}\n' "$([[ $state == on ]] && echo true || echo false)"
    else
        printf '%s\n' "$state"
    fi
}

relay::notif::dismiss() {
    local what=${1:-last}
    case $what in
        last) relay::notif::__ipc dismissLast >/dev/null ;;
        all) relay::notif::__ipc dismissAll >/dev/null ;;
        *)
            rig::log::error "unknown dismiss target '$what' (want last or all)"
            return "$RIG_EX_USAGE"
            ;;
    esac
}

relay::notif::invoke() { relay::notif::__ipc invokeLast >/dev/null; }

# What is on screen right now, oldest first. A row marked (restored) came back
# from disk after a shell restart: it still runs its --exec action, but its
# sender is gone, so it has no live action buttons.
relay::notif::list() {
    local json=0 a
    for a in "$@"; do
        [[ $a == --json ]] && json=1
    done

    local raw
    raw=$(relay::notif::__ipc popups) || return $?
    if ((json)) || ! rig::check::has jq; then
        printf '%s\n' "$raw"
        return 0
    fi
    printf '%s\n' "$raw" | jq -r '
        .[] | [
            .urgency,
            .appName,
            (.summary + (if .body == "" then "" else " — " + .body end)),
            (if .restored then "(restored)" else "" end)
        ] | @tsv
    ' | awk -F'\t' '{ printf "%-9s %-16s %s %s\n", $1, substr($2, 1, 16), $3, $4 }'
}

# ---- history -----------------------------------------------------------------

relay::notif::history() {
    local limit=20 json=0
    while (($# > 0)); do
        case $1 in
            --json)
                json=1
                shift
                ;;
            -n | --limit)
                [[ ${2-} =~ ^[0-9]+$ ]] || {
                    rig::log::error "--limit wants a number"
                    return "$RIG_EX_USAGE"
                }
                limit=$2
                shift 2
                ;;
            -n*)
                limit=${1#-n}
                shift
                ;;
            *)
                rig::log::error "unknown history option: $1"
                return "$RIG_EX_USAGE"
                ;;
        esac
    done

    local raw
    raw=$(relay::notif::__ipc history) || return $?
    rig::check::has jq || {
        printf '%s\n' "$raw"
        return 0
    }

    if ((json)); then
        printf '%s\n' "$raw" | jq --argjson n "$limit" '.[:$n]'
        return 0
    fi

    # Local time, newest first, one line each: HH:MM  app  summary — body
    printf '%s\n' "$raw" | jq -r --argjson n "$limit" '
        .[:$n][]
        | (.time / 1000 | strflocaltime("%H:%M")) as $t
        | [$t, .appName, (.summary + (if .body == "" then "" else " — " + .body end))]
        | @tsv
    ' | awk -F'\t' '{ printf "%-6s %-16s %s\n", $1, substr($2, 1, 16), $3 }'
}

# ---- wait --------------------------------------------------------------------

# The shell has to be up to serve IPC *and* to have claimed the bus name before
# a notification has anywhere to land. Both are checked: autostart order means
# an early `relay notif send` otherwise silently goes nowhere.
relay::notif::wait() {
    local timeout=${1:-10} attempts
    [[ $timeout =~ ^[0-9]+$ ]] || {
        rig::log::error "wait wants a timeout in seconds"
        return "$RIG_EX_USAGE"
    }
    attempts=$((timeout * 10))
    while ((attempts > 0)); do
        if qs -c "$RELAY_QS_CONFIG" ipc call notifications ping >/dev/null 2>&1 &&
            busctl --user call org.freedesktop.Notifications \
                /org/freedesktop/Notifications org.freedesktop.Notifications \
                GetServerInformation >/dev/null 2>&1; then
            return 0
        fi
        attempts=$((attempts - 1))
        sleep 0.1
    done
    return 1
}

relay::notif::__usage() {
    cat <<'EOF'
  relay notif send <summary> [body] [options]
  relay notif dnd [on|off|toggle|status]    no argument: print state
  relay notif dismiss [last|all]            default: last
  relay notif invoke                        run the newest popup's click action
  relay notif list                          popups currently on screen
  relay notif history [-n N]                recent notification history
  relay notif wait [seconds]                block until the daemon accepts

send options
  -u, --urgency <level>   low | normal | critical  (default: normal)
  -i, --icon <name|path>  themed icon name or absolute path
  -g, --glyph <char>      Nerd Font glyph, shown when there is no icon
      --image <path>      image/avatar to show instead of an icon
  -t, --expire-time <ms>  how long to show it (0 = until dismissed)
  -r, --replace-id <id>   update the notification with this id in place
  -p, --print-id          print the new notification's id on stdout
  -a, --app-name <name>   sender name (default: relay)
      --transient         popup only, keep it out of history
      --exec <cmd> [args] run this when the popup is clicked (must be last)

  --json   machine-readable output (dnd, history, list)

env
  RELAY_QS_CONFIG   which quickshell config answers IPC (default: main)

examples
  relay notif send "Theme updated" "regenerated from wall.png"
  relay notif send "Build failed" -u critical --exec foot -e journalctl -xe
  relay notif dnd toggle
EOF
}
