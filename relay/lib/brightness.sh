# brightness — backlight via brightnessctl.
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

relay::brightness::__require() {
    rig::check::has brightnessctl || {
        rig::log::error "brightnessctl is not installed (pacman -S brightnessctl)"
        return "$RIG_EX_NODEP"
    }
}

# -m is the machine-readable form: name,class,current,percent,max
relay::brightness::get() {
    relay::brightness::__require || return $?
    local line percent
    line=$(brightnessctl -m 2>/dev/null | head -n1) || return "$RIG_EX_FAIL"
    IFS=, read -r _ _ _ percent _ <<<"$line"
    printf '%s\n' "${percent%\%}"
}

relay::brightness::devices() {
    relay::brightness::__require || return $?
    brightnessctl -lm
}

relay::brightness::__apply() {
    local want=$1
    relay::brightness::__require || return $?

    ((want < RELAY_BRIGHTNESS_MIN)) && want=$RELAY_BRIGHTNESS_MIN
    ((want > 100)) && want=100

    rig::proc::run brightnessctl -q set "${want}%" || return $?
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
  relay brightness devices              what brightnessctl can see

env
  RELAY_BRIGHTNESS_STEP   default 5
  RELAY_BRIGHTNESS_MIN    default 1 — never zero, on purpose
EOF
}
