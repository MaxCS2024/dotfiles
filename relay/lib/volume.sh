# volume — PipeWire via wpctl, falling back to pactl.
#
# Clamped at RELAY_VOLUME_MAX because wpctl will happily take a sink to 300%
# and the first thing you learn about that is how loud it is.

rig::load log check proc
relay::load osd bar

RELAY_MODULE_SUMMARY[volume]="audio volume, mute, and bar status"
RELAY_MODULE_ACTIONS[volume]="up down set get mute muted status"
RELAY_MODULE_STATUS[volume]="ready"
RELAY_MODULE_TIER[volume]="core"

: "${RELAY_VOLUME_STEP:=5}"
: "${RELAY_VOLUME_MAX:=100}"

relay::volume::__backend() {
    if rig::check::has wpctl; then
        printf 'wpctl'
    elif rig::check::has pactl; then
        printf 'pactl'
    else
        rig::log::error "no wpctl or pactl — install wireplumber or libpulse"
        return "$RIG_EX_NODEP"
    fi
}

# "0.45" -> 45, in bash, without tripping over octal. Leading zeros are why
# 10# is here: $((045)) is an error, not forty-five.
relay::volume::__to_percent() {
    local raw=${1:-0} int frac
    if [[ $raw == *.* ]]; then
        int=${raw%%.*}
        frac=${raw#*.}
    else
        int=$raw
        frac=0
    fi
    frac="${frac}00"
    frac=${frac:0:2}
    printf '%s\n' "$((10#${int:-0} * 100 + 10#$frac))"
}

# Prints the current level as a whole-number percentage.
relay::volume::get() {
    local backend raw
    backend=$(relay::volume::__backend) || return $?

    case $backend in
        wpctl)
            # "Volume: 0.45" or "Volume: 0.45 [MUTED]"
            raw=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || {
                rig::log::error "wpctl could not read the default sink"
                return "$RIG_EX_FAIL"
            }
            raw=${raw#Volume: }
            raw=${raw%% *}
            relay::volume::__to_percent "$raw"
            ;;
        pactl)
            raw=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | head -n1) || return "$RIG_EX_FAIL"
            raw=${raw#*/ }
            raw=${raw%%%*}
            printf '%s\n' "${raw// /}"
            ;;
    esac
}

relay::volume::muted() {
    local backend
    backend=$(relay::volume::__backend) || return $?
    case $backend in
        wpctl) [[ $(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) == *MUTED* ]] ;;
        pactl) [[ $(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null) == *yes* ]] ;;
    esac
}

relay::volume::__apply() {
    local want=$1 backend
    backend=$(relay::volume::__backend) || return $?

    ((want < 0)) && want=0
    ((want > RELAY_VOLUME_MAX)) && want=$RELAY_VOLUME_MAX

    case $backend in
        wpctl) rig::proc::run wpctl set-volume @DEFAULT_AUDIO_SINK@ "${want}%" ;;
        pactl) rig::proc::run pactl set-sink-volume @DEFAULT_SINK@ "${want}%" ;;
    esac || return $?

    relay::osd::show volume "$want"
}

relay::volume::set() {
    local want=${1:-}
    [[ $want =~ ^[0-9]+$ ]] || {
        rig::log::error "set: want a whole number, got '${want}'"
        return "$RIG_EX_USAGE"
    }
    relay::volume::__apply "$want"
}

relay::volume::up() {
    local step=${1:-$RELAY_VOLUME_STEP} now
    now=$(relay::volume::get) || return $?
    relay::volume::__apply "$((now + step))"
}

relay::volume::down() {
    local step=${1:-$RELAY_VOLUME_STEP} now
    now=$(relay::volume::get) || return $?
    relay::volume::__apply "$((now - step))"
}

# Toggle, since that is what a mute key does.
relay::volume::mute() {
    local backend
    backend=$(relay::volume::__backend) || return $?
    case $backend in
        wpctl) rig::proc::run wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
        pactl) rig::proc::run pactl set-sink-mute @DEFAULT_SINK@ toggle ;;
    esac || return $?

    if relay::volume::muted; then
        relay::osd::text volume "Muted"
    else
        relay::osd::show volume "$(relay::volume::get)"
    fi
}

relay::volume::status() {
    local now
    now=$(relay::volume::get 2>/dev/null) || {
        relay::bar::error "no audio sink"
        return 0
    }
    if relay::volume::muted; then
        relay::bar::emit --text "muted" --class muted --percentage 0 \
            --tooltip "Volume ${now}% (muted)"
    else
        relay::bar::emit --text "${now}%" --class volume --percentage "$now" \
            --tooltip "Volume ${now}%"
    fi
}

relay::volume::__usage() {
    cat <<'EOF'
  relay volume up          relay vol up 10
  relay volume down
  relay volume mute                     toggles
  relay volume set 40
  relay volume get                      prints a number, nothing else
  relay volume status                   Waybar JSON

env
  RELAY_VOLUME_STEP   default 5
  RELAY_VOLUME_MAX    default 100 — the reason your ears still work
EOF
}
