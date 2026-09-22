#!/usr/bin/env bash
# tests for relay's power module
#
# Same shape as orbit-toggle.test.sh next door: plain bash, no framework. The
# safety story is different though, and stricter. This command's whole job is
# to repoint the CPU governor, so a test that escaped its fixtures would not
# just be wrong, it would reset the power profile of whoever ran it — and on
# the sysfs path it would try to do that through sudo.
#
# Two things prevent that, and setup() refuses to run if either is missing:
# every run is pointed at a fake /sys via RELAY_SYSFS, and both `sudo` and
# `powerprofilesctl` are stubbed with versions that fail loudly. The command
# skips sudo entirely when RELAY_SYSFS is not /sys, so reaching the stub at
# all means a bug worth failing on.
#
#   ./test/relay-power.test.sh          # all tests
#   ./test/relay-power.test.sh ppd      # only tests matching "ppd"
# Exit codes are rig's, not orbit's: 2 for a usage error and 127 for a missing
# dependency, where orbit exited 1 for everything. That distinction is the
# point of the convention — a script can tell "you typed it wrong" from "the
# machine is missing a tool" from "the kernel refused the write".
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
	mkdir -p "$TMP/bin"
	export RELAY_SYSFS="$TMP/sys"

	# Neither of these should ever run. They exist so that a bug which tries
	# reaches something inert and noisy instead of the real system.
	cat >"$TMP/bin/sudo" <<-'EOF'
		#!/usr/bin/env bash
		printf 'test stub: relay power tried to use sudo\n' >&2
		exit 111
	EOF

	# Answers `powerprofilesctl get|set|list`. Present only when a test asks
	# for it via use_ppd; the default PATH below has no powerprofilesctl at
	# all, which is what puts the command on its cpufreq path.
	cat >"$TMP/ppdctl" <<-'EOF'
		#!/usr/bin/env bash
		state="$ORBIT_TEST_PPD_STATE"
		printf '%s\n' "$@" >> "$ORBIT_TEST_PPD_CALLS"
		[[ -n ${ORBIT_TEST_PPD_DEAD:-} ]] && exit 1
		case $1 in
			get) cat "$state" ;;
			set) printf '%s' "$2" > "$state" ;;
		esac
	EOF

	chmod +x "$TMP/bin/sudo" "$TMP/ppdctl"

	# Only what the command and the assertions actually run, symlinked in one
	# by one. Putting /usr/bin on the end instead would be enough for the
	# stubs to win by precedence, but not enough to make the real
	# powerprofilesctl unreachable — and once it is reachable, a bug in
	# backend detection reaches the daemon and moves the profile of whoever
	# is running the tests.
	local tool src
	for tool in bash sh env readlink dirname basename cat grep sed awk sort \
		tail head tr mkdir cp rm chmod wc; do
		src=$(command -v "$tool" 2>/dev/null) || continue
		ln -sf "$src" "$TMP/bin/$tool"
	done

	export ORBIT_TEST_PPD_STATE="$TMP/ppd-state"
	export ORBIT_TEST_PPD_CALLS="$TMP/ppd-calls"
	printf 'balanced' >"$ORBIT_TEST_PPD_STATE"
	: >"$ORBIT_TEST_PPD_CALLS"
	unset ORBIT_TEST_PPD_DEAD

	export PATH="$TMP/bin"

	# The fixtures are only protection if they are the ones actually in play.
	[[ $RELAY_SYSFS == "$TMP/sys" ]] || {
		printf 'harness error: RELAY_SYSFS is %s, not the fixture\n' "$RELAY_SYSFS" >&2
		exit 1
	}
	command -v powerprofilesctl >/dev/null && {
		printf 'harness error: a real powerprofilesctl is on PATH\n' >&2
		exit 1
	}
	return 0
}

# Build a fake cpufreq tree: <n> policies, all at <governor>, and an EPP file
# holding <epp> unless it is the literal "none" — which is how a CPU with no
# HWP/EPP support is modelled.
fake_cpufreq() {
	local n=$1 governor=$2 epp=$3 i d
	for ((i = 0; i < n; i++)); do
		d="$RELAY_SYSFS/devices/system/cpu/cpufreq/policy$i"
		mkdir -p "$d"
		printf '%s\n' "$governor" >"$d/scaling_governor"
		[[ $epp == none ]] || printf '%s\n' "$epp" >"$d/energy_performance_preference"
	done
}

# Put the powerprofilesctl stub on PATH, which is what makes the command
# choose its ppd backend over cpufreq.
use_ppd() { cp "$TMP/ppdctl" "$TMP/bin/powerprofilesctl"; }

policy_value() { cat "$RELAY_SYSFS/devices/system/cpu/cpufreq/policy$1/$2" 2>/dev/null; }

teardown() {
	export PATH="$ORIG_PATH"
	[[ -n ${TMP:-} && -d $TMP ]] && rm -rf "$TMP"
	unset RELAY_SYSFS
	return 0
}

# Adapter for the one interface change the port made: orbit took the profile
# as a bare word (`orbit powerprofile performance`), relay takes it as an
# argument to an action (`relay power set performance`), because under relay's
# grammar a bare word is an action name and `performance` would collide with
# one. Every test below is written in the old shape and translated here, so
# what they assert is still the behaviour and not the spelling.
run() {
	local -a argv
	local first="" a
	for a in "$@"; do
		[[ $a == -* ]] && continue
		first=$a
		break
	done
	case $first in
		'') argv=(status "$@") ;;
		status | list | set) argv=("$@") ;;
		*) argv=(set "$@") ;;
	esac
	OUT=$("$RELAY" power "${argv[@]}" 2>"$TMP/err")
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

it() { CURRENT=$1; }

# ---- reading the current profile ---------------------------------------------

test_reads_balance() {
	it "powersave + balance_power reads as balance"
	fake_cpufreq 4 powersave balance_power
	run
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "profile" "$OUT" balance || return
	ok
}

# What most kernels boot into. Orbit writes balance_power, but a machine nobody
# has touched is sitting in balance and should be told so.
test_reads_stock_balance_performance() {
	it "the kernel's own balance_performance also reads as balance"
	fake_cpufreq 4 powersave balance_performance
	run
	assert_eq "profile" "$OUT" balance || return
	ok
}

# The regression that made all of this worth fixing: power-profiles-daemon
# drives intel_pstate through the EPP alone and leaves the governor on
# powersave, even for performance. A reader keyed on the governor called that
# state 'custom' and so would have misreported every profile ppd had set.
test_reads_the_state_ppd_leaves_behind() {
	it "powersave + performance EPP reads as performance, not custom"
	fake_cpufreq 4 powersave performance
	run
	assert_eq "profile" "$OUT" performance || return
	ok
}

test_reads_saver() {
	it "powersave + the power EPP reads as saver"
	fake_cpufreq 4 powersave power
	run
	assert_eq "profile" "$OUT" saver || return
	ok
}

test_reads_performance() {
	it "the performance governor reads as performance"
	fake_cpufreq 4 performance performance
	run
	assert_eq "profile" "$OUT" performance || return
	ok
}

test_unknown_epp_is_custom() {
	it "an EPP outside the table reads as custom"
	fake_cpufreq 4 powersave some_vendor_epp
	run
	assert_eq "profile" "$OUT" custom || return
	ok
}

# A governor nothing in the table claims, on hardware with no EPP to fall back
# on. Answering with the nearest profile would misreport whatever set it.
test_unknown_governor_is_custom() {
	it "with no EPP, a governor outside the table reads as custom"
	fake_cpufreq 4 schedutil none
	run
	assert_eq "profile" "$OUT" custom || return
	ok
}

# Half-applied state is the case worth catching: reading cpu0 alone would call
# this a clean 'power' and hide that three cores disagree.
test_mixed_policies_are_custom() {
	it "policies that disagree read as custom, not as whatever cpu0 says"
	fake_cpufreq 4 powersave power
	printf 'performance\n' >"$RELAY_SYSFS/devices/system/cpu/cpufreq/policy3/scaling_governor"
	run
	assert_eq "profile" "$OUT" custom || return
	assert_eq "governor" "$(run list; printf '%s' "$OUT" | sed -n 's/^  governor  //p')" mixed || return
	ok
}

test_no_policies_is_an_error() {
	it "a machine with no cpufreq policies is an error, not a silent answer"
	mkdir -p "$RELAY_SYSFS"
	run
	assert_eq "status" "$STATUS" 1 || return
	[[ $ERR == *"no cpufreq policies"* ]] || { fail "expected the no-policies message, got [$ERR]"; return; }
	ok
}

# ---- setting a profile --------------------------------------------------------

test_set_performance_writes_every_policy() {
	it "setting a profile writes every policy, not just cpu0"
	fake_cpufreq 4 powersave balance_power
	run performance
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "profile" "$OUT" performance || return
	local i
	for i in 0 1 2 3; do
		assert_eq "policy$i epp" "$(policy_value $i energy_performance_preference)" performance || return
		# powersave, not performance: on EPP hardware the EPP is the setting
		# and the governor stays where ppd would leave it.
		assert_eq "policy$i governor" "$(policy_value $i scaling_governor)" powersave || return
	done
	ok
}

test_set_saver_writes_both_knobs() {
	it "saver sets the governor and the EPP, which is the only thing telling it from balance"
	fake_cpufreq 2 performance performance
	run saver
	assert_eq "profile" "$OUT" saver || return
	assert_eq "governor" "$(policy_value 0 scaling_governor)" powersave || return
	assert_eq "epp" "$(policy_value 0 energy_performance_preference)" power || return
	ok
}

# The case the whole three-write dance in apply_sysfs exists for: coming FROM
# performance, where the EPP is pinned until the governor moves off it.
test_performance_to_balance() {
	it "leaving performance still lands the EPP write"
	fake_cpufreq 2 performance performance
	run balance
	assert_eq "profile" "$OUT" balance || return
	assert_eq "governor" "$(policy_value 0 scaling_governor)" powersave || return
	assert_eq "epp" "$(policy_value 0 energy_performance_preference)" balance_power || return
	ok
}

# ---- the names ----------------------------------------------------------------

test_capitalised_names() {
	it "the capitalised names work"
	fake_cpufreq 2 powersave balance_performance
	run Performance
	assert_eq "profile" "$OUT" performance || return
	run Saver
	assert_eq "profile" "$OUT" saver || return
	run Balance
	assert_eq "profile" "$OUT" balance || return
	ok
}

test_kernel_and_ppd_spellings() {
	it "the kernel's and ppd's own spellings are accepted"
	fake_cpufreq 2 performance performance
	run power-saver
	assert_eq "power-saver" "$OUT" saver || return
	run balanced
	assert_eq "balanced" "$OUT" balance || return
	ok
}

# 'power' is what the kernel calls this EPP, and what orbit itself called the
# profile before the name turned out to read as the opposite of what it means.
# Either way it is a name people will type, so it stays an alias.
test_power_is_still_an_alias() {
	it "the old name 'power' still resolves to saver"
	fake_cpufreq 2 performance performance
	run power
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "profile" "$OUT" saver || return
	assert_eq "epp" "$(policy_value 0 energy_performance_preference)" power || return
	ok
}

test_unknown_profile_is_rejected() {
	it "an unknown profile names the three that exist"
	fake_cpufreq 2 powersave power
	run sport
	assert_eq "status" "$STATUS" 2 || return
	[[ $ERR == *"saver balance performance"* ]] || { fail "expected the profile list, got [$ERR]"; return; }
	assert_eq "governor untouched" "$(policy_value 0 scaling_governor)" powersave || return
	ok
}

test_unknown_option_is_rejected() {
	it "an unknown option is rejected rather than read as a profile"
	fake_cpufreq 2 powersave power
	run --fast
	assert_eq "status" "$STATUS" 2 || return
	[[ $ERR == *"unknown option"* ]] || { fail "expected an unknown-option error, got [$ERR]"; return; }
	ok
}

test_two_profiles_is_rejected() {
	it "two profiles at once is rejected"
	fake_cpufreq 2 powersave power
	run saver performance
	assert_eq "status" "$STATUS" 2 || return
	ok
}

# ---- CPUs without EPP ---------------------------------------------------------

# Here power and balance are the same governor, so the read-back can never
# return the requested name. The write is still complete, so this has to
# succeed — and say why on stderr, leaving stdout a single parseable word.
test_no_epp_set_succeeds_with_a_note() {
	it "no EPP support: setting saver succeeds and explains itself on stderr"
	fake_cpufreq 2 schedutil none
	run saver
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "stdout" "$OUT" saver || return
	assert_eq "governor" "$(policy_value 0 scaling_governor)" powersave || return
	[[ $ERR == *"no EPP support"* ]] || { fail "expected the EPP note, got [$ERR]"; return; }
	ok
}

test_no_epp_performance_is_unambiguous() {
	it "no EPP support: performance is still unambiguous, so no note"
	fake_cpufreq 2 powersave none
	run performance
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "profile" "$OUT" performance || return
	assert_eq "stderr" "$ERR" "" || return
	ok
}

test_no_epp_reads_as_custom() {
	it "no EPP support: powersave alone cannot claim to be either name"
	fake_cpufreq 2 powersave none
	run
	assert_eq "profile" "$OUT" custom || return
	ok
}

# ---- the power-profiles-daemon backend ----------------------------------------

test_ppd_is_preferred() {
	it "a running power-profiles-daemon wins over cpufreq"
	use_ppd
	fake_cpufreq 2 performance performance
	run --json
	assert_eq "backend" "$OUT" '{"profile":"balance","backend":"ppd","governor":"","epp":""}' || return
	ok
}

test_ppd_name_translation() {
	it "saver is handed to ppd as power-saver"
	use_ppd
	run saver
	assert_eq "profile" "$OUT" saver || return
	assert_eq "daemon state" "$(cat "$ORBIT_TEST_PPD_STATE")" power-saver || return
	grep -qx 'power-saver' "$ORBIT_TEST_PPD_CALLS" || { fail "ppd was not asked for power-saver"; return; }
	ok
}

test_ppd_leaves_cpufreq_alone() {
	it "the ppd backend does not also write the sysfs knobs"
	use_ppd
	fake_cpufreq 2 performance performance
	run saver
	assert_eq "governor" "$(policy_value 0 scaling_governor)" performance || return
	ok
}

# Installed but not answering is the case that matters: falling through to
# cpufreq is right, treating it as a running daemon is not.
test_dead_ppd_falls_back_to_cpufreq() {
	it "an installed but unresponsive ppd falls back to cpufreq"
	use_ppd
	export ORBIT_TEST_PPD_DEAD=1
	fake_cpufreq 2 powersave balance_power
	run --json
	assert_eq "backend" "$OUT" \
		'{"profile":"balance","backend":"sysfs","governor":"powersave","epp":"balance_power"}' || return
	ok
}

# ppd and the fallback have to leave the machine in the same state, or a
# profile would quietly mean two different things depending on whether the
# daemon happened to be running.
test_backends_agree_on_balance() {
	it "the fallback writes the same EPP ppd would for balance"
	fake_cpufreq 2 powersave performance
	run balance
	local fallback
	fallback=$(policy_value 0 energy_performance_preference)

	use_ppd
	printf 'performance' >"$ORBIT_TEST_PPD_STATE"
	run balance
	grep -qx 'balanced' "$ORBIT_TEST_PPD_CALLS" || { fail "ppd was not asked for balanced"; return; }
	# balance_power is what ppd sets intel_pstate to for balanced.
	assert_eq "fallback EPP" "$fallback" balance_power || return
	ok
}

# ---- output shapes ------------------------------------------------------------

test_json_after_a_set() {
	it "--json after a set reports the knobs it ended up on"
	fake_cpufreq 2 powersave balance_power
	run --json performance
	assert_eq "json" "$OUT" \
		'{"profile":"performance","backend":"sysfs","governor":"powersave","epp":"performance"}' || return
	ok
}

test_list_marks_the_active_profile() {
	it "list marks exactly one profile as active"
	fake_cpufreq 2 powersave power
	run list
	assert_eq "marked" "$(printf '%s\n' "$OUT" | grep -c '^ \*')" 1 || return
	[[ $(printf '%s\n' "$OUT" | sed -n 's/^ \* *\([a-z]*\).*/\1/p') == saver ]] ||
		{ fail "the wrong profile is marked: $OUT"; return; }
	ok
}

test_help_needs_no_hardware() {
	it "help works on a machine with no cpufreq at all"
	mkdir -p "$RELAY_SYSFS"
	# `relay help <mod>` rather than a per-module -h: the dispatcher owns help,
	# so it answers without the module reading the machine at all.
	OUT=$("$RELAY" help power 2>"$TMP/err")
	STATUS=$?
	assert_eq "status" "$STATUS" 0 || return
	[[ $OUT == *"relay power set performance"* ]] || { fail "expected the usage block, got [$OUT]"; return; }
	ok
}

# ---- runner ------------------------------------------------------------------

main() {
	[[ -x "$RELAY" ]] || {
		printf 'relay not found or not executable: %s\n' ""$RELAY"" >&2
		exit 1
	}

	local tests t
	mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_' | sort)

	printf 'relay power\n'
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
