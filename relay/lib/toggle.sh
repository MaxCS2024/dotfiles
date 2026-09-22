# toggle — flip a desktop switch (the bar, do-not-disturb, ...) on or off.
#
# One verb for every "get this out of my way" switch. Each subject here is
# shell state rather than a file on disk or a property on the bus, so every one
# of them is a single `qs ipc call` into the running quickshell — which is also
# the constraint on adding more: a subject can only appear below once the shell
# exposes a handler for it (services/Panels.qml, services/Notifications.qml,
# services/Settings.qml). Given that, adding one is a row in RELAY_TOGGLE_SUBJECTS
# and a two-line wrapper.
#
# The subjects do not all persist, and that is deliberate rather than an
# oversight to tidy up later. The bar's switch is runtime-only: it means "not
# for the next few minutes", not "I don't want a bar", so a shell restart
# brings it back, and the saved per-monitor answer to whether a bar exists at
# all is a different setting this command never touches (see Panels.barVisible's
# own comment). dnd, nightlight and awake are the opposite — real saved
# settings, so flipping one here outlives the session exactly as flipping it in
# the UI does. `status` is the way to ask which state you are actually in.
#
# `relay toggle dnd` and `relay notif dnd` are the same switch reached twice:
# this one so that every toggle is findable under one verb, that one so it sits
# with the rest of the notification controls.
#
# Ported from bin/orbit-toggle. Under relay's grammar each subject is an
# action — `relay toggle bar off` — so the subject table drives one wrapper per
# subject rather than a dispatch loop.

rig::load log check

RELAY_MODULE_SUMMARY[toggle]="flip a desktop switch on or off"
RELAY_MODULE_ACTIONS[toggle]="bar dnd nightlight awake"
RELAY_MODULE_STATUS[toggle]="ready"
RELAY_MODULE_TIER[toggle]="core"

: "${RELAY_QS_CONFIG:=main}"

# subject -> "<ipc target>|<flip>|<on>|<off>|<state>"
#
# The four function fields are whole argv vectors, not bare names: dnd's setter
# takes its value as an argument and the bar's does not. Every one of them has
# to answer "on" or "off" — that uniformity is what lets this stay a table.
declare -gA RELAY_TOGGLE_SUBJECTS=(
    [bar]='bar|toggle|open|close|state'
    [dnd]='notifications|toggleDnd|setDnd true|setDnd false|dndState'
    [nightlight]='nightlight|toggle|enable|disable|state'
    [awake]='awake|toggle|enable|disable|state'
)

relay::toggle::__ipc() {
    local target=$1
    shift
    rig::check::has qs || {
        rig::log::error "quickshell (qs) not found"
        return "$RIG_EX_NODEP"
    }
    qs -c "$RELAY_QS_CONFIG" ipc call "$target" "$@" 2>/dev/null || {
        rig::log::error "quickshell config '$RELAY_QS_CONFIG' is not running (or has no '$target' IPC)"
        return "$RIG_EX_FAIL"
    }
}

# The whole of every subject below: pick the argv for the requested action,
# call it, and insist on an on/off answer.
relay::toggle::__flip() {
    local subject=$1 json=0 action=""
    shift

    # Positionals are counted rather than just read: `relay toggle bar on off`
    # is a typo with two plausible readings, and silently obeying one of them
    # is how a script ends up doing the opposite of what it says.
    local a
    for a in "$@"; do
        case $a in
            --json) json=1 ;;
            -*)
                rig::log::error "unknown option '$a' (see: relay help toggle)"
                return "$RIG_EX_USAGE"
                ;;
            *)
                [[ -z $action ]] || {
                    rig::log::error "unexpected argument '$a' (see: relay help toggle)"
                    return "$RIG_EX_USAGE"
                }
                action=$a
                ;;
        esac
    done

    local target flip on off query
    IFS='|' read -r target flip on off query <<<"${RELAY_TOGGLE_SUBJECTS[$subject]}"

    # read -ra rather than an unquoted expansion: the vectors above are ours,
    # not user input, but splitting them explicitly keeps the call site quoted
    # and means a subject whose argument ever contains a space still works.
    local -a call
    case $action in
        '' | toggle) read -ra call <<<"$flip" ;;
        on) read -ra call <<<"$on" ;;
        off) read -ra call <<<"$off" ;;
        status) read -ra call <<<"$query" ;;
        *)
            rig::log::error "unknown action '$action' (want on, off, status, or nothing to flip)"
            return "$RIG_EX_USAGE"
            ;;
    esac

    local state
    state=$(relay::toggle::__ipc "$target" "${call[@]}") || return $?
    state=${state//[$'\r\n']/}

    # A handler that exists but predates this command answers with an empty
    # line rather than a state (its functions still return void). Saying so
    # beats printing nothing and exiting 0 as though the toggle had worked.
    case $state in
        on | off) ;;
        *)
            rig::log::error "'$target' answered '$state', not on/off — is the running shell older than this command?"
            return "$RIG_EX_FAIL"
            ;;
    esac

    if ((json)); then
        printf '{"%s":%s}\n' "$subject" "$([[ $state == on ]] && printf true || printf false)"
    else
        printf '%s\n' "$state"
    fi
}

relay::toggle::bar() { relay::toggle::__flip bar "$@"; }
relay::toggle::dnd() { relay::toggle::__flip dnd "$@"; }
relay::toggle::nightlight() { relay::toggle::__flip nightlight "$@"; }
relay::toggle::awake() { relay::toggle::__flip awake "$@"; }

# Names worth answering with a pointer rather than relay's bare "no action".
# `idle` is the one that matters: omarchy calls this switch that, and so does
# half the muscle memory, but the two names are opposites — this shell's switch
# is stayAwake, so `awake on` and `idle off` would be the same request. Rather
# than pick one polarity and let the other be scripted backwards, only the
# unambiguous name exists and the other explains itself. Deliberately absent
# from RELAY_MODULE_ACTIONS: they are errors with directions, not actions.
relay::toggle::__suggest() {
    rig::log::error "no subject '$1' — you want: $2"
    return "$RIG_EX_USAGE"
}

relay::toggle::idle() {
    relay::toggle::__suggest idle 'awake (on = staying awake, i.e. no idling — the opposite polarity)'
}
relay::toggle::nightmode() { relay::toggle::__suggest nightmode 'nightlight'; }
relay::toggle::coffee() { relay::toggle::__suggest coffee 'awake'; }
relay::toggle::notifications() { relay::toggle::__suggest notifications 'dnd'; }

relay::toggle::__usage() {
    cat <<'EOF'
  relay toggle <subject> [on|off|status]

subjects
  bar         the bar, on every monitor at once (until the shell restarts)
  dnd         do not disturb (same switch as: relay notif dnd)
  nightlight  the warm screen filter (hyprsunset)
  awake       keep the screen awake — on means no idling or locking

With no on/off/status the subject flips, which is the point of the command.
Either way the resulting state is printed: on or off. `status` asks without
changing anything.

bar is forgotten when the shell restarts; the rest are saved settings and
persist.

options
  --json    print {"<subject>":true|false} instead of on/off

env
  RELAY_QS_CONFIG   which quickshell config answers IPC (default: main)

examples
  relay toggle bar
  relay toggle bar off
  relay toggle nightlight
  relay toggle awake status
EOF
}
