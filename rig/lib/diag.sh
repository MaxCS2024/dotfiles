# diag — collect findings, report them, and offer the repairs that go with them.
#
# A subsystem command (net, bt, health, ...) defines two functions and gets
# status/doctor/fix for free:
#
#   <run_fn>     populates the finding list by calling rig::diag::add
#   <apply_fn>   performs one action string produced by rig::diag::add
#
# The contract that makes this predictable: fix only ever performs actions that
# <run_fn> attached to a finding, so doctor is always an accurate preview of
# what fix would do.
#
# Ported from bin/lib/checks.sh. The one change worth knowing about: orbit's
# version reached for globals named run_checks and apply_fix, so a file could
# only ever host one subsystem. Here they are passed in by name, which is what
# lets relay's net and bt modules live in the same process.

rig::load log check

RIG_MODULE_SUMMARY[diag]="findings, reporting, and the doctor/fix flow"
RIG_MODULE_ACTIONS[diag]="add print json failed reset status doctor fix"
RIG_MODULE_STATUS[diag]="ready"
RIG_MODULE_TIER[diag]="core"

declare -ga RIG_DIAG_NAME=()
declare -ga RIG_DIAG_STATUS=()
declare -ga RIG_DIAG_TEXT=()
declare -ga RIG_DIAG_FIX=()
declare -ga RIG_DIAG_DETAIL=()
RIG_DIAG_OVERALL=ok

# Name column width. The default fits the subsystem checks; a reporter with
# longer names (health) widens it rather than letting its own output wrap.
: "${RIG_DIAG_WIDTH:=11}"

# Set by a caller that was given --json. Human output then goes to stderr so
# stdout stays a single parseable document.
: "${RIG_DIAG_JSON:=0}"

rig::diag::reset() {
    RIG_DIAG_NAME=()
    RIG_DIAG_STATUS=()
    RIG_DIAG_TEXT=()
    RIG_DIAG_FIX=()
    RIG_DIAG_DETAIL=()
    RIG_DIAG_OVERALL=ok
}

# ok < info < warn < problem. Only 'problem' affects exit status, so a warning
# never makes a status command look like a failure to a script polling it, and
# `info` is for a state that is entirely normal but worth printing — pending
# updates being the case it was added for.
rig::diag::__escalate() {
    case "${1:-}" in
        problem) RIG_DIAG_OVERALL=problem ;;
        warn) [[ $RIG_DIAG_OVERALL == problem ]] || RIG_DIAG_OVERALL=warn ;;
        info) [[ $RIG_DIAG_OVERALL == ok ]] && RIG_DIAG_OVERALL=info ;;
    esac
    return 0
}

# rig::diag::add <name> <status> <text> [fix-action] [json-detail]
#
# Omit fix-action for anything that should not be repaired on its own — a
# hardware rfkill block, or a choice only the user can make. json-detail is a
# JSON value carried straight through to --json output for a reader that wants
# the numbers behind the sentence; omit it and the key is left out entirely,
# so a consumer of the plain shape never sees it appear.
rig::diag::add() {
    RIG_DIAG_NAME+=("$1")
    RIG_DIAG_STATUS+=("$2")
    RIG_DIAG_TEXT+=("$3")
    RIG_DIAG_FIX+=("${4:-}")
    RIG_DIAG_DETAIL+=("${5:-}")
    rig::diag::__escalate "$2"
}

rig::diag::print() {
    local i
    for i in "${!RIG_DIAG_NAME[@]}"; do
        printf '  %-*s %s\n' "$RIG_DIAG_WIDTH" "${RIG_DIAG_NAME[$i]}" "${RIG_DIAG_TEXT[$i]}"
    done
}

rig::diag::json() {
    rig::check::require jq || return "$RIG_EX_NODEP"
    local i
    for i in "${!RIG_DIAG_NAME[@]}"; do
        jq -nc --arg n "${RIG_DIAG_NAME[$i]}" --arg s "${RIG_DIAG_STATUS[$i]}" \
            --arg t "${RIG_DIAG_TEXT[$i]}" --arg f "${RIG_DIAG_FIX[$i]}" \
            --argjson d "${RIG_DIAG_DETAIL[$i]:-null}" \
            '{name: $n, status: $s, summary: $t, fixable: ($f != "")}
             + (if $d == null then {} else {detail: $d} end)'
    done | jq -sc --arg o "$RIG_DIAG_OVERALL" '{status: $o, checks: .}'
}

rig::diag::failed() { [[ $RIG_DIAG_OVERALL == problem ]]; }

# ---- shared subcommands ------------------------------------------------------

# rig::diag::status <label> <run_fn>
rig::diag::status() {
    local label=$1 run_fn=$2
    rig::diag::reset
    "$run_fn" || return $?

    if ((RIG_DIAG_JSON)); then
        rig::diag::json
    else
        printf '%s:\n' "$label"
        rig::diag::print
        printf '\n%s\n' "$RIG_DIAG_OVERALL"
    fi
    rig::diag::failed && return 1
    return 0
}

# rig::diag::doctor <label> <run_fn> <fix-command-to-suggest>
rig::diag::doctor() {
    local label=$1 run_fn=$2 fix_cmd=${3:-}
    rig::diag::reset
    "$run_fn" || return $?

    if ((RIG_DIAG_JSON)); then
        rig::diag::json
        rig::diag::failed && return 1
        return 0
    fi

    printf '%s diagnosis:\n' "$label"
    rig::diag::print

    local i fixable=0
    for i in "${!RIG_DIAG_FIX[@]}"; do
        [[ -n ${RIG_DIAG_FIX[$i]} ]] && fixable=1
    done

    if ((fixable)); then
        printf '\nsome of this is repairable — run: %s\n' "${fix_cmd:-fix}"
    elif rig::diag::failed; then
        printf '\nnothing here is safe to repair automatically.\n'
    fi

    rig::diag::failed && return 1
    return 0
}

# rig::diag::fix <run_fn> <apply_fn>
rig::diag::fix() {
    local run_fn=$1 apply_fn=$2
    rig::diag::reset
    "$run_fn" || return $?

    local i
    local -a actions=() reasons=()
    for i in "${!RIG_DIAG_FIX[@]}"; do
        [[ -n ${RIG_DIAG_FIX[$i]} ]] || continue
        actions+=("${RIG_DIAG_FIX[$i]}")
        reasons+=("${RIG_DIAG_TEXT[$i]}")
    done

    if ((${#actions[@]} == 0)); then
        if rig::diag::failed; then
            printf 'problems found, but none are safe to repair:\n'
            rig::diag::print
            return 1
        fi
        printf 'nothing to fix\n'
        return 0
    fi

    printf 'found %s repairable problem(s):\n' "${#actions[@]}"
    for i in "${!reasons[@]}"; do
        printf '  %s\n' "${reasons[$i]}"
    done

    if ((${RIG_DRY_RUN:-0})); then
        printf '\ndry run — would run:\n'
    else
        printf '\n'
        rig::check::confirm "apply these repairs?" || {
            printf 'nothing changed\n'
            return 0
        }
    fi

    for i in "${!actions[@]}"; do
        "$apply_fn" "${actions[$i]}"
    done

    ((${RIG_DRY_RUN:-0})) && return 0

    # Re-check rather than claiming success: a repair can succeed as a command
    # and still leave the subsystem broken.
    printf '\nre-checking...\n'
    rig::diag::reset
    "$run_fn"
    rig::diag::print
    printf '\n%s\n' "$RIG_DIAG_OVERALL"
    rig::diag::failed && return 1
    return 0
}

rig::diag::__usage() {
    cat <<'EOF'
  A library, not a command: sourced by the subsystem modules that report.

  rig::diag::add <name> <status> <text> [fix-action] [json-detail]
      status is ok | info | warn | problem
      omit fix-action for "do not touch"; omit json-detail to leave the key out

  rig::diag::status <label> <run_fn>
  rig::diag::doctor <label> <run_fn> <fix-command-to-suggest>
  rig::diag::fix    <run_fn> <apply_fn>

env
  RIG_DIAG_JSON=1   emit one JSON document instead of a human report
  RIG_DIAG_WIDTH    name column width in the human report (default 11)
  RIG_DRY_RUN=1     fix prints what it would run and changes nothing
  RIG_YES=1         fix skips the confirmation prompt
EOF
}
