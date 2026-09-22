#!/usr/bin/env bash
# tests for relay's notif module
#
# Plain bash, no test framework — nothing to install, runs anywhere the repo
# does. Run it directly:
#
#   ./test/relay-notif.test.sh          # all tests
#   ./test/relay-notif.test.sh send     # only tests whose name matches "send"
#
# `busctl` and `qs` are stubbed on PATH, so nothing here touches the real D-Bus
# session or the running shell: a test run can't send you a notification, clear
# your history, or flip your DND. The stubs record their argv, and the
# assertions check the exact D-Bus vector relay notif builds — which is where
# all the parsing logic that matters actually lands.
# Exit codes are rig's, not orbit's: 2 for a usage error and 127 for a missing
# dependency, where orbit exited 1 for everything. That distinction is the
# point of the convention — a script can tell "you typed it wrong" from "the
# machine is missing a tool" from "the bus said no".
set -uo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
RELAY="$ROOT/relay"

# rig prints through its log module; colour would land in the asserted stderr.
export RIG_COLOR=never
export RIG_LOG_JOURNAL=never

FILTER=${1-}
PASS=0
FAIL=0
FAILURES=()

# Tests are free to narrow PATH (see setup_without_busctl), so the harness
# keeps its own copy to restore from. Without this, a test that takes away
# busctl also takes away mktemp from every test that runs after it.
ORIG_PATH=$PATH

# ---- harness -----------------------------------------------------------------

setup() {
	export PATH="$ORIG_PATH"
	TMP=$(mktemp -d)
	CAPTURE="$TMP/capture"
	mkdir -p "$TMP/bin"

	# One captured argument per line, so assertions can index into the vector
	# by position instead of pattern-matching a flattened string.
	cat >"$TMP/bin/busctl" <<-'EOF'
		#!/usr/bin/env bash
		printf '%s\n' "$@" > "$RELAY_TEST_CAPTURE"
		[[ -n ${RELAY_TEST_BUSCTL_FAIL:-} ]] && exit 1
		echo "u 42"
	EOF

	# Answers `qs -c <cfg> ipc call notifications <fn> [args]`. The reply is
	# whatever RELAY_TEST_QS_OUT holds, so a test can drive the CLI's parsing
	# of a response without a shell running.
	cat >"$TMP/bin/qs" <<-'EOF'
		#!/usr/bin/env bash
		printf '%s\n' "$@" > "$RELAY_TEST_CAPTURE"
		[[ -n ${RELAY_TEST_QS_FAIL:-} ]] && exit 1
		printf '%s\n' "${RELAY_TEST_QS_OUT:-ok}"
	EOF

	chmod +x "$TMP/bin/busctl" "$TMP/bin/qs"
	export RELAY_TEST_CAPTURE="$CAPTURE"
	export PATH="$TMP/bin:/usr/bin:/bin"
	unset RELAY_TEST_BUSCTL_FAIL RELAY_TEST_QS_FAIL RELAY_TEST_QS_OUT

	# The stubs are only protection if they are the ones actually found. A
	# test that shadows PATH incorrectly would otherwise reach the real bus
	# and put a notification on the user's screen — which is exactly what
	# happened before this check existed.
	local resolved
	resolved=$(command -v busctl)
	[[ $resolved == "$TMP/"* ]] || {
		printf 'harness error: busctl resolves to %s, not the stub\n' "$resolved" >&2
		exit 1
	}
}

# A PATH with no busctl on it at all, for the "not installed" branch. Removing
# the stub is not enough: /usr/bin is still on PATH behind it, so the real
# busctl would be found and the test would talk to the live session bus.
# Symlinking only what relay notif needs is the only way to genuinely take
# busctl away.
setup_without_busctl() {
	local nobus="$TMP/nobus" tool src
	mkdir -p "$nobus"
	# bash and env matter as much as the rest: the shebang is
	# `#!/usr/bin/env bash`, and env resolves bash through PATH.
	for tool in bash env readlink dirname basename cat sed awk grep tr head tail cut wc jq date; do
		src=$(command -v "$tool" 2>/dev/null) || continue
		ln -sf "$src" "$nobus/$tool"
	done
	ln -sf "$TMP/bin/qs" "$nobus/qs"
	export PATH="$nobus"
	command -v busctl >/dev/null && {
		printf 'harness error: busctl still reachable on the restricted PATH\n' >&2
		exit 1
	}
	return 0
}

teardown() {
	export PATH="$ORIG_PATH"
	[[ -n ${TMP:-} && -d $TMP ]] && rm -rf "$TMP"
	return 0
}

# Run relay notif, capturing stdout, stderr and status separately.
run() {
	OUT=$("$RELAY" notif "$@" 2>"$TMP/err")
	STATUS=$?
	ERR=$(cat "$TMP/err")
	return 0
}

# nth captured argument, 1-based.
field() { sed -n "${1}p" "$CAPTURE"; }
last_field() { tail -n1 "$CAPTURE"; }
field_count() { wc -l <"$CAPTURE" | tr -d ' '; }

# Index of the first captured argument equal to $1, or "" if absent. Hint
# positions shift as flags are added, so hint assertions look the key up rather
# than hardcoding an offset.
index_of() { grep -nxF -- "$1" "$CAPTURE" 2>/dev/null | head -1 | cut -d: -f1; }

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

# A test is a function named test_<something>; `it` names the current one.
it() { CURRENT=$1; }

# ---- send: the D-Bus vector --------------------------------------------------

# Fixed prefix of the busctl call, so field numbers below are stable:
#   1 --user   2 --   3 call   4 dest   5 path   6 iface   7 Notify
#   8 signature   9 app_name   10 replaces_id   11 app_icon
#   12 summary   13 body   14 actions-count   15 hint-count   ... last: timeout
readonly F_APP=9 F_REPLACES=10 F_ICON=11 F_SUMMARY=12 F_BODY=13 F_HINTCOUNT=15

test_send_basic() {
	it "send builds the Notify vector"
	run send "Theme updated" "regenerated from wall.png" || true
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "app_name" "$(field $F_APP)" "relay" || return
	assert_eq "summary" "$(field $F_SUMMARY)" "Theme updated" || return
	assert_eq "body" "$(field $F_BODY)" "regenerated from wall.png" || return
	assert_eq "replaces_id" "$(field $F_REPLACES)" "0" || return
	assert_eq "expire_timeout" "$(last_field)" "-1" || return
	ok
}

test_send_urgency_mapping() {
	it "send maps urgency names to D-Bus bytes"
	local level byte
	for level in low:0 normal:1 critical:2; do
		byte=${level#*:}
		level=${level%:*}
		run send "S" -u "$level" || true
		local i
		i=$(index_of urgency)
		assert_eq "$level byte" "$(field $((i + 2)))" "$byte" || return
	done
	ok
}

test_send_default_urgency_is_normal() {
	it "send defaults to normal urgency"
	run send "S" || true
	local i
	i=$(index_of urgency)
	assert_eq "byte" "$(field $((i + 2)))" "1" || return
	ok
}

test_send_rejects_bad_urgency() {
	it "send rejects an unknown urgency"
	run send "S" -u screaming || true
	assert_eq "status" "$STATUS" 2 || return
	[[ $ERR == *"unknown urgency"* ]] || { fail "expected an 'unknown urgency' message, got: $ERR"; return; }
	ok
}

# ---- send: injection resistance ----------------------------------------------
#
# The reason this command talks to busctl instead of notify-send. A summary is
# data no matter what it looks like.

test_send_summary_that_looks_like_a_hint() {
	it "send keeps a hint-shaped summary as one positional"
	run send "--hint=urgency:byte:2 pwned" || true
	assert_eq "summary" "$(field $F_SUMMARY)" "--hint=urgency:byte:2 pwned" || return
	# urgency is the only hint, so the count must still be 1.
	assert_eq "hint count" "$(field $F_HINTCOUNT)" "1" || return
	ok
}

test_send_body_may_start_with_a_dash() {
	it "send treats a dash-leading body as text, not options"
	run send "Volume" "-3 dB" || true
	assert_eq "body" "$(field $F_BODY)" "-3 dB" || return
	ok
}

test_send_real_flag_in_body_slot_is_not_a_body() {
	it "send leaves body empty when a real flag follows the summary"
	run send "Only a summary" -u low || true
	assert_eq "body" "$(field $F_BODY)" "" || return
	ok
}

# ---- send: hints -------------------------------------------------------------

test_send_glyph_hint() {
	it "send attaches the relay-glyph hint"
	run send "S" -g "X" || true
	local i
	i=$(index_of "relay-glyph")
	[[ -n $i ]] || { fail "relay-glyph hint not sent"; return; }
	assert_eq "type" "$(field $((i + 1)))" "s" || return
	assert_eq "value" "$(field $((i + 2)))" "X" || return
	assert_eq "hint count" "$(field $F_HINTCOUNT)" "2" || return
	ok
}

test_send_image_and_transient_hints() {
	it "send attaches image-path and transient hints"
	run send "S" --image /tmp/a.png --transient || true
	local i
	i=$(index_of "image-path")
	[[ -n $i ]] || { fail "image-path hint not sent"; return; }
	assert_eq "image" "$(field $((i + 2)))" "/tmp/a.png" || return
	i=$(index_of "transient")
	[[ -n $i ]] || { fail "transient hint not sent"; return; }
	assert_eq "transient" "$(field $((i + 2)))" "true" || return
	assert_eq "hint count" "$(field $F_HINTCOUNT)" "3" || return
	ok
}

test_send_flag_equals_value_form() {
	it "send accepts --flag=value as well as --flag value"
	run send "S" --urgency=critical --app-name=probe || true
	assert_eq "app_name" "$(field $F_APP)" "probe" || return
	local i
	i=$(index_of urgency)
	assert_eq "byte" "$(field $((i + 2)))" "2" || return
	ok
}

# ---- send: --exec ------------------------------------------------------------

test_exec_becomes_an_argv_vector() {
	it "--exec ships a JSON argv vector, not a shell string"
	run send "Build failed" --exec foot -e journalctl -xe || true
	local i
	i=$(index_of "relay-exec-argv")
	[[ -n $i ]] || { fail "relay-exec-argv hint not sent"; return; }
	assert_eq "argv" "$(field $((i + 2)))" '["foot","-e","journalctl","-xe"]' || return
	ok
}

test_exec_swallows_later_orbit_flags() {
	it "--exec passes later flags to the target program, not to orbit"
	run send "Report" --exec myprog --json --help || true
	local i
	i=$(index_of "relay-exec-argv")
	assert_eq "argv" "$(field $((i + 2)))" '["myprog","--json","--help"]' || return
	ok
}

test_exec_preserves_arguments_containing_spaces() {
	it "--exec keeps a spaced argument as one element"
	run send "S" --exec notify-me "two words" || true
	local i
	i=$(index_of "relay-exec-argv")
	assert_eq "argv" "$(field $((i + 2)))" '["notify-me","two words"]' || return
	ok
}

test_exec_rejects_a_single_quoted_command() {
	it "--exec rejects one quoted string instead of splitting it"
	run send "S" --exec "foot -e htop" || true
	assert_eq "status" "$STATUS" 2 || return
	[[ $ERR == *"separate words"* ]] || { fail "expected a 'separate words' message, got: $ERR"; return; }
	ok
}

test_exec_requires_a_command() {
	it "--exec with nothing after it is an error"
	run send "S" --exec || true
	assert_eq "status" "$STATUS" 2 || return
	ok
}

# ---- send: ids and validation ------------------------------------------------

test_print_id() {
	it "-p prints the id busctl returned"
	run send "S" -p || true
	assert_eq "stdout" "$OUT" "42" || return
	ok
}

test_no_print_id_by_default() {
	it "send is silent without -p"
	run send "S" || true
	assert_eq "stdout" "$OUT" "" || return
	ok
}

test_replace_id() {
	it "-r sets replaces_id"
	run send "S" -r 7 || true
	assert_eq "replaces_id" "$(field $F_REPLACES)" "7" || return
	ok
}

test_rejects_non_numeric_replace_id() {
	it "-r rejects a non-numeric id"
	run send "S" -r abc || true
	assert_eq "status" "$STATUS" 2 || return
	ok
}

test_rejects_non_numeric_expire_time() {
	it "-t rejects a non-numeric timeout"
	run send "S" -t soon || true
	assert_eq "status" "$STATUS" 2 || return
	ok
}

test_expire_time_passes_through_as_milliseconds() {
	it "-t is passed through untouched"
	run send "S" -t 3000 || true
	assert_eq "expire_timeout" "$(last_field)" "3000" || return
	ok
}

# ---- send: degradation -------------------------------------------------------

test_send_survives_a_missing_bus() {
	it "send falls back to stderr and exits 0 when the bus is unreachable"
	RELAY_TEST_BUSCTL_FAIL=1 run send "Dotfiles synced" "pulled and relinked" || true
	assert_eq "status" "$STATUS" 0 || return
	[[ $ERR == *"Dotfiles synced"*"pulled and relinked"* ]] ||
		{ fail "expected the message on stderr, got: $ERR"; return; }
	ok
}

test_send_survives_no_busctl_at_all() {
	it "send falls back when busctl is not installed"
	setup_without_busctl
	run send "Theme updated" "regenerated" || true
	assert_eq "status" "$STATUS" 0 || return
	[[ $ERR == *"Theme updated"*"regenerated"* ]] ||
		{ fail "expected the message on stderr, got: $ERR"; return; }
	ok
}

# ---- IPC subcommands ---------------------------------------------------------

test_dnd_reads_state() {
	it "dnd with no argument reports the current state"
	RELAY_TEST_QS_OUT=on run dnd || true
	assert_eq "stdout" "$OUT" "on" || return
	assert_eq "ipc fn" "$(last_field)" "dndState" || return
	ok
}

test_dnd_toggle_and_set() {
	it "dnd on/off/toggle call the right IPC function"
	RELAY_TEST_QS_OUT=on run dnd toggle || true
	assert_eq "toggle fn" "$(last_field)" "toggleDnd" || return

	RELAY_TEST_QS_OUT=on run dnd on || true
	assert_eq "on arg" "$(last_field)" "true" || return

	RELAY_TEST_QS_OUT=off run dnd off || true
	assert_eq "off arg" "$(last_field)" "false" || return
	ok
}

test_dnd_json() {
	it "dnd --json emits a JSON object"
	RELAY_TEST_QS_OUT=on run dnd --json || true
	assert_eq "stdout" "$OUT" '{"dnd":true}' || return
	RELAY_TEST_QS_OUT=off run dnd --json || true
	assert_eq "stdout" "$OUT" '{"dnd":false}' || return
	ok
}

test_dnd_rejects_unknown_action() {
	it "dnd rejects an unknown action"
	run dnd maybe || true
	assert_eq "status" "$STATUS" 2 || return
	ok
}

test_dismiss_targets() {
	it "dismiss maps last/all to the right IPC function"
	run dismiss || true
	assert_eq "default" "$(last_field)" "dismissLast" || return
	run dismiss all || true
	assert_eq "all" "$(last_field)" "dismissAll" || return
	ok
}

test_dismiss_rejects_unknown_target() {
	it "dismiss rejects an unknown target"
	run dismiss everything || true
	assert_eq "status" "$STATUS" 2 || return
	ok
}

test_invoke() {
	it "invoke calls invokeLast"
	run invoke || true
	assert_eq "ipc fn" "$(last_field)" "invokeLast" || return
	ok
}

test_ipc_uses_configured_shell() {
	it "RELAY_QS_CONFIG selects which quickshell config to talk to"
	RELAY_QS_CONFIG=my-experiment run invoke || true
	local i
	i=$(index_of "-c")
	assert_eq "config" "$(field $((i + 1)))" "my-experiment" || return
	ok
}

test_ipc_fails_clearly_when_shell_is_down() {
	it "an IPC command explains itself when no shell is running"
	RELAY_TEST_QS_FAIL=1 run dnd || true
	assert_eq "status" "$STATUS" 1 || return
	[[ $ERR == *"not running"* ]] || { fail "expected a 'not running' message, got: $ERR"; return; }
	ok
}

test_history_json_passthrough() {
	it "history --json emits the rows as JSON"
	RELAY_TEST_QS_OUT='[{"id":1,"appName":"relay","summary":"S","body":"","time":0}]' \
		run history --json || true
	[[ $OUT == *'"appName"'* ]] || { fail "expected JSON rows, got: $OUT"; return; }
	ok
}

test_history_human_output() {
	it "history renders one line per row"
	RELAY_TEST_QS_OUT='[{"id":1,"appName":"relay","summary":"Theme updated","body":"from wall.png","time":0}]' \
		run history || true
	[[ $OUT == *"relay"*"Theme updated"*"from wall.png"* ]] ||
		{ fail "expected a rendered row, got: $OUT"; return; }
	ok
}

test_list_marks_restored_popups() {
	it "list flags a popup restored from disk"
	RELAY_TEST_QS_OUT='[{"urgency":"critical","appName":"relay","summary":"S","body":"","restored":true}]' \
		run list || true
	[[ $OUT == *"(restored)"* ]] || { fail "expected a (restored) marker, got: $OUT"; return; }
	ok
}

# ---- dispatch ----------------------------------------------------------------

test_help_exits_zero() {
	it "help succeeds and describes the subcommands"
	# `relay help <mod>` rather than a per-module --help: the dispatcher owns
	# help, so a module never sees the flag.
	OUT=$("$RELAY" help notif 2>"$TMP/err")
	STATUS=$?
	assert_eq "status" "$STATUS" 0 || return
	[[ $OUT == *"send <summary>"* && $OUT == *"dnd"* ]] ||
		{ fail "help text looks wrong"; return; }
	ok
}

test_unknown_command_fails() {
	it "an unknown subcommand is an error"
	run frobnicate || true
	assert_eq "status" "$STATUS" 2 || return
	[[ $ERR == *"has no action"* ]] || { fail "expected 'unknown command', got: $ERR"; return; }
	ok
}

test_send_with_no_summary_fails() {
	it "send with no summary is a usage error"
	run send || true
	assert_eq "status" "$STATUS" 2 || return
	ok
}

# ---- runner ------------------------------------------------------------------

main() {
	[[ -x "$RELAY" ]] || {
		printf 'relay not found or not executable: %s\n' "$RELAY" notif >&2
		exit 1
	}
	command -v jq >/dev/null || {
		printf 'these tests need jq (relay notif uses it for --exec and history)\n' >&2
		exit 1
	}

	local tests t
	mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_' | sort)

	printf 'relay notif\n'
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
