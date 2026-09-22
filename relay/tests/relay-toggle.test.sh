#!/usr/bin/env bash
# tests for relay's toggle module
#
# Same shape as relay-notif.test.sh next door: plain bash, no framework, and a
# stubbed `qs` on PATH so a test run can never reach the real shell. That
# matters more here than anywhere else in the repo — every command under test
# is one that hides the user's bar or flips their do-not-disturb, and a run
# that escaped the stub would do exactly that.
#
#   ./test/relay-toggle.test.sh          # all tests
#   ./test/relay-toggle.test.sh json     # only tests whose name matches "json"
#
# The stub records its argv one word per line, so the assertions check the
# exact `qs ipc call` vector the command builds. That vector is the whole of
# what this command does, so it is the whole of what is worth asserting.
# Exit codes are rig's, not orbit's: 2 for a usage error and 127 for a missing
# dependency, where orbit exited 1 for everything. That distinction is the
# point of the convention — a script can tell "you typed it wrong" from "the
# machine is missing a tool" from "the thing it drives said no".
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

ORIG_PATH=$PATH

# ---- harness -----------------------------------------------------------------

setup() {
	export PATH="$ORIG_PATH"
	TMP=$(mktemp -d)
	CAPTURE="$TMP/capture"
	mkdir -p "$TMP/bin"

	# Answers `qs -c <cfg> ipc call <target> <fn> [args]`. The reply is
	# whatever RELAY_TEST_QS_OUT holds, so a test can drive the command's
	# handling of a response without a shell running.
	cat >"$TMP/bin/qs" <<-'EOF'
		#!/usr/bin/env bash
		printf '%s\n' "$@" > "$RELAY_TEST_CAPTURE"
		[[ -n ${RELAY_TEST_QS_FAIL:-} ]] && exit 1
		printf '%s\n' "${RELAY_TEST_QS_OUT-on}"
	EOF

	chmod +x "$TMP/bin/qs"
	export RELAY_TEST_CAPTURE="$CAPTURE"
	export PATH="$TMP/bin:/usr/bin:/bin"
	unset RELAY_TEST_QS_FAIL RELAY_QS_CONFIG
	export RELAY_TEST_QS_OUT=on

	# The stub is only protection if it is the one actually found. Without
	# this check a botched PATH would reach the real shell and hide the bar
	# of whoever ran the tests.
	local resolved
	resolved=$(command -v qs)
	[[ $resolved == "$TMP/"* ]] || {
		printf 'harness error: qs resolves to %s, not the stub\n' "$resolved" >&2
		exit 1
	}
}

# A PATH with no qs on it at all, for the "not installed" branch. Removing the
# stub is not enough: /usr/bin is still behind it, so the real qs would be
# found. Symlinking only what relay needs is the only way to genuinely
# take qs away.
setup_without_qs() {
	local noqs="$TMP/noqs" tool src
	mkdir -p "$noqs"
	# bash and env matter as much as the rest: the shebang is
	# `#!/usr/bin/env bash`, and env resolves bash through PATH.
	for tool in bash env readlink dirname basename cat sed tr head; do
		src=$(command -v "$tool" 2>/dev/null) || continue
		ln -sf "$src" "$noqs/$tool"
	done
	export PATH="$noqs"
	command -v qs >/dev/null && {
		printf 'harness error: qs still reachable on the restricted PATH\n' >&2
		exit 1
	}
	return 0
}

teardown() {
	export PATH="$ORIG_PATH"
	[[ -n ${TMP:-} && -d $TMP ]] && rm -rf "$TMP"
	return 0
}

# Run `relay toggle`, capturing stdout, stderr and status separately.
run() {
	OUT=$("$RELAY" toggle "$@" 2>"$TMP/err")
	STATUS=$?
	ERR=$(cat "$TMP/err")
	return 0
}

# The captured argv as one space-joined line, which is what the vector
# assertions want to compare against.
captured() { tr '\n' ' ' <"$CAPTURE" 2>/dev/null | sed 's/ $//'; }

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

# ---- the ipc vector ----------------------------------------------------------

test_bar_toggle_vector() {
	it "bare subject flips it"
	run bar
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "argv" "$(captured)" "-c main ipc call bar toggle" || return
	ok
}

test_bar_on_vector() {
	it "on maps to the bar's open, not a show it would swallow"
	run bar on
	assert_eq "argv" "$(captured)" "-c main ipc call bar open" || return
	ok
}

test_bar_off_vector() {
	it "off maps to the bar's close"
	run bar off
	assert_eq "argv" "$(captured)" "-c main ipc call bar close" || return
	ok
}

test_bar_status_vector() {
	it "status asks without changing anything"
	run bar status
	assert_eq "argv" "$(captured)" "-c main ipc call bar state" || return
	ok
}

test_dnd_toggle_vector() {
	it "dnd reaches the notifications target, not a target of its own"
	run dnd
	assert_eq "argv" "$(captured)" "-c main ipc call notifications toggleDnd" || return
	ok
}

test_dnd_on_passes_its_argument() {
	it "a setter with an argument stays two words, not one"
	run dnd on
	assert_eq "argv" "$(captured)" "-c main ipc call notifications setDnd true" || return
	ok
}

test_dnd_off_passes_its_argument() {
	it "dnd off sends the false argument"
	run dnd off
	assert_eq "argv" "$(captured)" "-c main ipc call notifications setDnd false" || return
	ok
}

test_nightlight_vectors() {
	it "nightlight uses enable/disable, not the bar's open/close"
	run nightlight
	assert_eq "toggle" "$(captured)" "-c main ipc call nightlight toggle" || return
	run nightlight on
	assert_eq "on" "$(captured)" "-c main ipc call nightlight enable" || return
	run nightlight off
	assert_eq "off" "$(captured)" "-c main ipc call nightlight disable" || return
	run nightlight status
	assert_eq "status" "$(captured)" "-c main ipc call nightlight state" || return
	ok
}

test_awake_vectors() {
	it "awake reaches its own target with the same verbs"
	run awake
	assert_eq "toggle" "$(captured)" "-c main ipc call awake toggle" || return
	run awake on
	assert_eq "on" "$(captured)" "-c main ipc call awake enable" || return
	run awake off
	assert_eq "off" "$(captured)" "-c main ipc call awake disable" || return
	ok
}

# The polarity trap this naming exists to avoid: `idle` and `awake` are
# opposites, so the wrong one must not silently do the right-looking thing.
test_idle_is_redirected_not_guessed() {
	it "idle points at awake instead of guessing a polarity"
	run idle
	assert_eq "status" "$STATUS" 2 || return
	[[ -s $CAPTURE ]] && { fail "called the shell anyway: [$(captured)]"; return; }
	[[ $ERR == *awake* ]] || { fail "expected a pointer to awake, got [$ERR]"; return; }
	ok
}

test_suggestions_do_not_leak_into_the_subject_list() {
	it "a suggested name is not itself a subject"
	OUT=$("$RELAY" help toggle 2>"$TMP/err")
	# `relay help <mod>` prints the module's action list as well as its usage
	# block, and a suggestion must appear in neither: the list is what shell
	# completion offers, so a name leaking into it is a name people will type.
	[[ $OUT == *"  idle"* || $OUT == *"actions:"*"idle"* ]] &&
		{ fail "idle listed as a real subject: [$OUT]"; return; }
	[[ $OUT == *nightlight* && $OUT == *awake* ]] || { fail "new subjects missing from help: [$OUT]"; return; }
	ok
}

test_config_override() {
	it "RELAY_QS_CONFIG picks the config to talk to"
	RELAY_QS_CONFIG=experiment run bar
	assert_eq "argv" "$(captured)" "-c experiment ipc call bar toggle" || return
	ok
}

# ---- output ------------------------------------------------------------------

test_prints_the_state_it_was_given() {
	it "prints the state the shell answered with"
	RELAY_TEST_QS_OUT=off run bar
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "stdout" "$OUT" "off" || return
	ok
}

test_json_true() {
	it "--json renders on as true"
	RELAY_TEST_QS_OUT=on run bar --json
	assert_eq "stdout" "$OUT" '{"bar":true}' || return
	ok
}

test_json_false() {
	it "--json renders off as false, under the subject's own name"
	RELAY_TEST_QS_OUT=off run dnd --json
	assert_eq "stdout" "$OUT" '{"dnd":false}' || return
	ok
}

test_no_arguments_prints_usage() {
	it "no subject prints the module's help"
	run
	assert_eq "status" "$STATUS" 2 || return
	[[ $OUT == *"relay toggle <subject>"* ]] ||
		{ fail "expected the usage block on stdout, got [$OUT]"; return; }
	ok
}

test_help_lists_every_subject() {
	it "help lists the subjects from the table"
	OUT=$("$RELAY" help toggle 2>"$TMP/err")
	STATUS=$?
	assert_eq "status" "$STATUS" 0 || return
	local sub
	for sub in bar dnd nightlight awake; do
		[[ $OUT == *"$sub"* ]] || { fail "subject '$sub' missing from help: [$OUT]"; return; }
	done
	ok
}

# ---- failure modes -----------------------------------------------------------

test_unknown_subject_touches_nothing() {
	it "an unknown subject fails without calling the shell"
	run nope
	assert_eq "status" "$STATUS" 2 || return
	[[ -s $CAPTURE ]] && { fail "called the shell anyway: [$(captured)]"; return; }
	ok
}

test_unknown_action_touches_nothing() {
	it "an unknown action fails without calling the shell"
	run bar sideways
	assert_eq "status" "$STATUS" 2 || return
	[[ -s $CAPTURE ]] && { fail "called the shell anyway: [$(captured)]"; return; }
	ok
}

test_extra_argument_is_an_error() {
	it "a third argument is a usage error"
	run bar on twice
	assert_eq "status" "$STATUS" 2 || return
	ok
}

test_unknown_option_is_an_error() {
	it "an unknown option is an error rather than a subject"
	run --bogus
	assert_eq "status" "$STATUS" 2 || return
	ok
}

test_shell_not_running() {
	it "a failing ipc call is reported, not swallowed"
	RELAY_TEST_QS_FAIL=1 run bar
	assert_eq "status" "$STATUS" 1 || return
	[[ $ERR == *"not running"* ]] || { fail "expected a 'not running' message, got [$ERR]"; return; }
	ok
}

test_qs_missing() {
	it "a missing qs is reported as such"
	setup_without_qs
	run bar
	assert_eq "status" "$STATUS" 127 || return
	[[ $ERR == *"not found"* ]] || { fail "expected a 'not found' message, got [$ERR]"; return; }
	ok
}

# A shell older than this command still has the void-returning handlers, so it
# answers with an empty line. Exiting 0 having printed nothing would look like
# the toggle worked.
test_stale_shell_reply_is_rejected() {
	it "a reply that is not on/off is rejected"
	RELAY_TEST_QS_OUT= run bar
	assert_eq "status" "$STATUS" 1 || return
	[[ $ERR == *"older than this command"* ]] || { fail "expected the stale-shell hint, got [$ERR]"; return; }
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

	printf 'relay toggle\n'
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
