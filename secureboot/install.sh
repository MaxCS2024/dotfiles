#!/usr/bin/env bash
#
# Secure Boot with this machine's own keys (sbctl), with Microsoft's enrolled
# alongside. The firmware boots a signed unified kernel image (UKI) directly,
# with nothing in between: GRUB without shim can't hand off to a UKI under
# Secure Boot (found on the T480), and a UKI needs no bootloader.
#
# Each run does the next step that isn't done yet, and stops at the two only
# a person can take, in the BIOS:
#
#   1. keys     sbctl create-keys. From here on sbctl's mkinitcpio hook signs
#               every UKI it builds, and its pacman hook re-signs after
#               updates.
#   2. UKI      each mkinitcpio preset builds a UKI into <ESP>/EFI/Linux, with
#               the command line this boot used in /etc/kernel/cmdline
#   3. entry    a firmware boot entry per UKI, put first in the boot order.
#               The entries already there stay behind them as a fallback.
#   4. BIOS     reset Secure Boot to Setup Mode                        stop
#   5. enroll   sbctl enroll-keys --microsoft
#   6. verify   every UKI signed
#   7. BIOS     switch Secure Boot on                                  stop
#
# A stop exits 75, which rack reads as "not finished" (rack/lib/features.sh):
# `rack features on secureboot` again after the BIOS step carries on.
#
# Microsoft's keys go in too because some laptops' firmware loads option ROMs
# (a GPU's, a dock's) that only Microsoft signed, and enrolling without them
# can leave such a machine unable to show its own BIOS.
#
# rack/features.json runs this as setup and refuses to remove the feature:
# taking sbctl away with Secure Boot on leaves the next kernel unsigned, and
# the machine unbootable.

set -euo pipefail

PENDING=75
CMDLINE=/etc/kernel/cmdline
PRESET_DIR=/etc/mkinitcpio.d
BACKUP="${XDG_STATE_HOME:-$HOME/.local/state}/rack/backups/$(date +%Y%m%d-%H%M%S)"

die() {
    printf 'secureboot: %s\n' "$*" >&2
    exit 1
}

step() {
    printf '\n%s\n' "$*"
}

confirm() {
    local answer
    [[ -t 0 ]] || die "this needs a terminal to ask before it changes how the machine boots"
    read -r -p "$1 [y/N] " answer
    [[ $answer == [yY]* ]]
}

# Copies a root-owned file to where rack deploy keeps what it replaces.
backup() {
    mkdir -p -- "$BACKUP${1%/*}"
    sudo cat -- "$1" >"$BACKUP$1"
}

# The EFI system partition: whichever of the usual mount points is FAT.
esp() {
    local d
    for d in /efi /boot /boot/efi; do
        [[ $(findmnt -rno FSTYPE --mountpoint "$d" 2>/dev/null) == vfat ]] && {
            printf '%s\n' "$d"
            return 0
        }
    done
    return 1
}

status() {
    sbctl status --json 2>/dev/null || die "sbctl status failed"
}

# True when the enrolled Platform Key is sbctl's own, compared byte for byte.
# Secure Boot on with any other PK means someone else's keys (a vendor's, or
# shim's), which this would replace.
own_pk_enrolled() {
    local enrolled ours
    [[ $(status | jq -r .installed) == true ]] || return 1
    enrolled=$(sbctl list-enrolled-keys --json 2>/dev/null | jq -r '.PK[0].Raw // empty')
    ours=$(sudo grep -v -- '-----' /var/lib/sbctl/keys/PK/PK.pem | tr -d '\n')
    [[ -n $enrolled && $enrolled == "$ours" ]]
}

# Every UKI the presets build, fallbacks first: efibootmgr puts each new entry
# at the front, so the defaults end up ahead of them.
ukis() {
    local p
    for p in "$PRESET_DIR"/*.preset; do
        (
            # shellcheck disable=SC1090
            source "$p"
            for x in "${PRESETS[@]}"; do
                v=${x}_uki
                [[ -n ${!v:-} ]] && printf '%s\t%s\n' "$x" "${!v}"
            done
        )
    done | sort -r -k1,1 | cut -f2
}

keys() {
    [[ $(status | jq -r .installed) == true ]] && return 0
    step "Creating this machine's Secure Boot keys (sbctl create-keys)"
    sudo sbctl create-keys
}

cmdline() {
    local line
    sudo test -s "$CMDLINE" && return 0
    line=$(tr ' ' '\n' </proc/cmdline | grep -vE '^(BOOT_IMAGE|initrd)=|^$' | paste -sd' ')
    [[ $line == *root=* ]] ||
        die "this boot's command line has no root=, so there's nothing safe to copy; write $CMDLINE yourself and run this again"
    step "The UKI carries the kernel command line in it. This boot used:"
    printf '  %s\n' "$line"
    confirm "Put that in $CMDLINE?" || die "stopped; nothing about booting has changed"
    printf '%s\n' "$line" | sudo tee "$CMDLINE" >/dev/null
}

# Turns each preset's image lines into UKI lines, keeping the old ones
# commented, and builds. Presets already making a UKI are left as they are.
uki() {
    local esp=$1 p name tmp changed=0 u missing=0
    for p in "$PRESET_DIR"/*.preset; do
        grep -q '^[^#]*_uki=' "$p" && continue
        name=$(basename "$p" .preset)
        tmp=$(mktemp)
        awk -v esp="$esp" -v name="$name" '
            /^[[:space:]]*default_image=/ { print "#" $0; print "default_uki=\"" esp "/EFI/Linux/arch-" name ".efi\""; next }
            /^[[:space:]]*fallback_image=/ { print "#" $0; print "fallback_uki=\"" esp "/EFI/Linux/arch-" name "-fallback.efi\""; next }
            { print }' "$p" >"$tmp"
        grep -q '^default_uki=' "$tmp" || {
            rm -f -- "$tmp"
            die "$p has no default_image line to turn into a UKI"
        }
        backup "$p"
        sudo install -m644 -- "$tmp" "$p"
        rm -f -- "$tmp"
        changed=1
    done
    while read -r u; do [[ -f $u ]] || missing=1; done < <(ukis)
    ((changed || missing)) || return 0
    step "Building the UKIs (mkinitcpio -P); sbctl's hook signs each one"
    sudo install -d -- "$esp/EFI/Linux"
    sudo mkinitcpio -P
    while read -r u; do [[ -f $u ]] || die "mkinitcpio built no $u"; done < <(ukis)
}

# sbctl's hook signed them as they were built; -s also puts them in sbctl's
# list, which its pacman hook re-signs after every update.
sign() {
    local u
    while read -r u; do
        sudo sbctl sign -s -- "$u" >/dev/null
    done < <(ukis)
}

entries() {
    local esp=$1 dev disk part u path loader base label current
    dev=$(findmnt -rno SOURCE --mountpoint "$esp")
    disk=/dev/$(lsblk -no PKNAME -- "$dev")
    part=$(<"/sys/class/block/${dev##*/}/partition")
    while read -r u; do
        path=${u#"$esp"}
        loader=${path//\//\\}
        # Captured, not piped into grep -q: under pipefail a match that
        # closes the pipe early reads as a failure.
        current=$(efibootmgr)
        [[ ${current,,} == *"${loader,,}"* ]] && continue
        base=$(basename "$u" .efi)
        label="Arch Linux (UKI ${base#arch-})"
        step "Adding the firmware boot entry \"$label\""
        sudo efibootmgr --quiet --create --disk "$disk" --part "$part" --label "$label" --loader "$loader"
    done < <(ukis)
}

enroll() {
    own_pk_enrolled && return 0
    if [[ $(status | jq -r .setup_mode) != true ]]; then
        cat <<-'EOF'

			Next, in the BIOS: put Secure Boot in Setup Mode.
			  1. Restart into the BIOS setup (F1 on a ThinkPad; often F2 or Del).
			  2. Under Security › Secure Boot, choose "Reset to Setup Mode" (ThinkPad),
			     or "Clear Secure Boot keys" / "Delete all keys" elsewhere. Some
			     firmware asks for a supervisor password to be set first.
			  3. Leave Secure Boot itself off for now. Save, and boot back into Linux.
			  4. Run `rack features on secureboot` again.
		EOF
        exit "$PENDING"
    fi
    step "Enrolling this machine's keys, with Microsoft's (sbctl enroll-keys --microsoft)"
    sudo sbctl enroll-keys --microsoft
}

verify() {
    local out u bad=0
    out=$(sudo sbctl verify 2>&1) || true
    while read -r u; do
        [[ $out == *"$u is signed"* ]] || {
            printf '  %s is not signed\n' "$u" >&2
            bad=1
        }
    done < <(ukis)
    ((bad == 0)) || die "a UKI isn't signed, so Secure Boot would refuse it; don't switch it on yet"
}

main() {
    local esp state
    [[ -d /sys/firmware/efi ]] || die "this machine booted without UEFI, which Secure Boot needs"
    command -v mkinitcpio >/dev/null || die "the UKI is built by mkinitcpio, which isn't installed"
    esp=$(esp) || die "no EFI system partition is mounted at /efi, /boot or /boot/efi"

    state=$(status)
    if [[ $(jq -r .secure_boot <<<"$state") == true ]]; then
        own_pk_enrolled ||
            die "Secure Boot is already on, with keys that aren't this machine's sbctl keys. Setting it up here replaces them: switch Secure Boot off in the BIOS first."
        verify
        printf 'Secure Boot is on, with this machine'\''s keys, and every UKI is signed\n'
        return 0
    fi

    if ! grep -qs '^[^#]*_uki=' "$PRESET_DIR"/*.preset || ! own_pk_enrolled; then
        cat <<-EOF
			This sets up Secure Boot with keys of this machine's own:
			  - mkinitcpio builds signed UKIs into $esp/EFI/Linux instead of initramfs
			    images; the old image lines stay in the presets, commented out
			  - a firmware boot entry per UKI goes first in the boot order; the
			    entries there now stay behind them, as a fallback
			  - keys are created, and enrolled with Microsoft's
			Two steps are yours, in the BIOS; this stops and says when.
			Changed files are copied to $BACKUP first.
		EOF
        confirm "Go on?" || die "stopped; nothing has changed"
    fi

    keys
    cmdline
    uki "$esp"
    sign
    entries "$esp"
    enroll
    verify
    cat <<-'EOF'

		Last step, in the BIOS: switch Secure Boot on.
		  1. Restart into the BIOS setup (F1 on a ThinkPad; often F2 or Del).
		  2. Under Security › Secure Boot, set Secure Boot to Enabled. Save.
		  3. The laptop starts the "Arch Linux (UKI linux)" entry. If it doesn't
		     start, switch Secure Boot off again: nothing else has to be undone.
		Conf › Features shows Secure Boot as installed once it's on.
	EOF
    exit "$PENDING"
}

main "$@"
