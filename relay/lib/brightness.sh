# brightness — backlight via sysfs and systemd-logind.
#
# Reads come straight from /sys/class/backlight. Writes go through logind's
# Session.SetBrightness: the sysfs file is root's, and logind lets the user at
# the seat write it without the `video` group. That is the call brightnessctl
# made, so it is one package fewer for the same write. The shell does the
# same in quickshell/main/services/Brightness.qml.
#
# The floor is 1%, not 0. A screen at zero is a screen you cannot see to fix,
# and the keybind that got you there is now invisible too.

rig::load log check proc
relay::load osd bar

RELAY_MODULE_SUMMARY[brightness]="screen backlight and bar status"
RELAY_MODULE_ACTIONS[brightness]="up down set get status devices"
RELAY_MODULE_STATUS[brightness]="ready"
RELAY_MODULE_TIER[brightness]="core"

: "${RELAY_BRIGHTNESS_STEP:=5}"
: "${RELAY_BRIGHTNESS_MIN:=1}"
: "${RELAY_BRIGHTNESS_SYSFS:=/sys/class/backlight}"

# The first backlight device, as brightnessctl picked it: its name.
relay::brightness::__device() {
    local d
    for d in "$RELAY_BRIGHTNESS_SYSFS"/*; do
        [[ -r $d/brightness && -r $d/max_brightness ]] || continue
        printf '%s\n' "${d##*/}"
        return 0
    done
    rig::log::error "no backlight device in $RELAY_BRIGHTNESS_SYSFS"
    return "$RIG_EX_FAIL"
}

# Prints "current max" for one device, raw.
relay::brightness::__read() {
    local dir=$RELAY_BRIGHTNESS_SYSFS/$1 cur max
    read -r cur <"$dir/brightness" && read -r max <"$dir/max_brightness" || return "$RIG_EX_FAIL"
    ((max > 0)) || return "$RIG_EX_FAIL"
    printf '%s %s\n' "$cur" "$max"
}

# Rounded, the way brightnessctl -m printed it.
relay::brightness::get() {
    local dev cur max
    dev=$(relay::brightness::__device) || return $?
    read -r cur max < <(relay::brightness::__read "$dev") || return "$RIG_EX_FAIL"
    printf '%s\n' "$(((cur * 100 + max / 2) / max))"
}

# name,class,current,percent,max — brightnessctl -lm's columns.
relay::brightness::devices() {
    local d cur max
    for d in "$RELAY_BRIGHTNESS_SYSFS"/*; do
        [[ -e $d ]] || continue
        read -r cur max < <(relay::brightness::__read "${d##*/}") || continue
        printf '%s,backlight,%s,%s%%,%s\n' "${d##*/}" "$cur" "$(((cur * 100 + max / 2) / max))" "$max"
    done
}

relay::brightness::__apply() {
    local want=$1 dev cur max
    rig::check::has busctl || {
        rig::log::error "busctl is not installed (it comes with systemd)"
        return "$RIG_EX_NODEP"
    }
    dev=$(relay::brightness::__device) || return $?
    read -r cur max < <(relay::brightness::__read "$dev") || return "$RIG_EX_FAIL"

    ((want < RELAY_BRIGHTNESS_MIN)) && want=$RELAY_BRIGHTNESS_MIN
    ((want > 100)) && want=100

    rig::proc::run busctl call org.freedesktop.login1 \
        /org/freedesktop/login1/session/auto org.freedesktop.login1.Session \
        SetBrightness ssu backlight "$dev" "$(((max * want + 50) / 100))" || return $?
    relay::osd::show brightness "$want"
}

relay::brightness::set() {
    local want=${1:-}
    [[ $want =~ ^[0-9]+$ ]] || {
        rig::log::error "set: want a whole number, got '${want}'"
        return "$RIG_EX_USAGE"
    }
    relay::brightness::__apply "$want"
}

relay::brightness::up() {
    local step=${1:-$RELAY_BRIGHTNESS_STEP} now
    now=$(relay::brightness::get) || return $?
    relay::brightness::__apply "$((now + step))"
}

relay::brightness::down() {
    local step=${1:-$RELAY_BRIGHTNESS_STEP} now
    now=$(relay::brightness::get) || return $?
    relay::brightness::__apply "$((now - step))"
}

relay::brightness::status() {
    local now
    now=$(relay::brightness::get 2>/dev/null) || {
        relay::bar::error "no backlight device"
        return 0
    }
    relay::bar::emit --text "${now}%" --class brightness --percentage "$now" \
        --tooltip "Brightness ${now}%"
}

relay::brightness::__usage() {
    cat <<'EOF'
  relay brightness up          relay bright up 10
  relay brightness down
  relay brightness set 60
  relay brightness get                  prints a number, nothing else
  relay brightness status               Waybar JSON
  relay brightness devices              every backlight device, raw and %

env
  RELAY_BRIGHTNESS_STEP   default 5
  RELAY_BRIGHTNESS_MIN    default 1 — never zero, on purpose
EOF
}
