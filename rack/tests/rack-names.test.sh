#!/usr/bin/env bash
# tests for how rack's commands take entry names: diff, reload and validate
#
# The same harness as rack-deploy.test.sh: a fresh HOME, dotfiles tree and
# manifest per test, and the real `rack` command run against them. deploy's
# own names are covered there; this is the rest of the commands that take a
# list of entries, and what they do with one that isn't in the manifest —
# which, until 2026-09-24, was log it and then report success ("everything
# matches the manifest", "nothing to reload") because the selection's
# status was lost in a process substitution.
#
#   ./tests/rack-names.test.sh           # all tests
#   ./tests/rack-names.test.sh reload    # only tests whose name matches
set -uo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
RACK="$ROOT/rack"

FILTER=${1-}
PASS=0
FAIL=0
FAILURES=()

ORIG_HOME=$HOME
ORIG_TMPDIR=${TMPDIR:-/tmp}

# ---- harness -----------------------------------------------------------------

setup() {
	# Stop dead if this fails: every path below is "$TMP/...".
	TMP=$(TMPDIR=$ORIG_TMPDIR mktemp -d) && [[ -d $TMP && $TMP == "$ORIG_TMPDIR"/* ]] || {
		printf 'harness error: cannot make a temp directory\n' >&2
		exit 1
	}
	DOTS="$TMP/dots"
	mkdir -p "$TMP/home" "$DOTS/rack" "$TMP/runtime"

	export HOME="$TMP/home"
	export RACK_MANIFEST="$DOTS/rack/manifest.conf"
	export XDG_RUNTIME_DIR="$TMP/runtime"
	export RIG_COLOR=never RIG_LOG_JOURNAL=never
	unset RACK_DOTFILES RIG_DRY_RUN
	: >"$RACK_MANIFEST"

	# One entry of each kind these commands care about: a script the
	# validator can check with bash -n, whose reload command leaves a mark.
	mkdir -p "$DOTS/tool"
	printf '#!/bin/sh\necho hi\n' >"$DOTS/tool/run.sh"
	printf 'tool  ~/.config/tool  touch %s/reloaded\n' "$TMP" >>"$RACK_MANIFEST"
}

teardown() {
	export HOME="$ORIG_HOME"
	[[ -n ${TMP:-} && -d $TMP ]] && rm -rf "$TMP"
	return 0
}

run() {
	OUT=$("$RACK" "$@" 2>"$TMP/err")
	STATUS=$?
	ERR=$(cat "$TMP/err")
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

it() { CURRENT=$1; }

# ---- diff --------------------------------------------------------------------

test_diff_unknown_name() {
	it "diff refuses a name that isn't in the manifest"
	run diff tol
	assert_eq "status" "$STATUS" 2 || return
	assert_has "said" "$ERR" "not in the manifest: tol" || return
	[[ $ERR == *"everything matches"* ]] && { fail "reported a match: [$ERR]"; return; }
	ok
}

test_diff_known_name() {
	it "diff still reports drift for a name that is there"
	run diff tool
	assert_eq "status" "$STATUS" 1 || return
	assert_has "said" "$OUT" "not deployed" || return
	ok
}

test_diff_everything() {
	it "diff with no names still checks every entry"
	run diff
	assert_eq "status" "$STATUS" 1 || return
	assert_has "said" "$OUT" "tool" || return
	ok
}

# ---- reload ------------------------------------------------------------------

test_reload_unknown_name() {
	it "reload refuses a name that isn't in the manifest"
	run reload tol
	assert_eq "status" "$STATUS" 2 || return
	assert_has "said" "$ERR" "not in the manifest: tol" || return
	ok
}

test_reload_mixed_names_runs_nothing() {
	it "one unknown name among known ones reloads nothing"
	run reload tool tol
	assert_eq "status" "$STATUS" 2 || return
	[[ -e $TMP/reloaded ]] && { fail "ran tool's reload anyway"; return; }
	ok
}

test_reload_known_name() {
	it "reload still runs a known entry's command"
	run reload tool
	assert_eq "status" "$STATUS" 0 || return
	[[ -e $TMP/reloaded ]] || { fail "did not run the reload command"; return; }
	ok
}

test_reload_list_unknown_name() {
	it "reload list refuses an unknown name too"
	run reload list tol
	assert_eq "status" "$STATUS" 2 || return
	ok
}

test_reload_empty_manifest() {
	it "an empty manifest is nothing to reload, not an entry with no name"
	: >"$RACK_MANIFEST"
	run reload
	assert_eq "status" "$STATUS" 0 || return
	assert_has "said" "$ERR" "nothing to reload" || return
	ok
}

# ---- validate ----------------------------------------------------------------

test_validate_unknown_name() {
	it "validate refuses a name that isn't in the manifest"
	run validate tol
	assert_eq "status" "$STATUS" 2 || return
	assert_has "said" "$ERR" "not in the manifest: tol" || return
	[[ $ERR == *"nothing obviously broken"* ]] && { fail "reported success: [$ERR]"; return; }
	ok
}

test_validate_known_name() {
	it "validate still checks a known entry"
	run validate tool
	assert_eq "status" "$STATUS" 0 || return
	assert_has "said" "$OUT" "tool" || return
	ok
}

test_validate_empty_manifest() {
	it "an empty manifest validates nothing, and says nothing is broken"
	: >"$RACK_MANIFEST"
	run validate
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "no rows" "$OUT" "" || return
	ok
}

# ---- runner ------------------------------------------------------------------

main() {
	[[ -x $RACK ]] || {
		printf 'rack not found or not executable: %s\n' "$RACK" >&2
		exit 1
	}

	local tests t
	mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_' | sort)

	printf 'rack names (diff, reload, validate)\n'
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
