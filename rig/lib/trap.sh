# trap — a cleanup stack, and strict mode that says where it died.
#
# bash's `trap` overwrites. The moment two pieces of code both want cleanup,
# one of them silently loses and you never find out. This keeps a stack and
# fires all of it, in reverse order, exactly once.

rig::load log

RIG_MODULE_SUMMARY[trap]="cleanup stack and strict mode"
RIG_MODULE_ACTIONS[trap]="add strict fire installed count"
RIG_MODULE_STATUS[trap]="ready"
RIG_MODULE_TIER[trap]="core"

declare -ga RIG_CLEANUP_STACK=()
RIG_TRAPS_INSTALLED=0
RIG_CLEANUP_FIRED=0

# The process that owns the stack. A trap set inside a subshell is live in that
# subshell, so without this a single `x=$(something)` could run the parent's
# cleanup early and delete files still in use. Only the owner fires.
RIG_TRAP_PID=$BASHPID

# Run everything on the stack, newest first, then forget it. Failures in one
# handler must not stop the rest — cleanup is the last chance to release things.
rig::trap::fire() {
    [[ $BASHPID == "$RIG_TRAP_PID" ]] || return 0
    ((RIG_CLEANUP_FIRED)) && return 0
    RIG_CLEANUP_FIRED=1

    local i had_errexit=0
    [[ $- == *e* ]] && had_errexit=1
    set +e

    for ((i = ${#RIG_CLEANUP_STACK[@]} - 1; i >= 0; i--)); do
        eval "${RIG_CLEANUP_STACK[i]}" 2>/dev/null
    done

    RIG_CLEANUP_STACK=()
    ((had_errexit)) && set -e
    return 0
}

rig::trap::__on_exit() {
    local status=$?
    rig::trap::fire
    return "$status"
}

# Clean up, then die the way we were asked to, so the parent shell sees the
# right signal rather than a plain exit.
rig::trap::__on_signal() {
    local sig=$1
    rig::trap::fire
    trap - "$sig"
    kill "-$sig" "$$"
}

# Not installed at load time: a library has no business putting an EXIT trap in
# an interactive shell that merely sourced it. First use arms it.
rig::trap::install() {
    ((RIG_TRAPS_INSTALLED)) && return 0
    RIG_TRAPS_INSTALLED=1
    trap 'rig::trap::__on_exit' EXIT
    trap 'rig::trap::__on_signal INT' INT
    trap 'rig::trap::__on_signal TERM' TERM
    trap 'rig::trap::__on_signal HUP' HUP
}

# rig::trap::add 'rm -f "$tmp"'
# Single-quote it: the command is evaluated when cleanup runs, not now.
rig::trap::add() {
    (($#)) || {
        rig::log::error "trap add: nothing to run"
        return "${RIG_EX_USAGE:-2}"
    }
    # A subshell gets its own copy of the array, so the entry would be silently
    # discarded when it exits. Almost always a $(...) that should not be one.
    if [[ $BASHPID != "$RIG_TRAP_PID" ]]; then
        rig::log::warn "trap add: called from a subshell; this cleanup will be lost"
    fi
    rig::trap::install
    RIG_CLEANUP_STACK+=("$*")
    RIG_CLEANUP_FIRED=0
}

rig::trap::count() { printf '%s\n' "${#RIG_CLEANUP_STACK[@]}"; }
rig::trap::installed() { ((RIG_TRAPS_INSTALLED)); }

# Without this, a script that dies on line 40 of a keybind produces nothing at
# all. The ERR trap is the whole point; set -e alone tells you nothing.
rig::trap::strict() {
    set -euo pipefail
    shopt -s inherit_errexit 2>/dev/null || true
    trap 'rig::trap::__on_err $? $LINENO "$BASH_COMMAND"' ERR
}

rig::trap::__on_err() {
    local status=$1 line=$2 cmd=$3
    local where=${BASH_SOURCE[1]:-${0}}
    rig::log::error "${where##*/}:${line}: exit ${status}: ${cmd}"
    return "$status"
}

rig::trap::__usage() {
    cat <<'EOF'
  rig::trap::strict                  set -euo pipefail plus a useful ERR trap
  rig::trap::add 'rm -f "$tmp"'      stacks; fires in reverse on EXIT INT TERM HUP

Only useful sourced — cleanup belongs to the calling script's lifetime.
EOF
}
