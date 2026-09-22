# lock — one at a time, please.
#
# This is what stops a mashed keybind from spawning eight wallpaper changers.
# Locks live in the runtime directory, so they die with the session rather than
# surviving a crash as a stale file in /tmp.

rig::load log path

RIG_MODULE_SUMMARY[lock]="single-instance guards via flock"
RIG_MODULE_ACTIONS[lock]="acquire release run held path"
RIG_MODULE_STATUS[lock]="ready"
RIG_MODULE_TIER[lock]="core"

declare -gA RIG_LOCK_FD=()

rig::lock::path() {
    local name=${1:-}
    [[ -n $name ]] || {
        rig::log::error "lock: no name given"
        return "${RIG_EX_USAGE:-2}"
    }
    local dir
    dir=$(rig::path::runtime "rig/locks") || return $?
    printf '%s/%s.lock\n' "$dir" "${name//\//_}"
}

# acquire <name> [--wait [seconds]]
# Returns 1 when someone else holds it — deliberately quiet, because "another
# copy is already running" is a normal outcome for a keybind, not an error.
rig::lock::acquire() {
    local name=${1:-}
    shift || true
    local wait_for=""

    while (($#)); do
        case $1 in
            --wait)
                wait_for=${2:-0}
                [[ ${2:-} =~ ^[0-9]+$ ]] && shift
                ;;
            *) break ;;
        esac
        shift
    done

    local file fd
    file=$(rig::lock::path "$name") || return $?

    if [[ -n ${RIG_LOCK_FD[$name]:-} ]]; then
        rig::log::debug "lock: already holding $name"
        return 0
    fi

    exec {fd}<>"$file" || {
        rig::log::error "lock: cannot open $file"
        return "${RIG_EX_FAIL:-1}"
    }

    local -a args=()
    if [[ -z $wait_for ]]; then
        args=(-n)
    elif [[ $wait_for == 0 ]]; then
        args=()
    else
        args=(-w "$wait_for")
    fi

    if ! flock "${args[@]}" "$fd"; then
        exec {fd}>&-
        rig::log::debug "lock: $name is held by someone else"
        return "${RIG_EX_FAIL:-1}"
    fi

    RIG_LOCK_FD[$name]=$fd
    rig::log::debug "lock: acquired $name"
}

rig::lock::release() {
    local name=${1:-} fd=${RIG_LOCK_FD[${1:-}]:-}
    [[ -n $fd ]] || return 0
    flock -u "$fd" 2>/dev/null || true
    exec {fd}>&-
    unset "RIG_LOCK_FD[$name]"
}

rig::lock::held() { [[ -n ${RIG_LOCK_FD[${1:-}]:-} ]]; }

# run <name> [--wait [seconds]] [--] <command...>
# Exits 1 without running anything if the lock is taken.
rig::lock::run() {
    local name=${1:-}
    shift || true
    local -a acquire_args=()

    while (($#)); do
        case $1 in
            --wait)
                acquire_args+=(--wait)
                if [[ ${2:-} =~ ^[0-9]+$ ]]; then
                    acquire_args+=("$2")
                    shift
                fi
                ;;
            --)
                shift
                break
                ;;
            *) break ;;
        esac
        shift
    done

    (($#)) || {
        rig::log::error "lock run: no command given"
        return "${RIG_EX_USAGE:-2}"
    }

    rig::lock::acquire "$name" "${acquire_args[@]}" || return $?

    local status=0
    "$@" || status=$?
    rig::lock::release "$name"
    return "$status"
}

rig::lock::__usage() {
    cat <<'EOF'
  rig lock run wallpaper -- swww img next.png     skips if already running
  rig lock run sync --wait 5 -- rsync ...         waits up to 5s, then gives up
  rig::lock::acquire build || exit 0              quiet; 1 means someone else has it

Locks live in $XDG_RUNTIME_DIR/rig/locks and vanish with the session.
EOF
}
