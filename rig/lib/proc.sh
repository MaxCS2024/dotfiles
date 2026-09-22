# proc — is it running, and run it (or don't).
#
# rig::proc::run is the choke point for RIG_DRY_RUN. It only works if scripts
# actually go through it, which is why it exists before anything needs it:
# retrofitting a dry-run flag once forty scripts call things directly is not
# a refactor, it is an archaeology project.

rig::load log

RIG_MODULE_SUMMARY[proc]="process checks and dry-run aware execution"
RIG_MODULE_ACTIONS[proc]="run running pid wait toggle kill"
RIG_MODULE_STATUS[proc]="ready"
RIG_MODULE_TIER[proc]="core"

: "${RIG_DRY_RUN:=0}"

# run [--] <command...>
# With RIG_DRY_RUN=1 it prints what it would have done and returns 0.
rig::proc::run() {
    [[ ${1:-} == -- ]] && shift
    (($#)) || {
        rig::log::error "run: no command given"
        return "${RIG_EX_USAGE:-2}"
    }

    if [[ $RIG_DRY_RUN != 0 ]]; then
        # %q so the printed line is actually re-runnable, quoting and all.
        printf 'would run:'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi

    "$@"
}

# Exact match by default: `pgrep waybar` also matches `waybar-wrapper`, which
# is the sort of thing that makes a toggle kill the wrong process.
rig::proc::running() { pgrep -x -u "$(id -u)" -- "${1:-}" >/dev/null 2>&1; }

rig::proc::pid() {
    local name=${1:-}
    [[ -n $name ]] || {
        rig::log::error "pid: no name given"
        return "${RIG_EX_USAGE:-2}"
    }
    pgrep -x -u "$(id -u)" -- "$name" | head -n1
}

# wait <name> [seconds] — until it appears, not until it exits.
rig::proc::wait() {
    local name=${1:-} timeout=${2:-5} waited=0
    while ((waited * 10 < timeout * 10)); do
        rig::proc::running "$name" && return 0
        sleep 0.1
        waited=$((waited + 1))
    done
    rig::proc::running "$name"
}

rig::proc::kill() {
    local name=${1:-} sig=${2:-TERM}
    rig::proc::running "$name" || return 0
    rig::proc::run pkill -"$sig" -x -u "$(id -u)" -- "$name"
}

# toggle <name> [--] <command to start it...>
# The start-or-kill that panels and launchers want from a single keybind.
rig::proc::toggle() {
    local name=${1:-}
    shift || true
    [[ ${1:-} == -- ]] && shift
    [[ -n $name ]] || {
        rig::log::error "toggle: no name given"
        return "${RIG_EX_USAGE:-2}"
    }

    if rig::proc::running "$name"; then
        rig::log::debug "toggle: stopping $name"
        rig::proc::kill "$name"
        return 0
    fi

    (($#)) || set -- "$name"
    rig::log::debug "toggle: starting $name"
    rig::proc::run "$@"
}

rig::proc::__usage() {
    cat <<'EOF'
  rig run -- swww img next.png        honours RIG_DRY_RUN=1
  rig proc running waybar             quiet; exact name match
  rig proc toggle waybar              start it, or kill it if it is up
  rig proc toggle rofi -- rofi -show drun
  rig proc wait swww-daemon 3         wait for it to appear

env
  RIG_DRY_RUN=1    print commands instead of running them
EOF
}
