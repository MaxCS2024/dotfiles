#!/usr/bin/env bash
# tests for relay's launcher module
#
# Same shape as relay-toggle.test.sh next door: plain bash, no framework.
# XDG_DATA_HOME points into a temp directory, so a run never touches the
# real ~/.local/share/applications, and RELAY_LAUNCHER_FETCH=0 keeps the
# icon fetch off the network.
#
#   ./tests/relay-launcher.test.sh          # all tests
#   ./tests/relay-launcher.test.sh tui      # only tests whose name matches "tui"
set -uo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
RELAY="$ROOT/relay"

export RIG_COLOR=never
export RIG_LOG_JOURNAL=never
export RELAY_LAUNCHER_FETCH=0

FILTER=${1-}
PASS=0
FAIL=0
FAILURES=()

# ---- harness -----------------------------------------------------------------

setup() {
	TMP=$(mktemp -d)
	export XDG_DATA_HOME="$TMP/data"
	APPS="$XDG_DATA_HOME/applications"
}

teardown() {
	[[ -n ${TMP:-} && -d $TMP ]] && rm -rf "$TMP"
	return 0
}

run() {
	OUT=$("$RELAY" launcher "$@" 2>"$TMP/err")
	STATUS=$?
	ERR=$(cat "$TMP/err")
	return 0
}

# One key's raw line value from a written entry.
key() { sed -n "s/^$2=//p" "$APPS/relay-launcher-$1.desktop"; }

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

# ---- web ---------------------------------------------------------------------

test_web_writes_entry() {
	it "web writes an entry named after the slug"
	run web "Proton Mail" https://mail.proton.me/
	assert_eq "status" "$STATUS" 0 || return
	[[ -f $APPS/relay-launcher-proton-mail.desktop ]] || { fail "no proton-mail entry"; return; }
	assert_eq "name" "$(key proton-mail Name)" "Proton Mail" || return
	assert_eq "kind" "$(key proton-mail X-Relay-Kind)" web || return
	assert_eq "target" "$(key proton-mail X-Relay-Target)" https://mail.proton.me/ || return
	[[ $(key proton-mail Exec) == *" launcher run proton-mail" ]] || { fail "exec: $(key proton-mail Exec)"; return; }
	assert_eq "icon" "$(key proton-mail Icon)" web-browser || return
	ok
}

test_web_rejects_non_http() {
	it "web refuses an address that isn't http(s)"
	run web Evil "file:///etc/passwd"
	assert_eq "status" "$STATUS" 2 || return
	[[ ! -e $APPS ]] || [[ -z $(ls -A "$APPS") ]] || { fail "wrote something anyway"; return; }
	ok
}

test_web_rejects_line_break() {
	it "web refuses a name with a line break"
	run web $'Bad\nExec=rm' https://example.com/
	assert_eq "status" "$STATUS" 2 || return
	ok
}

test_web_rejects_nameless_slug() {
	it "web refuses a name with nothing to slug"
	run web "!!!" https://example.com/
	assert_eq "status" "$STATUS" 2 || return
	ok
}

test_web_same_name_replaces() {
	it "the same name again replaces the entry"
	run web YouTube https://youtube.com/
	run web youtube https://www.youtube.com/
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "target" "$(key youtube X-Relay-Target)" https://www.youtube.com/ || return
	assert_eq "count" "$(ls "$APPS" | wc -l)" 1 || return
	ok
}

# ---- tui ---------------------------------------------------------------------

test_tui_joins_words() {
	it "tui joins the command words into one line"
	run tui "Disk usage" -- ncdu /
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "kind" "$(key disk-usage X-Relay-Kind)" tui || return
	assert_eq "target" "$(key disk-usage X-Relay-Target)" "ncdu /" || return
	ok
}

test_tui_backslash_round_trips() {
	it "a backslash in a command is escaped in the file and read back as one"
	run tui Grep 'grep -r foo\ bar .'
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "raw" "$(key grep X-Relay-Target)" 'grep -r foo\\ bar .' || return
	run list
	assert_eq "list" "$OUT" $'tui\tgrep\tGrep\tgrep -r foo\\ bar .' || return
	ok
}

test_tui_needs_a_command() {
	it "tui with no command is a usage error"
	run tui Lazygit
	assert_eq "status" "$STATUS" 2 || return
	ok
}

# ---- list / remove -----------------------------------------------------------

test_list_prints_tab_rows() {
	it "list prints kind, slug, name, target"
	run web GitHub https://github.com/
	run tui Lazygit lazygit
	run list
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "list" "$OUT" $'web\tgithub\tGitHub\thttps://github.com/\ntui\tlazygit\tLazygit\tlazygit' || return
	ok
}

test_list_empty_is_quiet() {
	it "list with no launchers prints nothing and succeeds"
	run list
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "out" "$OUT" "" || return
	ok
}

test_list_ignores_other_entries() {
	it "list skips desktop files it didn't write"
	mkdir -p "$APPS"
	printf '[Desktop Entry]\nName=Other\n' >"$APPS/relay-launcher-other.desktop"
	printf '[Desktop Entry]\nName=Firefox\n' >"$APPS/firefox.desktop"
	run list
	assert_eq "out" "$OUT" "" || return
	ok
}

test_remove_by_name() {
	it "remove takes the label and deletes the entry"
	run web "Proton Mail" https://mail.proton.me/
	run remove "Proton Mail"
	assert_eq "status" "$STATUS" 0 || return
	[[ ! -e $APPS/relay-launcher-proton-mail.desktop ]] || { fail "still there"; return; }
	ok
}

test_remove_missing_fails() {
	it "remove of something that isn't there fails"
	run remove Nothing
	assert_eq "status" "$STATUS" 1 || return
	ok
}

test_run_missing_fails() {
	it "run of something that isn't there fails"
	run run nothing
	assert_eq "status" "$STATUS" 1 || return
	ok
}

# ---- runner ------------------------------------------------------------------

main() {
	[[ -x $RELAY ]] || {
		printf 'relay not found or not executable: %s\n' "$RELAY" >&2
		exit 1
	}

	local tests t
	mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_' | sort)

	printf 'relay launcher\n'
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
