# tmp — temporary files and directories that remove themselves.
#
# These take the NAME of a variable to assign, not a path to print:
#
#     rig::tmp::file shot .png     # not  shot=$(rig::tmp::file .png)
#
# because $(...) runs in a subshell. A function that both prints a path and
# registers its cleanup would register that cleanup in the subshell, fire it
# when the subshell exits, and hand back a path to a file it just deleted.
# Assigning to the caller's variable keeps both halves in one process.

rig::load log trap path

RIG_MODULE_SUMMARY[tmp]="temp files and dirs that clean themselves up"
RIG_MODULE_ACTIONS[tmp]="file dir keep"
RIG_MODULE_STATUS[tmp]="ready"
RIG_MODULE_TIER[tmp]="core"

rig::tmp::__base() {
    if [[ -n ${TMPDIR:-} && -d ${TMPDIR:-} ]]; then
        printf '%s\n' "${TMPDIR%/}"
    else
        rig::path::runtime "rig/tmp"
    fi
}

rig::tmp::__check_name() {
    [[ ${1:-} =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && return 0
    rig::log::error "tmp: '${1:-}' is not a variable name — pass a name, not \$(...)"
    return "${RIG_EX_USAGE:-2}"
}

# rig::tmp::file <varname> [suffix]
rig::tmp::file() {
    local __rig_var=${1:-} __rig_suffix=${2:-} __rig_base __rig_path
    rig::tmp::__check_name "$__rig_var" || return $?
    __rig_base=$(rig::tmp::__base) || return $?
    __rig_path=$(mktemp "$__rig_base/${RIG_TAG}.XXXXXXXX${__rig_suffix}") || {
        rig::log::error "tmp: cannot create a file in $__rig_base"
        return "${RIG_EX_FAIL:-1}"
    }
    rig::trap::add "rm -f -- '$__rig_path'"
    printf -v "$__rig_var" '%s' "$__rig_path"
}

# rig::tmp::dir <varname>
rig::tmp::dir() {
    local __rig_var=${1:-} __rig_base __rig_path
    rig::tmp::__check_name "$__rig_var" || return $?
    __rig_base=$(rig::tmp::__base) || return $?
    __rig_path=$(mktemp -d "$__rig_base/${RIG_TAG}.XXXXXXXX") || {
        rig::log::error "tmp: cannot create a directory in $__rig_base"
        return "${RIG_EX_FAIL:-1}"
    }
    rig::trap::add "rm -rf -- '$__rig_path'"
    printf -v "$__rig_var" '%s' "$__rig_path"
}

# Hand a temp path to something that outlives this script: drops its cleanup
# entry so it survives.
rig::tmp::keep() {
    local target=${1:-} i
    [[ -n $target ]] || {
        rig::log::error "tmp keep: no path given"
        return "${RIG_EX_USAGE:-2}"
    }
    for i in "${!RIG_CLEANUP_STACK[@]}"; do
        [[ ${RIG_CLEANUP_STACK[i]} == *"'$target'"* ]] && unset "RIG_CLEANUP_STACK[$i]"
    done
    RIG_CLEANUP_STACK=("${RIG_CLEANUP_STACK[@]}")
}

rig::tmp::__usage() {
    cat <<'EOF'
  rig::tmp::file shot .png       assigns $shot; removed however the script exits
  rig::tmp::dir work             assigns $work
  rig::tmp::keep "$shot"         let this one survive

Takes a variable NAME, not $(...) — see the comment at the top of tmp.sh.
Sourced only: cleanup is tied to the calling script's exit.
EOF
}
