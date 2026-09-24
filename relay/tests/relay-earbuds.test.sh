#!/usr/bin/env bash
# tests for relay's earbuds module: the part that turns Nothing's frames into
# levels.
#
# The watcher itself needs BlueZ and a pair of earbuds, so what is tested here
# is `earbuds.py decode <hex>`, the same frame splitting and battery parsing
# the watcher runs on what comes off the socket. The first frame is a real
# one, captured from an Ear (3) on 2026-09-24; the others are built with the
# module's own encoder and CRC.
#
#   ./tests/relay-earbuds.test.sh          # all tests
#   ./tests/relay-earbuds.test.sh case     # only tests whose name matches "case"
set -uo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
EARBUDS="$ROOT/lib/earbuds.py"

FILTER=${1-}
PASS=0
FAIL=0
FAILURES=()

# Reply to a battery request (0x4007): left 95, right 95, no case.
REAL_REPLY=556001074005000102025f035f0297
# Pushed on a change (0xE001): left 40 and charging, right 38, case 72.
PUSH=55600101e00700000302a8032604481cf8
# REAL_REPLY with its last CRC byte flipped.
BAD_CRC=556001074005000002025f035f0347

decode() { OUT=$(python3 "$EARBUDS" decode "$1" 2>&1); STATUS=$?; }

field() { jq -c "$1" <<<"$OUT"; }

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

it() { CURRENT=$1; }

test_real_reply() {
	it "a real Ear (3) reply gives both buds and no case"
	decode "$REAL_REPLY"
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "left" "$(field .left)" '{"level":95,"charging":false,"stale":false}' || return
	assert_eq "right" "$(field .right.level)" 95 || return
	assert_eq "case" "$(field .case)" null || return
	ok
}

test_push_with_case_and_charging() {
	it "a push carries the case, and the top bit is charging"
	decode "$PUSH"
	assert_eq "left" "$(field .left)" '{"level":40,"charging":true,"stale":false}' || return
	assert_eq "right charging" "$(field .right.charging)" false || return
	assert_eq "case" "$(field .case.level)" 72 || return
	ok
}

test_case_goes_stale() {
	it "a part missing from the next report keeps its level, marked stale"
	decode "$PUSH$REAL_REPLY"
	assert_eq "frames" "$(field .frames)" 2 || return
	assert_eq "case" "$(field .case)" '{"level":72,"charging":false,"stale":true}' || return
	assert_eq "left fresh" "$(field .left)" '{"level":95,"charging":false,"stale":false}' || return
	ok
}

test_resync_and_partial() {
	it "junk before a frame is skipped, and half a frame is kept for later"
	decode "ff00${REAL_REPLY}556001"
	assert_eq "frames" "$(field .frames)" 1 || return
	assert_eq "rest" "$(field .rest)" '"556001"' || return
	ok
}

test_bad_crc_dropped() {
	it "a frame whose CRC does not match is dropped"
	decode "$BAD_CRC"
	assert_eq "frames" "$(field .frames)" 0 || return
	assert_eq "left" "$(field .left)" null || return
	ok
}

test_request_bytes() {
	it "the battery request is the frame the earbuds answered"
	OUT=$(python3 "$EARBUDS" encode)
	assert_eq "request" "$OUT" 55600107c0000001acdf || return
	ok
}

main() {
	command -v jq >/dev/null || {
		printf 'these tests need jq\n' >&2
		exit 127
	}
	local tests t
	mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_' | sort)

	printf 'relay earbuds\n'
	for t in "${tests[@]}"; do
		[[ -n $FILTER && $t != *"$FILTER"* ]] && continue
		CURRENT=$t
		"$t"
	done

	printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
	((FAIL == 0)) || {
		printf '\nfailures:\n'
		printf '  %s\n' "${FAILURES[@]}"
		exit 1
	}
}

main "$@"
