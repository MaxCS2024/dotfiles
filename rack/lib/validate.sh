# validate — catch the config error before it locks you out.
#
# The failure this prevents is specific: a syntax error in hyprland.conf that
# you find out about when the compositor will not come back. Checking before
# committing costs two seconds.
#
# Validators are keyed by manifest name, with a fallback by file extension.
# When nothing knows how to check something, it says so rather than pretending
# the check passed.

rig::load log check proc
rack::load manifest

RACK_MODULE_SUMMARY[validate]="syntax-check configs before deploying them"
RACK_MODULE_ACTIONS[validate]="run file known"
RACK_MODULE_STATUS[validate]="ready"
RACK_MODULE_TIER[validate]="core"

# Each returns 0 for fine, 1 for broken, 2 for "cannot check here".
rack::validate::__hypr() {
    rig::check::has hyprctl || return 2
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 2

    # Hyprland has no offline checker, so this asks the running compositor
    # what it thinks of its current config. Which means it is only meaningful
    # after a deploy, not before one — worth knowing.
    local errors
    errors=$(hyprctl configerrors 2>/dev/null) || return 2
    [[ -z $errors || $errors == *"no errors"* ]] && return 0
    printf '%s\n' "$errors"
    return 1
}

rack::validate::__nvim() {
    rig::check::has nvim || return 2
    local out
    out=$(nvim --headless -c 'quitall' 2>&1) || {
        printf '%s\n' "$out"
        return 1
    }
    [[ -n $out ]] && printf '%s\n' "$out"
    return 0
}

rack::validate::__waybar() {
    local source=$1 config="$1/config.jsonc"
    [[ -f $config ]] || config="$1/config"
    [[ -f $config ]] || return 2
    rig::check::has python3 || return 2

    # jsonc, so jq will not do: strip // comments first, crudely but enough
    # to catch the error that actually happens, which is a missing comma.
    python3 - "$config" <<'PY' || return 1
import json, re, sys
raw = open(sys.argv[1], encoding="utf-8").read()
raw = re.sub(r'^\s*//.*$', '', raw, flags=re.M)
try:
    json.loads(raw)
except json.JSONDecodeError as e:
    print(f"{e.msg} at line {e.lineno}, column {e.colno}")
    raise SystemExit(1)
PY
    return 0
}

rack::validate::__by_extension() {
    local path=$1 out
    case $path in
        *.sh | *.bash | .bashrc | .zshrc | .profile)
            rig::check::has bash || return 2
            out=$(bash -n -- "$path" 2>&1) || {
                printf '%s\n' "$out"
                return 1
            }
            return 0
            ;;
        *.lua)
            if rig::check::has luac; then
                out=$(luac -p -- "$path" 2>&1) || {
                    printf '%s\n' "$out"
                    return 1
                }
                return 0
            fi
            return 2
            ;;
        *.json)
            rig::check::has jq || return 2
            out=$(jq empty -- "$path" 2>&1) || {
                printf '%s\n' "$out"
                return 1
            }
            return 0
            ;;
        *) return 2 ;;
    esac
}

# Walk a directory's checkable files; a directory is fine if none are broken.
rack::validate::__directory() {
    local dir=$1 file status worst=2 out
    while IFS= read -r file; do
        out=$(rack::validate::__by_extension "$file")
        status=$?
        case $status in
            0) ((worst == 2)) && worst=0 ;;
            1)
                printf '    %s: %s\n' "${file#"$dir"/}" "${out:-invalid}"
                worst=1
                ;;
        esac
    done < <(find "$dir" -type f \( -name '*.sh' -o -name '*.lua' -o -name '*.json' \) \
        -not -path '*/.git/*' 2>/dev/null)
    return "$worst"
}

rack::validate::__one() {
    local name=$1 source=$2 out status

    case $name in
        hypr | hyprland)
            out=$(rack::validate::__hypr)
            status=$?
            ;;
        nvim | neovim)
            out=$(rack::validate::__nvim)
            status=$?
            ;;
        waybar)
            out=$(rack::validate::__waybar "$source")
            status=$?
            ;;
        *)
            if [[ -d $source ]]; then
                out=$(rack::validate::__directory "$source")
                status=$?
            else
                out=$(rack::validate::__by_extension "$source")
                status=$?
            fi
            ;;
    esac

    case $status in
        0) printf '  %-12s ok\n' "$name" ;;
        1)
            printf '  %-12s BROKEN\n' "$name"
            [[ -n $out ]] && printf '%s\n' "$out" | sed 's/^/    /'
            ;;
        *) printf '  %-12s no validator\n' "$name" ;;
    esac
    return "$status"
}

rack::validate::run() {
    local name source target reload entries broken=0

    # Selected up front: read through a process substitution, an unknown
    # name was logged and then "nothing obviously broken" reported with
    # success. deploy.sh has the same note.
    entries=$(rack::manifest::select "$@") || return $?

    while IFS=$'\t' read -r name source target reload; do
        [[ -n $name ]] || continue
        rack::validate::__one "$name" "$source" || [[ $? == 2 ]] || broken=$((broken + 1))
    done <<<"$entries"

    ((broken)) && {
        rig::log::error "$broken config(s) would not load"
        return "$RIG_EX_FAIL"
    }
    rig::log::success "nothing obviously broken"
}

# file <path> — check something that is not in the manifest yet.
rack::validate::file() {
    local path=${1:-} out status
    [[ -f $path ]] || {
        rig::log::error "no such file: $path"
        return "$RIG_EX_USAGE"
    }
    out=$(rack::validate::__by_extension "$path")
    status=$?
    case $status in
        0) rig::log::success "${path##*/} is fine" ;;
        1)
            rig::log::error "${path##*/}: ${out:-invalid}"
            return "$RIG_EX_FAIL"
            ;;
        *)
            rig::log::warn "no validator for ${path##*/}"
            return 0
            ;;
    esac
}

rack::validate::known() {
    cat <<'EOF'
  hypr      hyprctl configerrors (needs a running Hyprland)
  nvim      nvim --headless -c quitall
  waybar    config.jsonc parses as JSON once // comments are stripped
  *.sh      bash -n
  *.lua     luac -p, when luac is installed
  *.json    jq empty
EOF
}

rack::validate::__default() { rack::validate::run "$@"; }

rack::validate::__usage() {
    cat <<'EOF'
  rack validate              everything in the manifest
  rack validate hypr nvim
  rack validate file ~/.zshrc
  rack validate known        what can actually be checked

"no validator" means exactly that — not that the config is fine. The hypr
check asks the running compositor, so it is only meaningful after a deploy.
EOF
}
