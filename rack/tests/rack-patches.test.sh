#!/usr/bin/env bash
# tests for rack patches: udev rules for one piece of hardware each, copied
# into /etc on the machines that have it.
#
# The same harness as rack-features.test.sh, cut down: a fresh HOME per test,
# the real `rack` command, a udev/ of two made-up rules, and a stand-in /etc
# directory (RACK_PATCHES_TARGET). sudo, pacman and udevadm are stand-ins that
# write what they were asked to $TMP/calls; sudo runs the rest, so install
# and rm act on the stand-in directory only.
#
#   ./tests/rack-patches.test.sh           # all tests
#   ./tests/rack-patches.test.sh remove    # only tests whose name matches
set -uo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
RACK="$ROOT/rack"

FILTER=${1-}
PASS=0
FAIL=0
FAILURES=()

ORIG_HOME=$HOME
ORIG_PATH=$PATH
ORIG_TMPDIR=${TMPDIR:-/tmp}

# ---- harness -----------------------------------------------------------------

# /usr/bin without anything a patch could reach for, built once per run.
make_sys() {
	SYS=$(TMPDIR=$ORIG_TMPDIR mktemp -d) || exit 1
	local f
	for f in /usr/bin/*; do
		case ${f##*/} in
			pacman | sudo | udevadm) continue ;;
		esac
		ln -s "$f" "$SYS/"
	done
}

setup() {
	TMP=$(TMPDIR=$ORIG_TMPDIR mktemp -d) && [[ -d $TMP && $TMP == "$ORIG_TMPDIR"/* ]] || {
		printf 'harness error: cannot make a temp directory\n' >&2
		exit 1
	}
	mkdir -p "$TMP/home" "$TMP/bin" "$TMP/udev" "$TMP/etc"

	export HOME="$TMP/home"
	export RACK_PATCHES="$TMP/udev"
	export RACK_PATCHES_TARGET="$TMP/etc"
	export PATH="$TMP/bin:$SYS"
	export RIG_COLOR=never RIG_LOG_JOURNAL=never STUB="$TMP"
	unset RIG_DRY_RUN RIG_YES

	# drive has every header; plain has none, so its label is its name.
	cat >"$TMP/udev/91-apple-drive.rules" <<-'EOF'
		# Patch: Apple Drive
		# Needs: sg3_utils other-pkg
		# Trigger: --subsystem-match=block --sysname-match=sr*
		#
		# Wakes the drive.
		ACTION=="add", RUN+="/usr/bin/true"
	EOF
	printf 'ACTION=="add", RUN+="/usr/bin/true"\n' >"$TMP/udev/50-plain.rules"

	printf '#!/bin/bash\necho "$(basename "$0") $*" >>"$STUB/calls"\n' >"$TMP/bin/stub"
	printf '#!/bin/bash\necho "sudo $*" >>"$STUB/calls"\nexec "$@"\n' >"$TMP/bin/sudo"
	chmod +x "$TMP/bin/"*
	ln -s stub "$TMP/bin/pacman"
	ln -s stub "$TMP/bin/udevadm"
	: >"$TMP/calls"
}

teardown() {
	export HOME="$ORIG_HOME" PATH="$ORIG_PATH"
	[[ -n ${TMP:-} && -d $TMP ]] && rm -rf "$TMP"
	return 0
}

run() {
	OUT=$("$RACK" "$@" 2>"$TMP/err" </dev/null)
	STATUS=$?
	ERR=$(cat "$TMP/err")
	CALLS=$(cat "$TMP/calls")
	return 0
}

fail() {
	FAIL=$((FAIL + 1))
	FAILURES+=("$CURRENT: $1")
	printf '  \033[31mFAIL\033[0m %s\n        %s\n' "$CURRENT" "$1"
}

ok() {
	PASS=$((PASS + 1))
	printf '  \033[32mok\033[0m   %s\n' "$CURRENT"
}

assert_eq() {
	[[ $2 == "$3" ]] || {
		fail "$1: expected [$3], got [$2]"
		return 1
	}
}

assert_has() {
	[[ $2 == *"$3"* ]] || {
		fail "$1: expected to contain [$3], got [$2]"
		return 1
	}
}

assert_lacks() {
	[[ $2 != *"$3"* ]] || {
		fail "$1: expected no [$3], got [$2]"
		return 1
	}
}

it() { CURRENT=$1; }

# ---- list ----------------------------------------------------------------------

test_list_names_and_labels() {
	it "list names each rule without its number, labelled by its Patch: line"
	run patches list
	assert_eq "status" "$STATUS" 0 || return
	assert_has "drive" "$OUT" "apple-drive        not installed  Apple Drive" || return
	assert_has "plain" "$OUT" "plain              not installed  plain" || return
	ok
}

test_list_states() {
	it "list tells installed from out of date"
	cp "$TMP/udev/91-apple-drive.rules" "$TMP/etc/"
	printf 'older\n' >"$TMP/etc/50-plain.rules"
	run patches
	assert_has "drive" "$OUT" "apple-drive        installed" || return
	assert_has "plain" "$OUT" "plain              out of date" || return
	ok
}

# ---- install ---------------------------------------------------------------------

test_install() {
	it "install brings its packages, copies the rule, reloads and triggers"
	run patches install apple-drive
	assert_eq "status" "$STATUS" 0 || return
	assert_has "packages" "$CALLS" "pacman -S --needed -- sg3_utils other-pkg" || return
	cmp -s "$TMP/udev/91-apple-drive.rules" "$TMP/etc/91-apple-drive.rules" ||
		{ fail "rule not copied"; return; }
	assert_has "reload" "$CALLS" "udevadm control --reload" || return
	assert_has "trigger" "$CALLS" "udevadm trigger --action=add --subsystem-match=block --sysname-match=sr*" || return
	[[ -e $TMP/etc/50-plain.rules ]] && { fail "installed a patch it wasn't asked for"; return; }
	ok
}

test_install_without_headers() {
	it "a rule with no Needs: or Trigger: installs without pacman or a trigger"
	run patches install plain
	assert_eq "status" "$STATUS" 0 || return
	assert_lacks "pacman" "$CALLS" "pacman" || return
	assert_lacks "trigger" "$CALLS" "trigger" || return
	[[ -e $TMP/etc/50-plain.rules ]] || { fail "rule not copied"; return; }
	ok
}

test_unknown_patch() {
	it "an unknown patch stops the command before anything changes"
	run patches install plain nope
	assert_eq "status" "$STATUS" 2 || return
	assert_has "said" "$ERR" "no patch called 'nope'" || return
	assert_eq "calls" "$CALLS" "" || return
	ok
}

# ---- remove ----------------------------------------------------------------------

test_remove_asks() {
	it "remove with no one to ask leaves the rule where it is"
	cp "$TMP/udev/50-plain.rules" "$TMP/etc/"
	run patches remove plain
	assert_eq "status" "$STATUS" 0 || return
	assert_has "listed" "$OUT" "$TMP/etc/50-plain.rules" || return
	[[ -e $TMP/etc/50-plain.rules ]] || { fail "removed without asking"; return; }
	ok
}

test_remove() {
	it "remove, once agreed to, deletes the rule and reloads"
	cp "$TMP/udev/91-apple-drive.rules" "$TMP/etc/"
	RIG_YES=1 run patches remove apple-drive
	assert_eq "status" "$STATUS" 0 || return
	[[ -e $TMP/etc/91-apple-drive.rules ]] && { fail "rule still there"; return; }
	assert_has "reload" "$CALLS" "udevadm control --reload" || return
	assert_lacks "packages" "$CALLS" "pacman" || return
	ok
}

test_remove_not_installed() {
	it "removing a patch that isn't installed says so and does nothing"
	run patches remove plain
	assert_eq "status" "$STATUS" 0 || return
	assert_has "said" "$OUT" "plain: not installed" || return
	assert_eq "calls" "$CALLS" "" || return
	ok
}

main() {
	[[ -x $RACK ]] || {
		printf 'rack not found or not executable: %s\n' "$RACK" >&2
		exit 1
	}
	make_sys
	trap 'rm -rf "$SYS"' EXIT

	local tests t
	mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_' | sort)

	printf 'rack patches\n'
	for t in "${tests[@]}"; do
		[[ -n $FILTER && $t != *"$FILTER"* ]] && continue
		CURRENT=$t
		setup
		"$t"
		teardown
	done

	printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
	((FAIL == 0)) || {
		printf '\nfailures:\n'
		printf '  %s\n' "${FAILURES[@]}"
		exit 1
	}
}

main "$@"
