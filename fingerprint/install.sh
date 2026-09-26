#!/usr/bin/env bash
#
# Fingerprint unlock: the reader's driver, an enrolled finger, and sudo taking
# a finger in terminal windows. The lock screen needs nothing from here:
# hypr/hyprlock.conf asks fprintd directly whenever it is there.
#
# Most readers are libfprint's, and fprintd from the repo drives them as it
# comes. The older Synaptics/Validity sensors in ThinkPads of the T480 era
# (VALIDITY_IDS below) are not, and need the AUR's python-validity, which
# needs more care. All of this was learnt on a T480:
#
#   - Its install hook starts the driver at once, before the sensor's
#     firmware is on the machine. The driver fails, systemd restarts it, and
#     the half-finished attempts leave the sensor answering only errors until
#     a factory reset. So --prepare masks the driver before the package goes
#     in, and setup unmasks it once the firmware is there.
#   - validity-sensors-firmware downloads the firmware into /run, which is
#     emptied at every shutdown, and the driver reads it from there at every
#     boot. A copy is kept in /var/lib/python-validity and tmpfiles.d puts it
#     back before the driver starts.
#
# sudo gets two lines above `auth include system-auth` in /etc/pam.d/sudo. The
# finger is only asked for on a /dev/pts tty, a terminal window. The shell's
# services/PrivilegedExec.qml runs `sudo -S` with a typed password, and its
# tty is tty1 (ly starts Hyprland there), so it goes straight to the password
# rather than waiting on a finger.
#
# rack/features.json runs this: --validity picks the driver, --prepare runs
# before the driver is installed, no argument after it, and --remove before
# it is uninstalled. Safe to run by hand, and again.

set -euo pipefail

VALIDITY_IDS=(138a:0090 138a:0097 138a:009d 06cb:009a)
FIRMWARE_HOME=/var/lib/python-validity
FIRMWARE_RUN=/run/python-validity
TMPFILES=/etc/tmpfiles.d/python-validity.conf
PAM=/etc/pam.d/sudo
MARK='# rack features: fingerprint'
PAM_LINES="$MARK — a finger in terminal windows only (fingerprint/install.sh)
auth		[success=ignore default=1]	pam_succeed_if.so quiet tty =~ *pts/*
auth		sufficient	pam_fprintd.so max-tries=3 timeout=10"

die() {
    printf 'fingerprint: %s\n' "$*" >&2
    exit 1
}

# True when the reader is one only python-validity drives. Read from sysfs,
# since usbutils (lsusb) is not a given.
validity() {
    local d id
    for d in /sys/bus/usb/devices/*; do
        [[ -r $d/idVendor && -r $d/idProduct ]] || continue
        id=$(<"$d/idVendor"):$(<"$d/idProduct")
        [[ " ${VALIDITY_IDS[*]} " == *" $id "* ]] && return 0
    done
    return 1
}

# Its install hook then says it could not enable python3-validity; that is
# this, and setup enables it.
prepare() {
    validity || return 0
    pacman -Q python-validity >/dev/null 2>&1 && return 0
    printf 'masking python3-validity until its firmware is here\n'
    sudo systemctl mask python3-validity.service
}

validity_setup() {
    local -a firmware
    shopt -s nullglob
    firmware=("$FIRMWARE_HOME"/*.xpfwext)
    if ((${#firmware[@]} == 0)); then
        sudo validity-sensors-firmware
        firmware=("$FIRMWARE_RUN"/*.xpfwext)
        ((${#firmware[@]})) || die "validity-sensors-firmware put no firmware in $FIRMWARE_RUN"
        sudo install -D -m644 -t "$FIRMWARE_HOME" "${firmware[@]}"
        firmware=("$FIRMWARE_HOME"/*.xpfwext)
    fi
    [[ -f $TMPFILES ]] ||
        printf 'C %s - - - - %s\n' "$FIRMWARE_RUN" "$FIRMWARE_HOME" | sudo tee "$TMPFILES" >/dev/null
    # A driver that already ran and failed leaves a file of its own in
    # /run/python-validity, and tmpfiles.d copies nothing into a directory
    # that isn't empty, so the firmware goes in by hand this once.
    sudo install -D -m644 -t "$FIRMWARE_RUN" "${firmware[@]}"
    shopt -u nullglob

    sudo systemctl unmask python3-validity.service
    # The suspend hotfix restarts the driver when it starts, so it is only
    # enabled here: it runs after the next resume.
    sudo systemctl enable python3-validity-suspend-hotfix.service
    sudo systemctl enable --now python3-validity.service
}

# What fprintd knows about this user: the reader, then the enrolled fingers.
# Captured whole rather than piped into grep -q, which exits on the first
# match and, under pipefail, turns a match into a failure (rack/lib/setup.sh
# has the same story for fc-list).
listing() {
    fprintd-list "$USER" 2>/dev/null || true
}

# The driver uploads firmware, reboots the sensor and calibrates it before it
# offers the reader, which takes python-validity ten seconds or so.
wait_for_reader() {
    local _
    for _ in {1..45}; do
        [[ $(listing) == *"Device at"* ]] && return 0
        sleep 1
    done
    return 1
}

no_reader() {
    if validity; then
        cat >&2 <<-EOF
			fingerprint: the driver is running, but the reader never showed up.
			journalctl -u python3-validity says why. What fixed it on the T480:
			  1. In the BIOS (F1): Security › Fingerprint › Predesktop Authentication: Disabled
			  2. sudo systemctl mask python3-validity, then shut down (not reboot),
			     wait 15 seconds, and power on
			  3. sudo python3 /usr/share/python-validity/playground/factory-reset.py
			     (it prints nothing when it works)
			  4. sudo systemctl unmask python3-validity
			  5. rack features on fingerprint
		EOF
    else
        cat >&2 <<-EOF
			fingerprint: fprintd found no reader it can drive. Is the reader switched on
			in the BIOS, and is it on https://fprint.freedesktop.org/supported-devices.html?
			rack features remove fingerprint takes fprintd away again.
		EOF
    fi
    exit 1
}

enrol() {
    [[ $(listing) == *" - #"* ]] && return 0
    if [[ -t 0 && -t 1 ]]; then
        printf '\nEnrol a finger: touch the reader each time it asks, lifting the finger\n'
        printf 'and moving it a little between touches so the whole fingertip is covered.\n\n'
        fprintd-enroll || printf 'enrolment did not finish; run fprintd-enroll to try again\n'
    else
        printf 'no finger enrolled yet: run fprintd-enroll in a terminal\n'
    fi
}

# Writes the PAM file through a copy, keeping the old one where rack deploy
# keeps what it replaces. pam_fprintd.so has to exist before sudo names it:
# a module PAM cannot load fails every sudo.
pam_install() {
    local tmp=$1 backup
    [[ $(head -n1 "$tmp") == '#%PAM-1.0' ]] && grep -q 'system-auth' "$tmp" ||
        die "refusing to write $PAM: the new file doesn't look like the old one"
    backup="${XDG_STATE_HOME:-$HOME/.local/state}/rack/backups/$(date +%Y%m%d-%H%M%S)$PAM"
    mkdir -p -- "${backup%/*}"
    cp -- "$PAM" "$backup"
    sudo install -m644 -o root -g root -- "$tmp" "$PAM"
    printf 'the old %s is in %s\n' "$PAM" "$backup"
}

pam_add() {
    local tmp
    grep -q 'pam_fprintd\.so' "$PAM" && return 0
    [[ -e /usr/lib/security/pam_fprintd.so && -e /usr/lib/security/pam_succeed_if.so ]] ||
        die "pam_fprintd.so is not installed, so sudo is left alone"
    tmp=$(mktemp)
    awk -v block="$PAM_LINES" '!done && /^auth[[:space:]]/ { print block; done = 1 } { print }' "$PAM" >"$tmp"
    grep -q 'pam_fprintd\.so' "$tmp" || {
        rm -f -- "$tmp"
        die "no auth line in $PAM to put the finger in front of"
    }
    pam_install "$tmp"
    rm -f -- "$tmp"
    printf 'sudo in a terminal asks for a finger first (3 tries, 10 seconds each), then the password\n'
}

# Takes out what pam_add puts in, and the same two lines put in by hand.
pam_remove() {
    local tmp
    grep -qE 'pam_fprintd\.so|^# rack features: fingerprint' "$PAM" || return 0
    tmp=$(mktemp)
    awk '/^# rack features: fingerprint/ || /pam_fprintd\.so/ || /pam_succeed_if\.so quiet tty =~ \*pts\/\*/ { next } { print }' \
        "$PAM" >"$tmp"
    pam_install "$tmp"
    rm -f -- "$tmp"
}

setup() {
    command -v fprintd-enroll >/dev/null || die "fprintd is not installed (rack features on fingerprint installs it)"
    validity && validity_setup
    wait_for_reader || no_reader
    enrol
    pam_add
}

# Runs while the driver is still installed: sudo stops naming pam_fprintd.so
# before the package that has it goes, and fprintd can still delete the
# enrolled fingers (python-validity keeps them on the sensor itself).
remove() {
    pam_remove
    fprintd-delete "$USER" >/dev/null 2>&1 || true
    if [[ -e $TMPFILES || -e $FIRMWARE_HOME ]]; then
        sudo rm -rf -- "$TMPFILES" "$FIRMWARE_HOME"
    fi
    if [[ $(systemctl is-enabled python3-validity.service 2>/dev/null) == masked ]]; then
        sudo systemctl unmask python3-validity.service
    fi
}

case ${1-} in
    '') setup ;;
    --validity) validity ;;
    --prepare) prepare ;;
    --remove) remove ;;
    *)
        printf 'usage: fingerprint/install.sh [--validity | --prepare | --remove]\n' >&2
        exit 2
        ;;
esac
