#!/usr/bin/env bash
# Shows everything that can pop up on screen, one after another:
#
#   pill           the notices the island's pill flashes, through the
#                  `island-notices` IPC target (Controls.qml)
#   notifications  regular notifications, through dunst, sent the way
#                  their real senders do (AGENTS.md, Notifications)
#
# Both when no part is named. Nothing on the system changes.
#
# Pill: close any open panel first; the island skips notices while one is
# open, or while the pill is being dragged. The battery notices read the
# real charge, so they show today's percentage, not the label's N.
#
# Notifications: the critical ones stay until dismissed, so the script
# closes them itself at the end, and on Ctrl+C.
set -euo pipefail

usage() {
    echo "usage: ${0##*/} [pill|notifications]" >&2
    exit 2
}

parts=("$@")
((${#parts[@]})) || parts=(pill notifications)
for part in "${parts[@]}"; do
    [[ $part == pill || $part == notifications ]] || usage
done

# ── Pill ──

# Each notice stays 3 seconds (the layout 1.5); the extra half second
# lets the pill fade back to the time between them.
show() {
    local wait=$1 label=$2
    shift 2
    printf '%s\n' "$label"
    qs -c dynamic-island ipc call island-notices "$@"
    sleep "$wait"
}

pill() {
    local wifi=$'\U0000f1eb'
    local wifi_off=$'\U000f05aa'
    local ethernet=$'\U000f0200'
    local headset=$'\U000f02cb'
    local mouse=$'\U000f037d'
    local keyboard=$'\U000f030c'
    local gamepad=$'\U000f0297'
    local phone=$'\U000f011c'
    local rune=$'\U000f00af'

    echo "Pill › Battery"
    show 3.5 "  Low battery – N%"           battery low
    # Critical also sends its dunst notification (Alerts.qml); the
    # charging notice after it takes that back.
    show 3.5 "  Battery critical – N% (and its notification)" battery critical
    show 3.5 "  Charging – N% (closes it)"  battery charging

    echo "Pill › Display"
    show 3.5 "  Display connected – XV280K" display "XV280K"

    echo "Pill › Layout"
    show 2   "  Layout – English (US)"      layout "English (US)"
    show 2   "  Layout – Swedish"           layout "Swedish"
    show 2   "  Caps Lock – on"             caps true
    show 2   "  Caps Lock – off"            caps false

    echo "Pill › Network"
    show 3.5 "  Connected – Telia-3D6C57"   notice "$wifi" "Connected – " "Telia-3D6C57" ""
    show 3.5 "  Connected – Ethernet"       notice "$ethernet" "Connected – Ethernet" "" ""
    show 3.5 "  Wi-Fi lost"                 notice "$wifi_off" "Wi-Fi lost" "" ""
    show 3.5 "  Couldn't connect – Telia-3D6C57" \
        notice "$wifi_off" "Couldn't connect – " "Telia-3D6C57" ""

    echo "Pill › Bluetooth"
    show 3.5 "  Headset, with battery"      notice "$headset" "" "Nothing Ear (3)" " connected – 80%"
    show 3.5 "  Headset, no battery"        notice "$headset" "" "Nothing Ear (3)" " connected"
    show 3.5 "  Headset disconnected"       notice "$headset" "" "Nothing Ear (3)" " disconnected"
    show 3.5 "  Mouse"                      notice "$mouse" "" "MX Master 3S" " connected – 65%"
    show 3.5 "  Keyboard"                   notice "$keyboard" "" "Keychron K2" " connected"
    show 3.5 "  Gamepad"                    notice "$gamepad" "" "Xbox Wireless Controller" " connected"
    show 3.5 "  Phone"                      notice "$phone" "" "Pixel 9" " connected"
    show 3.5 "  Unknown device (rune)"      notice "$rune" "" "BT-Speaker" " disconnected"

    # Long names, cut with "…" to keep the pill within 400px: a
    # 31-character SSID (Wi-Fi allows 32), a long Bluetooth name and a
    # monitor reporting its full model name.
    echo "Pill › Long names"
    show 3.5 "  Long SSID, connected"       notice "$wifi" "Connected – " "Telia-3D6C57-5GHz-Guest-Network" ""
    show 3.5 "  Long SSID, couldn't connect" \
        notice "$wifi_off" "Couldn't connect – " "Telia-3D6C57-5GHz-Guest-Network" ""
    show 3.5 "  Long Bluetooth name"        notice "$headset" "" "Sony WH-1000XM5 Wireless Noise Cancelling" " connected – 80%"
    show 3.5 "  Long display name"          display "Dell UltraSharp U2723QE 27in"

    # Dictation isn't a flash: the face stays until the state goes back
    # to voxtype's own. The bars follow the real microphone, but nothing
    # is recorded or typed. Don't click its buttons: they drive the real
    # voxtype (stop would start a recording).
    show 3   "  Dictation, recording"       dictation recording
    show 3   "  Dictation, transcribing"    dictation transcribing
    show 1   "  Dictation over"             dictation ""
}

# ── Notifications ──

# The ids of the critical ones, closed at the end (they never time out).
critical_ids=()

close_critical() {
    local id
    for id in "${critical_ids[@]}"; do
        busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
            org.freedesktop.Notifications CloseNotification u "$id" >/dev/null 2>&1 || true
    done
    critical_ids=()
}
# The island's own critical ones, taken back the way it does itself
# (on Ctrl+C too, while they are up).
alerts_up=
take_back() {
    qs -c dynamic-island ipc call island-notices battery charging >/dev/null 2>&1 || true
    qs -c dynamic-island ipc call island-notices disk / 50 >/dev/null 2>&1 || true
}

# The dictation face too, if the script stops while it is up.
cleanup() {
    close_critical
    [[ -z $alerts_up ]] || take_back
    qs -c dynamic-island ipc call island-notices dictation "" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# send <label> <notify-send args…>: one through notify-send, as apps do.
send() {
    local label=$1 id
    shift
    printf '%s\n' "$label"
    id=$(notify-send -p "$@")
    [[ " $* " == *" -u critical "* ]] && critical_ids+=("$id")
    sleep 1.5
}

# relay_send <label> <relay notif send args…>: one the way rack and relay
# send theirs, through `relay notif send` (straight to D-Bus), or
# notify-send where relay isn't installed.
relay_send() {
    local label=$1 id
    shift
    printf '%s\n' "$label"
    if command -v relay >/dev/null; then
        id=$(relay notif send -p "$@")
    else
        id=$(notify-send -p "$@")
    fi
    [[ " $* " == *" -u critical "* ]] && critical_ids+=("$id")
    sleep 1.5
}

notifications() {
    echo "Notifications › Apps (normal, 5 s)"
    send "  Signal: a message"           -a Signal -u normal -t 5000 "Anna" "are we still on for tonight?"
    send "  Firefox: download complete"  -a Firefox -u normal -t 5000 "Download complete" "report.pdf"
    send "  Thunderbird: new mail"       -a Thunderbird -u normal -t 5000 "Invoice October" "from Telia"
    sleep 3

    echo "Notifications › rack and relay (low 3 s; failures critical)"
    relay_send "  rack: synced"              -a rack -u low -t 3000 "Dotfiles synced" "pulled and deployed ~/.dotfiles"
    relay_send "  rack: update failed"       -a rack -u critical "Update failed" "pacman: conflicting files – click for the log"

    # The Print keys' own line (hypr/modules/binds/media.lua), on the
    # newest screenshot; nothing is captured or copied.
    local shot
    shot=$(find "$HOME/Pictures/Screenshots" -maxdepth 1 -name '*.png' 2>/dev/null | sort | tail -n 1)
    if [[ -n $shot ]]; then
        send "  Print: screenshot copied" \
            -a Screenshot -u low -t 3000 -i "$shot" "Screenshot copied" "Saved in Pictures/Screenshots as ${shot##*/}"
    else
        echo "  Print: skipped, no screenshot in ~/Pictures/Screenshots to show"
    fi
    sleep 3

    # Sent by the island itself (Alerts.qml), from made-up readings; the
    # pill flashes the battery one too.
    echo "Notifications › System problems (critical, until dismissed)"
    echo "  Battery critical"
    alerts_up=1
    qs -c dynamic-island ipc call island-notices battery critical
    sleep 1.5
    echo "  Disk almost full"
    qs -c dynamic-island ipc call island-notices disk / 2.1
    sleep 1.5

    echo "  (taking them back in 6 s, as plugging in and freeing space do)"
    sleep 6
    take_back
    alerts_up=
    close_critical
}

for part in "${parts[@]}"; do
    "$part"
done
