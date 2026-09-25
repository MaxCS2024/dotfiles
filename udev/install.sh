#!/usr/bin/env bash
#
# Copies the udev rules in this directory into /etc/udev/rules.d.
#
# Copied rather than linked: udev reads its rules before /home is
# guaranteed to be mounted, so a link back into this repo can dangle at
# boot. Run this again after editing a rule here.
#
# Not a rack feature: each rule is a fix for one piece of hardware, only
# needed on a machine that has it.

set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# 91-apple-superdrive.rules runs sg_raw.
sudo pacman -S --needed sg3_utils

sudo install -m644 -t /etc/udev/rules.d -- *.rules
sudo udevadm control --reload
# Applies the rules to drives already plugged in, not only the next ones.
sudo udevadm trigger --action=add --subsystem-match=block --sysname-match='sr*'

printf 'Installed %s into /etc/udev/rules.d\n' "$(echo *.rules)"
