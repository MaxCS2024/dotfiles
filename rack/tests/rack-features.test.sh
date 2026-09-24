#!/usr/bin/env bash
# tests for rack features: turning optional parts of the desktop on, off, and
# off-and-gone.
#
# The same harness as rack-names.test.sh — a fresh HOME per test and the real
# `rack` command — plus a registry of two made-up features and stand-ins for
# everything a feature touches outside the repo: pacman, yay, sudo,
# systemctl, and the feature's own binary. Each stand-in writes what it was
# asked to do to $TMP/calls. PATH is those stand-ins plus a copy of /usr/bin
# with the real ones taken out, so nothing here can install, remove or stop
# anything on this machine, and "yay is not installed" can be true.
#
#   ./tests/rack-features.test.sh           # all tests
#   ./tests/rack-features.test.sh remove    # only tests whose name matches
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

# /usr/bin without anything a feature could reach for, built once per run.
make_sys() {
	SYS=$(TMPDIR=$ORIG_TMPDIR mktemp -d) || exit 1
	local f
	for f in /usr/bin/*; do
		case ${f##*/} in
			yay | paru | pacman | sudo | systemctl | hyprctl | voxtype | wtype) continue ;;
		esac
		ln -s "$f" "$SYS/"
	done
}

setup() {
	TMP=$(TMPDIR=$ORIG_TMPDIR mktemp -d) && [[ -d $TMP && $TMP == "$ORIG_TMPDIR"/* ]] || {
		printf 'harness error: cannot make a temp directory\n' >&2
		exit 1
	}
	mkdir -p "$TMP/home" "$TMP/bin" "$TMP/pkgs" "$TMP/units" "$TMP/runtime"

	export HOME="$TMP/home"
	export XDG_RUNTIME_DIR="$TMP/runtime"
	export RACK_FEATURES="$TMP/features.json"
	export RACK_MANIFEST="$TMP/manifest.conf"
	export PATH="$TMP/bin:$SYS"
	export RIG_COLOR=never RIG_LOG_JOURNAL=never STUB="$TMP"
	unset RACK_FEATURES_STATE XDG_CONFIG_HOME RIG_DRY_RUN RIG_YES HYPRLAND_INSTANCE_SIGNATURE
	: >"$RACK_MANIFEST"
	STATE="$HOME/.config/rack/features.conf"

	# talk is dictation's shape: a repo package, an AUR package that brings
	# the binary, setup that installs a unit, teardown that takes it away, and
	# data. sky shares talk's repo package, which a remove must leave alone
	# while sky is on. stray names a data path outside $HOME.
	cat >"$RACK_FEATURES" <<-'EOF'
		{"version": 1, "features": {
		  "talk": {"label": "Talk", "summary": "Say things.", "recommended": false,
		    "provides": ["zztalkd"],
		    "packages": {"repo": ["talk-typer"], "aur": ["zztalkd-bin"]},
		    "setup": [["zztalkd", "setup"]], "units": ["zztalkd.service"],
		    "teardown": [["zztalkd", "teardown"]], "data": ["~/.local/share/talk"]},
		  "sky": {"label": "Sky", "summary": "Look up.", "recommended": true,
		    "provides": [], "packages": {"repo": ["talk-typer"], "aur": []}},
		  "stray": {"label": "Stray", "summary": "x", "recommended": false,
		    "provides": [], "packages": {"repo": [], "aur": []}, "data": ["~/../escape"]}
		}}
	EOF

	# The package managers: -S installs (zztalkd-bin brings the zztalkd binary),
	# -Q asks, -Rns removes. sudo just runs what it was given.
	cat >"$TMP/bin/pkgstub" <<-'EOF'
		#!/bin/bash
		echo "$(basename "$0") $*" >>"$STUB/calls"
		op=$1; shift
		for p in "$@"; do
		  [[ $p == -* ]] && continue
		  case $op in
		    -S) touch "$STUB/pkgs/$p"
		        [[ $p == zztalkd-bin ]] && cp "$STUB/bin/zztalkd.real" "$STUB/bin/zztalkd" ;;
		    -Q) [[ -e $STUB/pkgs/$p ]] || exit 1 ;;
		    -Rns) rm -f "$STUB/pkgs/$p"
		        [[ $p == zztalkd-bin ]] && rm -f "$STUB/bin/zztalkd" ;;
		  esac
		done
		exit 0
	EOF
	cat >"$TMP/bin/zztalkd.real" <<-'EOF'
		#!/bin/bash
		echo "zztalkd $*" >>"$STUB/calls"
		case $1 in
		  setup) touch "$STUB/units/zztalkd.service"; mkdir -p "$HOME/.local/share/talk/models" ;;
		  teardown) rm -f "$STUB/units/zztalkd.service" ;;
		esac
	EOF
	cat >"$TMP/bin/systemctl" <<-'EOF'
		#!/bin/bash
		echo "systemctl $*" >>"$STUB/calls"
		[[ $2 == cat ]] && { [[ -e $STUB/units/${4:-$3} ]]; exit; }
		exit 0
	EOF
	printf '#!/bin/bash\necho "sudo $*" >>"$STUB/calls"\nexec "$@"\n' >"$TMP/bin/sudo"
	chmod +x "$TMP/bin/"*
	ln -s pkgstub "$TMP/bin/pacman"
	ln -s pkgstub "$TMP/bin/yay"
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

# Installs talk the way `rack features on talk` does, without asserting on it.
install_talk() {
	"$RACK" features on talk >/dev/null 2>&1 </dev/null
	: >"$TMP/calls"
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

# ---- list and state ------------------------------------------------------------

test_list_without_state_is_all_on() {
	it "with no choices file, every feature is on"
	run features list
	assert_eq "status" "$STATUS" 0 || return
	assert_has "talk" "$OUT" "talk         on   not installed" || return
	assert_has "sky" "$OUT" "sky          on   installed" || return
	[[ -e $STATE ]] && { fail "list wrote $STATE"; return; }
	ok
}

test_no_terminal_lists() {
	it "rack features with no terminal lists instead of opening the picker"
	run features
	assert_eq "status" "$STATUS" 0 || return
	assert_has "listed" "$OUT" "Talk" || return
	ok
}

test_unknown_feature() {
	it "an unknown feature stops the command before anything changes"
	run features off sky tlak
	assert_eq "status" "$STATUS" 2 || return
	assert_has "said" "$ERR" "no feature called 'tlak'" || return
	[[ -e $STATE ]] && { fail "wrote $STATE anyway"; return; }
	ok
}

test_off_keeps_other_lines() {
	it "off rewrites its own line and keeps everyone else's"
	run features off sky
	run features off talk
	run features on sky
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "lines" "$(grep -v '^#' "$STATE")" $'sky on\ntalk off' || return
	assert_eq "one header" "$(grep -c '^# Written' "$STATE")" 1 || return
	ok
}

test_state_path_override() {
	it "RACK_FEATURES_STATE moves the choices file"
	export RACK_FEATURES_STATE="$TMP/elsewhere.conf"
	run features off sky
	[[ -f $TMP/elsewhere.conf ]] || { fail "no file at the override"; return; }
	run features path
	assert_eq "path" "$OUT" "$TMP/elsewhere.conf" || return
	ok
}

# ---- on ------------------------------------------------------------------------

test_on_installs_and_sets_up() {
	it "on installs repo and AUR packages, runs setup, starts the unit"
	run features on talk
	assert_eq "status" "$STATUS" 0 || return
	assert_has "pacman" "$CALLS" "sudo pacman -S --needed talk-typer" || return
	assert_has "yay" "$CALLS" "yay -S --needed zztalkd-bin" || return
	assert_lacks "yay not under sudo" "$CALLS" "sudo yay" || return
	assert_has "setup" "$CALLS" "zztalkd setup" || return
	assert_has "unit" "$CALLS" "systemctl --user enable --now -- zztalkd.service" || return
	assert_has "state" "$(cat "$STATE")" "talk on" || return
	ok
}

test_on_installed_only_starts() {
	it "on for something already installed installs nothing"
	install_talk
	run features off talk
	: >"$TMP/calls"
	run features on talk
	assert_eq "status" "$STATUS" 0 || return
	assert_lacks "no install" "$(cat "$TMP/calls")" "-S" || return
	assert_has "unit" "$(cat "$TMP/calls")" "enable --now -- zztalkd.service" || return
	ok
}

test_on_probe_decides_installed() {
	it "a feature with a probe is installed only once the probe passes"
	cat >"$RACK_FEATURES" <<-'EOF'
		{"version": 1, "features": {
		  "libs": {"label": "Libs", "summary": "x", "recommended": false,
		    "provides": ["sh"], "probe": ["sh", "-c", "test -e \"$STUB/pkgs/py-thing\""],
		    "packages": {"repo": ["py-thing"], "aur": []}}
		}}
	EOF
	run features list
	assert_has "not yet" "$OUT" "libs         on   not installed" || return
	run features on libs
	assert_eq "status" "$STATUS" 0 || return
	assert_has "installed" "$CALLS" "sudo pacman -S --needed py-thing" || return
	: >"$TMP/calls"
	run features on libs
	assert_lacks "not twice" "$CALLS" "pacman -S" || return
	ok
}

test_on_without_yay() {
	it "on refuses an AUR feature without yay, and leaves it off"
	run features off talk
	rm "$TMP/bin/yay"
	run features on talk
	[[ $STATUS -ne 0 ]] || { fail "succeeded"; return; }
	assert_has "said" "$ERR" "yay is not installed" || return
	assert_lacks "no pacman either" "$CALLS" "pacman -S" || return
	assert_has "still off" "$(cat "$STATE")" "talk off" || return
	ok
}

test_on_dry_run() {
	it "on under RIG_DRY_RUN prints the plan and changes nothing"
	RIG_DRY_RUN=1 run features on talk
	assert_eq "status" "$STATUS" 0 || return
	assert_has "plan" "$OUT" "would run: sudo pacman -S --needed talk-typer" || return
	assert_has "state" "$OUT" "would set talk on" || return
	assert_lacks "installed nothing" "$CALLS" "-S" || return
	assert_lacks "set nothing up" "$CALLS" "zztalkd setup" || return
	[[ -n $(ls "$TMP/pkgs") ]] && { fail "installed $(ls "$TMP/pkgs")"; return; }
	[[ -e $STATE ]] && { fail "wrote $STATE"; return; }
	ok
}

# ---- off -----------------------------------------------------------------------

test_off_stops_unit_and_keeps_packages() {
	it "off stops the unit and leaves packages and data where they are"
	install_talk
	run features off talk
	assert_eq "status" "$STATUS" 0 || return
	assert_has "unit" "$CALLS" "systemctl --user disable --now -- zztalkd.service" || return
	assert_lacks "no removal" "$CALLS" "-Rns" || return
	[[ -e $TMP/pkgs/zztalkd-bin && -d $HOME/.local/share/talk ]] || { fail "something was removed"; return; }
	assert_has "state" "$(cat "$STATE")" "talk off" || return
	ok
}

test_off_skips_missing_unit() {
	it "off does not try to stop a unit that was never installed"
	run features off talk
	assert_eq "status" "$STATUS" 0 || return
	assert_lacks "no disable" "$CALLS" "disable" || return
	ok
}

# ---- remove --------------------------------------------------------------------

test_remove_keeps_shared_package() {
	it "remove uninstalls talk but keeps the package sky still uses"
	install_talk
	RIG_YES=1 run features remove talk
	assert_eq "status" "$STATUS" 0 || return
	assert_has "teardown" "$CALLS" "zztalkd teardown" || return
	assert_has "removed" "$CALLS" "sudo pacman -Rns -- zztalkd-bin" || return
	[[ -e $TMP/pkgs/talk-typer ]] || { fail "removed talk-typer, which sky uses"; return; }
	[[ -e $HOME/.local/share/talk ]] && { fail "data left behind"; return; }
	assert_has "state" "$(cat "$STATE")" "talk off" || return
	ok
}

test_remove_takes_shared_package_when_alone() {
	it "remove also takes the shared package once sky is off"
	install_talk
	run features off sky
	: >"$TMP/calls"
	RIG_YES=1 run features remove talk
	assert_has "removed both" "$CALLS" "pacman -Rns -- talk-typer zztalkd-bin" || return
	ok
}

test_remove_declined_without_terminal() {
	it "remove with no terminal and no RIG_YES turns it off and keeps it"
	install_talk
	run features remove talk
	assert_eq "status" "$STATUS" 0 || return
	assert_has "listed" "$OUT" "package  zztalkd-bin" || return
	assert_has "listed data" "$OUT" "files    ~/.local/share/talk" || return
	assert_lacks "no removal" "$CALLS" "-Rns" || return
	assert_has "state" "$(cat "$STATE")" "talk off" || return
	ok
}

test_remove_refuses_outside_home() {
	it "remove never deletes a data path outside \$HOME"
	mkdir -p "$TMP/escape"
	RIG_YES=1 run features remove stray
	assert_has "warned" "$ERR" "refusing to delete" || return
	[[ -d $TMP/escape ]] || { fail "deleted it"; return; }
	ok
}

test_remove_nothing_installed() {
	it "remove of something never installed says so"
	RIG_YES=1 run features remove talk
	assert_eq "status" "$STATUS" 0 || return
	assert_has "said" "$OUT" "nothing installed to remove" || return
	ok
}

# ---- rack setup's question -----------------------------------------------------

owner() {
	OUT=$(
		source "$RACK"
		rack::load features
		rack::features::off_owner "$1"
	)
	STATUS=$?
}

test_off_owner() {
	it "a binary that belongs to an off feature is named, one of an on feature is not"
	owner zztalkd
	assert_eq "talk on" "$STATUS" 1 || return
	run features off talk
	owner zztalkd
	assert_eq "talk off" "$OUT" "talk" || return
	owner jq
	assert_eq "no owner" "$STATUS" 1 || return
	ok
}

# ---- the picker's apply --------------------------------------------------------
#
# The checklist itself needs a terminal; what it does with the ticks does not.

apply() {
	OUT=$(
		source "$RACK"
		set -euo pipefail
		rack::load features
		local -a names=(talk sky stray) ticks=("$@")
		rack::features::__apply "$FIRST" names ticks
	) 2>"$TMP/err"
	STATUS=$?
	ERR=$(cat "$TMP/err")
	CALLS=$(cat "$TMP/calls")
}

test_apply_first_run_writes_every_line() {
	it "the first run writes a line for every feature, ticked or not"
	FIRST=1 apply 0 1 0
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "lines" "$(grep -v '^#' "$STATE" | sort)" $'sky on\nstray off\ntalk off' || return
	assert_lacks "installed nothing" "$CALLS" "-S" || return
	ok
}

test_apply_untick_offers_removal() {
	it "unticking an installed feature turns it off, then offers the removal"
	install_talk
	RIG_YES=1 FIRST=0 apply 0 1 0
	assert_eq "status" "$STATUS" 0 || return
	assert_has "explained" "$OUT" "Talk is off but still installed" || return
	assert_has "removed" "$CALLS" "pacman -Rns -- zztalkd-bin" || return
	ok
}

test_apply_nothing_changed() {
	it "applying the ticks you started with changes nothing"
	install_talk
	FIRST=0 apply 1 1 1
	assert_eq "said" "$OUT" "nothing changed" || return
	assert_eq "no calls" "$CALLS" "" || return
	ok
}

# ---- a feature with nothing to switch off -------------------------------------
#
# kit is lazyvim's shape: `"switch": false`, installed once its probe passes,
# with a setup step that records where it ran.

kit_registry() {
	cat >"$RACK_FEATURES" <<-'EOF'
		{"version": 1, "features": {
		  "kit": {"label": "Kit", "summary": "x", "recommended": false, "switch": false,
		    "provides": ["sh"], "probe": ["sh", "-c", "test -e \"$STUB/pkgs/zzkit\""],
		    "packages": {"repo": ["zzkit"], "aur": []},
		    "setup": [["sh", "-c", "pwd -P >\"$STUB/setup-cwd\""]],
		    "data": ["~/.config/kit"]}
		}}
	EOF
}

test_unswitchable_has_no_off() {
	it "a feature with nothing to switch lists no state and refuses off"
	kit_registry
	run features list
	assert_has "no state" "$OUT" "kit          -    not installed" || return
	run features off kit
	assert_eq "status" "$STATUS" 2 || return
	assert_has "said why" "$ERR" "nothing to switch off" || return
	ok
}

test_setup_runs_from_repo_root() {
	it "setup commands run from the repo root, so a feature can name its own script"
	kit_registry
	run features on kit
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "cwd" "$(cat "$TMP/setup-cwd")" "$(cd "$(dirname "$RACK")/.." && pwd -P)" || return
	assert_has "said" "$OUT$ERR" "kit is installed" || return
	ok
}

test_unswitchable_remove() {
	it "removing a feature with nothing to switch skips off and uninstalls it"
	kit_registry
	"$RACK" features on kit >/dev/null 2>&1 </dev/null
	mkdir -p "$HOME/.config/kit"
	: >"$TMP/calls"
	RIG_YES=1 run features remove kit
	assert_eq "status" "$STATUS" 0 || return
	assert_lacks "no off" "$ERR" "nothing to switch off" || return
	assert_has "uninstalled" "$CALLS" "pacman -Rns -- zzkit" || return
	[[ ! -e $HOME/.config/kit ]] || fail "data: ~/.config/kit is still there"
	ok
}

test_apply_unswitchable() {
	it "in the picker, a feature with nothing to switch is ticked to install and unticked to remove"
	kit_registry
	OUT=$(
		source "$RACK"
		set -euo pipefail
		rack::load features
		local -a names=(kit) ticks=(1)
		rack::features::__apply 0 names ticks
	) 2>"$TMP/err"
	assert_has "installed" "$(cat "$TMP/calls")" "pacman -S --needed zzkit" || return
	: >"$TMP/calls"
	OUT=$(
		source "$RACK"
		set -euo pipefail
		rack::load features
		local -a names=(kit) ticks=(0)
		RIG_YES=1 rack::features::__apply 0 names ticks
	) 2>"$TMP/err"
	assert_lacks "no off" "$(cat "$TMP/err")" "nothing to switch off" || return
	assert_has "removed" "$(cat "$TMP/calls")" "pacman -Rns -- zzkit" || return
	ok
}

# ---- runner ------------------------------------------------------------------

main() {
	[[ -x $RACK ]] || {
		printf 'rack not found or not executable: %s\n' "$RACK" >&2
		exit 1
	}
	make_sys
	trap 'rm -rf "$SYS"' EXIT

	local tests t
	mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_' | sort)

	printf 'rack features\n'
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
