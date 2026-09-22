# config — read values that rack writes. Read-only, on purpose.
#
# The contract that keeps the three tools pointed one way: rack owns writing,
# rig only ever reads. One writer, many readers, no merge logic, no locking,
# and a keybind script pays one grep rather than a config parser. If rack is
# not installed, every lookup falls back to its default instead of breaking.

rig::load log path

RIG_MODULE_SUMMARY[config]="read values written by rack"
RIG_MODULE_ACTIONS[config]="get has path list"
RIG_MODULE_STATUS[config]="ready"
RIG_MODULE_TIER[config]="core"

rig::config::path() {
    printf '%s/config\n' "$(rig::path::config rig)"
}

# get <key> [default] — never fails; an absent file is just an absent value.
rig::config::get() {
    local key=${1:-} fallback=${2:-} file value
    [[ -n $key ]] || {
        rig::log::error "config get: no key given"
        return "${RIG_EX_USAGE:-2}"
    }

    file=$(rig::config::path)
    [[ -r $file ]] || {
        printf '%s\n' "$fallback"
        return 0
    }

    # Last assignment wins, matching how the file is written. The `|| true`
    # matters: grep exits 1 on no match, which under `set -e` would abort the
    # caller instead of returning the default.
    value=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" -- "$file" 2>/dev/null | tail -n1 || true)
    if [[ -z $value ]]; then
        printf '%s\n' "$fallback"
        return 0
    fi

    value=${value#*=}
    # Trim surrounding space and one layer of quotes.
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    value=${value#\"}
    value=${value%\"}
    printf '%s\n' "$value"
}

rig::config::has() {
    local key=${1:-} file
    file=$(rig::config::path)
    [[ -r $file ]] || return 1
    grep -qE "^[[:space:]]*${key}[[:space:]]*=" -- "$file" 2>/dev/null
}

rig::config::list() {
    local file
    file=$(rig::config::path)
    [[ -r $file ]] || return 0
    grep -vE "^[[:space:]]*(#|$)" -- "$file" 2>/dev/null || true
}

rig::config::__usage() {
    cat <<'EOF'
  rig config get theme dark      the value, or the default
  rig config has theme
  rig config list
  rig config path                ~/.config/rig/config

Read-only. rack writes this file; nothing here ever does.
EOF
}
