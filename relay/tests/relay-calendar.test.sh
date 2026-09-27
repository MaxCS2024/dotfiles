#!/usr/bin/env bash
# tests for relay's calendar module: how the card's add line is read.
#
# Listing, adding and deleting need evolution-data-server running, so what is
# tested here is `calendar.py parse DATE TEXT`, the same reading `add` makes
# of what was typed before it hands the event to EDS.
#
#   ./tests/relay-calendar.test.sh          # all tests
#   ./tests/relay-calendar.test.sh range    # only tests whose name matches "range"
set -uo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
CALENDAR="$ROOT/lib/calendar.py"

FILTER=${1-}
PASS=0
FAIL=0
FAILURES=()

DAY=2026-09-28

parse() { OUT=$(python3 "$CALENDAR" parse "$DAY" "$1" 2>&1); STATUS=$?; }

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

test_start_only() {
	it "a start and no end lasts an hour"
	parse "14:00 Tandläkare"
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "event" "$OUT" '{"title": "Tandläkare", "allDay": false, "start": "2026-09-28T14:00", "end": "2026-09-28T15:00"}' || return
	ok
}

test_range_with_dot_and_bare_end() {
	it "a range may use a dot, and its end may be a bare hour"
	parse "9.30-10 Möte"
	assert_eq "start" "$(field .start)" '"2026-09-28T09:30"' || return
	assert_eq "end" "$(field .end)" '"2026-09-28T10:00"' || return
	assert_eq "title" "$(field .title)" '"Möte"' || return
	ok
}

test_range_of_bare_hours() {
	it "a range of two bare hours is a time, and an en dash works too"
	parse "8–9 Frukost"
	assert_eq "all day" "$(field .allDay)" false || return
	assert_eq "start" "$(field .start)" '"2026-09-28T08:00"' || return
	assert_eq "end" "$(field .end)" '"2026-09-28T09:00"' || return
	ok
}

test_range_past_midnight() {
	it "an end before the start is the next day"
	parse "22-01 Nattåg"
	assert_eq "end" "$(field .end)" '"2026-09-29T01:00"' || return
	ok
}

test_bare_hour_is_a_title() {
	it "a bare hour with no range is part of the title"
	parse "14 dagar kvar"
	assert_eq "all day" "$(field .allDay)" true || return
	assert_eq "title" "$(field .title)" '"14 dagar kvar"' || return
	ok
}

test_impossible_time_is_a_title() {
	it "a time that can't be (25:00) is part of the title"
	parse "25:00 Fel"
	assert_eq "all day" "$(field .allDay)" true || return
	assert_eq "title" "$(field .title)" '"25:00 Fel"' || return
	ok
}

test_all_day_ends_next_day() {
	it "an all-day event ends, exclusively, on the next day"
	parse "  Mammas födelsedag "
	assert_eq "title" "$(field .title)" '"Mammas födelsedag"' || return
	assert_eq "start" "$(field .start)" '"2026-09-28"' || return
	assert_eq "end" "$(field .end)" '"2026-09-29"' || return
	ok
}

test_month_end() {
	it "an all-day event on the last of a month ends on the first of the next"
	DAY=2026-12-31 parse "Nyårsafton"
	assert_eq "end" "$(field .end)" '"2027-01-01"' || return
	ok
}

test_bad_date() {
	it "a date that isn't one is a usage error"
	DAY=2026-02-30 parse "x"
	assert_eq "status" "$STATUS" 2 || return
	ok
}

main() {
	command -v jq >/dev/null || {
		printf 'these tests need jq\n' >&2
		exit 127
	}
	local tests t
	mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_' | sort)

	printf 'relay calendar\n'
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
