# log — leveled messages to stderr, and to the journal when there is no terminal.
#
# A script launched from a keybind has no terminal, so stderr goes nowhere and
# every log line you wrote is unreadable exactly when something has broken.
# When stderr is not a tty we also hand the message to syslog, which makes
# `journalctl -t <script> -f` the debugging story.

RIG_MODULE_SUMMARY[log]="leveled messages to stderr and the journal"
RIG_MODULE_ACTIONS[log]="debug info success warn error die fatal level tag color_enabled"
RIG_MODULE_STATUS[log]="ready"
RIG_MODULE_TIER[log]="core"

# Tag on journal entries. Defaults to the name of the running script, which is
# what makes per-script filtering work without any script opting in.
: "${RIG_TAG:=$(basename -- "${0:-rig}")}"
: "${RIG_LOG_LEVEL:=info}"
: "${RIG_LOG_JOURNAL:=auto}" # auto | always | never
: "${RIG_COLOR:=auto}"       # auto | always | never

declare -gA RIG_LOG_WEIGHT=(
    [debug]=10 [info]=20 [success]=25 [warn]=30 [error]=40 [fatal]=50
)
declare -gA RIG_LOG_SYSLOG=(
    [debug]=debug [info]=info [success]=notice [warn]=warning [error]=err [fatal]=crit
)

rig::log::__colorize() {
    [[ $RIG_COLOR == never || -n ${NO_COLOR:-} ]] && return 1
    [[ $RIG_COLOR == always ]] && return 0
    [[ -t 2 ]]
}

# Public form of the predicate above, for a caller that paints its own output
# rather than going through rig::log — `rack update` draws a staged report and
# has to make the same auto/always/never decision this does.
rig::log::color_enabled() { rig::log::__colorize; }

rig::log::__color_for() {
    case $1 in
        debug) printf '\033[2;37m' ;;
        info) printf '\033[34m' ;;
        success) printf '\033[32m' ;;
        warn) printf '\033[33m' ;;
        error | fatal) printf '\033[31m' ;;
    esac
}

rig::log::__emit() {
    local level=$1
    shift
    local msg="$*"

    local want=${RIG_LOG_WEIGHT[${RIG_LOG_LEVEL,,}]:-20}
    local have=${RIG_LOG_WEIGHT[$level]:-20}
    ((have < want)) && return 0

    # Syslog first: if stderr is a dead end, this is the copy that survives.
    if [[ $RIG_LOG_JOURNAL == always ]] ||
        { [[ $RIG_LOG_JOURNAL == auto && ! -t 2 ]] && command -v logger >/dev/null 2>&1; }; then
        logger -t "$RIG_TAG" -p "user.${RIG_LOG_SYSLOG[$level]}" -- "$msg" 2>/dev/null || true
    fi

    if rig::log::__colorize; then
        printf '%b%-7s\033[0m %s\n' "$(rig::log::__color_for "$level")" "$level" "$msg" >&2
    else
        printf '%-7s %s\n' "$level" "$msg" >&2
    fi
}

rig::log::debug() { rig::log::__emit debug "$@"; }
rig::log::info() { rig::log::__emit info "$@"; }
rig::log::success() { rig::log::__emit success "$@"; }
rig::log::warn() { rig::log::__emit warn "$@"; }
rig::log::error() { rig::log::__emit error "$@"; }

# Stop with a message. Exits 1 — or returns, if we are sourced into someone's
# interactive shell, where exiting would close their terminal.
rig::log::die() {
    rig::log::__emit fatal "$@"
    [[ $- == *i* ]] && return "${RIG_EX_FAIL:-1}"
    exit "${RIG_EX_FAIL:-1}"
}

# Same, with a chosen exit code: rig::log::fatal 127 "no jq"
rig::log::fatal() {
    local code=$1
    shift
    rig::log::__emit fatal "$@"
    [[ $- == *i* ]] && return "$code"
    exit "$code"
}

# Read or set the threshold at runtime.
rig::log::level() {
    if (($# == 0)); then
        printf '%s\n' "$RIG_LOG_LEVEL"
    else
        [[ -n ${RIG_LOG_WEIGHT[${1,,}]:-} ]] || {
            rig::log::error "unknown level: $1"
            return "${RIG_EX_USAGE:-2}"
        }
        RIG_LOG_LEVEL=${1,,}
    fi
}

rig::log::tag() {
    if (($# == 0)); then printf '%s\n' "$RIG_TAG"; else RIG_TAG=$1; fi
}

rig::log::__usage() {
    cat <<'EOF'
  rig log info "starting"          debug info success warn error
  rig log die "no display"         exits 1
  rig log fatal 127 "missing jq"   exits with a chosen code

env
  RIG_LOG_LEVEL    debug|info|success|warn|error   (default: info)
  RIG_LOG_JOURNAL  auto|always|never               (default: auto, i.e. when not a tty)
  RIG_TAG          journal tag                     (default: script name)
  RIG_COLOR        auto|always|never  — NO_COLOR is honoured
EOF
}
