# screenshot — grim and slurp, saved and on the clipboard.
#
# The lock matters more than it looks: Print is easy to hit twice, and two
# overlapping slurp overlays is a state you have to escape twice to leave.

rig::load log check proc lock tmp notify

RELAY_MODULE_SUMMARY[screenshot]="capture a region, window, output or screen"
RELAY_MODULE_ACTIONS[screenshot]="region window output full dir"
RELAY_MODULE_STATUS[screenshot]="ready"
RELAY_MODULE_TIER[screenshot]="core"

: "${RELAY_SCREENSHOT_EDITOR:=}" # satty or swappy; empty means auto-detect

relay::screenshot::dir() {
    local dir=${RELAY_SCREENSHOT_DIR:-}
    if [[ -z $dir ]]; then
        # Respect the user-dirs setting if there is one, rather than assuming
        # English directory names.
        if [[ -r ${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs ]]; then
            local pictures
            pictures=$(
                # shellcheck disable=SC1090
                source "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" 2>/dev/null
                printf '%s' "${XDG_PICTURES_DIR:-}"
            )
            [[ -n $pictures ]] && dir="$pictures/Screenshots"
        fi
    fi
    [[ -n $dir ]] || dir="$HOME/Pictures/Screenshots"
    mkdir -p -- "$dir" 2>/dev/null || {
        rig::log::error "cannot create $dir"
        return "$RIG_EX_FAIL"
    }
    printf '%s\n' "$dir"
}

relay::screenshot::__editor() {
    [[ -n $RELAY_SCREENSHOT_EDITOR ]] && {
        printf '%s' "$RELAY_SCREENSHOT_EDITOR"
        return 0
    }
    local candidate
    for candidate in satty swappy; do
        rig::check::has "$candidate" && {
            printf '%s' "$candidate"
            return 0
        }
    done
    return 1
}

relay::screenshot::__filename() {
    local dir
    dir=$(relay::screenshot::dir) || return $?
    printf '%s/%s.png\n' "$dir" "$(date +%Y-%m-%d_%H-%M-%S)"
}

# The shared path: capture into a temp file, then place it. Takes the grim
# arguments for whatever kind of capture this is.
relay::screenshot::__capture() {
    local kind=$1
    shift
    local -a grim_args=("$@")
    local edit=0 target shot

    rig::check::require grim

    # Options can arrive before or after the geometry, so scan what is left.
    local -a rest=()
    local arg
    for arg in "${grim_args[@]}"; do
        case $arg in
            --edit) edit=1 ;;
            *) rest+=("$arg") ;;
        esac
    done
    grim_args=("${rest[@]}")

    target=$(relay::screenshot::__filename) || return $?
    rig::tmp::file shot .png

    if ! rig::proc::run grim "${grim_args[@]}" "$shot"; then
        # slurp cancelled with Escape exits non-zero. That is a user deciding
        # not to, not a failure worth shouting about.
        rig::log::debug "capture cancelled or failed ($kind)"
        return "$RIG_EX_FAIL"
    fi

    if [[ ${RIG_DRY_RUN:-0} != 0 ]]; then
        rig::log::info "would save to $target"
        return 0
    fi

    if ((edit)); then
        local editor
        if editor=$(relay::screenshot::__editor); then
            case $editor in
                satty) rig::proc::run satty --filename "$shot" --output-filename "$target" ;;
                *) rig::proc::run swappy -f "$shot" -o "$target" ;;
            esac
            [[ -f $target ]] || return 0 # editor was cancelled
        else
            rig::log::warn "no satty or swappy installed; saving without editing"
            cp -- "$shot" "$target"
        fi
    else
        cp -- "$shot" "$target"
    fi

    rig::check::has wl-copy && wl-copy --type image/png <"$target"

    rig::notify::send -i "$target" -t 3000 \
        "Screenshot saved" "${target##*/}"
    printf '%s\n' "$target"
}

relay::screenshot::region() {
    rig::check::require slurp
    local geometry
    # Run slurp outside the lock-protected capture so a cancel releases early.
    geometry=$(slurp 2>/dev/null) || {
        rig::log::debug "region selection cancelled"
        return 0
    }
    rig::lock::run screenshot -- \
        relay::screenshot::__capture region -g "$geometry" "$@"
}

relay::screenshot::full() {
    rig::lock::run screenshot -- relay::screenshot::__capture full "$@"
}

# output [name] — defaults to the focused one.
relay::screenshot::output() {
    local name=${1:-}
    shift 2>/dev/null || true
    if [[ -z $name ]]; then
        relay::load hypr
        relay::hypr::running || {
            rig::log::error "output: no name given and Hyprland is not running"
            return "$RIG_EX_USAGE"
        }
        rig::check::require jq
        name=$(relay::hypr::monitors | jq -r '.[] | select(.focused) | .name')
    fi
    rig::lock::run screenshot -- relay::screenshot::__capture output -o "$name" "$@"
}

relay::screenshot::window() {
    relay::load hypr
    relay::hypr::running || {
        rig::log::error "window: Hyprland is not running"
        return "$RIG_EX_FAIL"
    }
    rig::check::require jq

    local geometry
    geometry=$(relay::hypr::active |
        jq -r 'if .at then "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])" else empty end')
    [[ -n $geometry ]] || {
        rig::log::error "window: nothing is focused"
        return "$RIG_EX_FAIL"
    }
    rig::lock::run screenshot -- \
        relay::screenshot::__capture window -g "$geometry" "$@"
}

relay::screenshot::__usage() {
    cat <<'EOF'
  relay screenshot region               slurp selection
  relay screenshot region --edit        straight into satty or swappy
  relay screenshot window               the focused window, via Hyprland
  relay screenshot output [name]        one monitor; defaults to the focused one
  relay screenshot full                 everything
  relay screenshot dir                  where they land

Saved, copied to the clipboard with wl-copy, and announced. Cancelling slurp
is not an error. Needs grim; slurp for regions, jq for window and output.

env
  RELAY_SCREENSHOT_DIR      default: XDG pictures dir + /Screenshots
  RELAY_SCREENSHOT_EDITOR   satty | swappy (auto-detected)
EOF
}
