# osd — the volume/brightness bar that replaces itself instead of stacking.
#
# This is why notify split across two programs: rig::notify::send is generic
# freedesktop, but the synchronous hint, the progress bar and the icon choice
# are presentation policy, and policy belongs here.

rig::load notify check log proc

RELAY_MODULE_SUMMARY[osd]="on-screen display that replaces itself"
RELAY_MODULE_ACTIONS[osd]="show text available"
RELAY_MODULE_STATUS[osd]="ready"
RELAY_MODULE_TIER[osd]="core"

: "${RELAY_OSD_TIMEOUT:=1200}"

relay::osd::available() { rig::notify::available; }

# The hint that makes dunst and mako replace the previous notification rather
# than queue another one. Keyed per kind, so volume and brightness do not
# fight over the same slot.
relay::osd::__sync_hint() {
    printf 'string:x-canonical-private-synchronous:relay-%s' "${1:-osd}"
}

# show <kind> <value> [--icon NAME] [--label TEXT]
#   relay osd show volume 45
relay::osd::show() {
    local kind=${1:-osd} value=${2:-}
    (($#)) && shift
    (($#)) && shift
    local icon="" label=""

    while (($#)); do
        case $1 in
            -i | --icon)
                icon=${2:-}
                shift 2
                ;;
            -l | --label)
                label=${2:-}
                shift 2
                ;;
            *)
                rig::log::error "osd show: unknown option: $1"
                return "$RIG_EX_USAGE"
                ;;
        esac
    done

    [[ $value =~ ^[0-9]+$ ]] || {
        rig::log::error "osd show: value must be a whole number, got '${value}'"
        return "$RIG_EX_USAGE"
    }

    [[ -n $label ]] || label="${kind^} ${value}%"
    [[ -n $icon ]] || icon=$(relay::osd::__icon_for "$kind" "$value")

    if ! relay::osd::available; then
        rig::log::info "$label"
        return 0
    fi

    rig::proc::run notify-send \
        -a relay \
        -u low \
        -t "$RELAY_OSD_TIMEOUT" \
        -i "$icon" \
        -h "$(relay::osd::__sync_hint "$kind")" \
        -h "int:value:$value" \
        -- "$label" ""
}

# Freedesktop icon names, so this works with whatever icon theme is set
# rather than hardcoding paths into a theme that might not be installed.
relay::osd::__icon_for() {
    local kind=$1 value=$2
    case $kind in
        volume)
            if ((value == 0)); then
                printf 'audio-volume-muted'
            elif ((value < 34)); then
                printf 'audio-volume-low'
            elif ((value < 67)); then
                printf 'audio-volume-medium'
            else
                printf 'audio-volume-high'
            fi
            ;;
        brightness)
            if ((value < 34)); then
                printf 'display-brightness-low'
            elif ((value < 67)); then
                printf 'display-brightness-medium'
            else
                printf 'display-brightness-high'
            fi
            ;;
        *) printf 'dialog-information' ;;
    esac
}

# Same replace-in-place behaviour, for a message with no percentage.
relay::osd::text() {
    local kind=${1:-osd} summary=${2:-} body=${3:-}
    [[ -n $summary ]] || {
        rig::log::error "osd text: no summary given"
        return "$RIG_EX_USAGE"
    }

    if ! relay::osd::available; then
        rig::log::info "${summary}${body:+ — $body}"
        return 0
    fi

    rig::proc::run notify-send \
        -a relay -u low -t "$RELAY_OSD_TIMEOUT" \
        -h "$(relay::osd::__sync_hint "$kind")" \
        -- "$summary" "$body"
}

relay::osd::__usage() {
    cat <<'EOF'
  relay osd show volume 45
  relay osd show brightness 80 --label "Screen 80%"
  relay osd text mute "Muted"

Uses the x-canonical-private-synchronous hint, so repeated presses replace the
notification instead of stacking it. Keyed per kind. Falls back to rig log
when there is no notification daemon.

env
  RELAY_OSD_TIMEOUT   milliseconds (default 1200)
EOF
}
