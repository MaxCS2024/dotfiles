# power — switch the machine between saver, balance, and performance.
#
# One name for a setting that lives in two different places depending on the
# machine. If power-profiles-daemon is installed this is a thin wrapper around
# it — that is the backend worth having, because it is polkit-authorized (no
# password), it knows about platform/firmware knobs this does not touch, and a
# desktop widget can read the same state off D-Bus. Without it, the cpufreq
# knobs are driven directly: the scaling governor plus, on hardware that has
# it, the energy/performance preference. That path needs root and does not
# survive a reboot, both of which the help text says out loud rather than
# leaving to be discovered.
#
# The three names are the whole point. saver/balance/performance is what the
# user thinks in; powersave+balance_power is what the kernel wants, and
# power-saver is what power-profiles-daemon calls the same thing. Every
# spelling collides with at least one of the others, so the table below is the
# single place the translation happens.
#
# saver rather than power, which is what the kernel names the EPP: 'power' next
# to 'performance' reads as more of it rather than less, the same polarity trap
# the toggle module documents for idle vs awake. It stays an alias, so the
# kernel's own name still works.
#
# Ported from bin/orbit-powerprofile. Under relay's grammar the profile is an
# argument to `set` rather than a bare word, which is what `volume set` does
# and what keeps a profile name from colliding with an action name.

rig::load log check proc

RELAY_MODULE_SUMMARY[power]="CPU power profile: saver, balance, performance"
RELAY_MODULE_ACTIONS[power]="status set list"
RELAY_MODULE_STATUS[power]="ready"
RELAY_MODULE_TIER[power]="general"

# Overridable so the tests can run against a fake tree instead of repointing
# the governor of whoever is running them — same trick as the network module.
: "${RELAY_SYSFS:=/sys}"

# profile -> "<fallback governor>|<epp>|<ppd name>|<description>"
#
# The EPP is the real setting on any CPU that has one: intel_pstate and
# amd-pstate in active mode keep the governor on powersave for all three
# profiles and move only the EPP, which is exactly what power-profiles-daemon
# does to them. The governor field is the fallback for hardware with no EPP,
# where it is the only knob there is — and where saver and balance therefore
# collapse into the same setting.
#
# balance takes balance_power rather than the kernel's balance_performance so
# that this balance and ppd's balanced are the same machine state, whichever
# backend ends up applying it.
declare -gA RELAY_POWER_PROFILES=(
    [saver]='powersave|power|power-saver|longest battery life — the CPU boosts reluctantly'
    [balance]='powersave|balance_power|balanced|boosts when asked, idles down quickly'
    [performance]='performance|performance|performance|never hold the CPU back — hottest, shortest battery'
)

# EPP values understood but never written. balance_performance is what most
# kernels boot into, so without this a machine nobody has touched yet would
# read as 'custom' rather than as the balance profile it is sitting in.
declare -gA RELAY_POWER_EPP_ALIASES=(
    [balance_performance]=balance
)

# An associative array has no order of its own, and this one reads as a slider
# from least to most power. Help, list and the reverse lookup all use this.
declare -ga RELAY_POWER_ORDER=(saver balance performance)

# Every other spelling of the same three profiles: the kernel's, power-profiles-
# daemon's, and the ones people actually type. Accepting them costs a row each
# and means a script written against `powerprofilesctl set power-saver` keeps
# working when it is pointed here.
declare -gA RELAY_POWER_ALIASES=(
    [power]=saver [power-saver]=saver [powersave]=saver [eco]=saver
    [battery]=saver [low-power]=saver
    [balanced]=balance [bal]=balance [normal]=balance [default]=balance
    [perf]=performance [max]=performance [turbo]=performance [high]=performance
)

RELAY_POWER_BACKEND=''
RELAY_POWER_PROFILE=''
RELAY_POWER_GOVERNOR=''
RELAY_POWER_EPP=''

relay::power::__say() {
    if ((${RELAY_POWER_JSON:-0})); then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi
}

# Resolve what the user typed to one of RELAY_POWER_ORDER, or fail.
relay::power::__resolve() {
    local want=${1,,}
    [[ -n ${RELAY_POWER_PROFILES[$want]:-} ]] && {
        printf '%s\n' "$want"
        return 0
    }
    [[ -n ${RELAY_POWER_ALIASES[$want]:-} ]] && {
        printf '%s\n' "${RELAY_POWER_ALIASES[$want]}"
        return 0
    }
    return 1
}

# ---- backend ------------------------------------------------------------------

# Installed is not the same as running: power-profiles-daemon.service can be
# present and masked, or the bus can be unreachable, and in both cases the
# cpufreq path is still the honest answer. `get` is the cheapest question that
# actually talks to the daemon.
relay::power::__detect_backend() {
    if rig::check::has powerprofilesctl && powerprofilesctl get >/dev/null 2>&1; then
        printf 'ppd\n'
    else
        printf 'sysfs\n'
    fi
}

# ---- cpufreq ------------------------------------------------------------------

relay::power::__policies() {
    local p
    for p in "$RELAY_SYSFS"/devices/system/cpu/cpufreq/policy*/; do
        [[ -d $p ]] || continue
        printf '%s\n' "${p%/}"
    done
}

# The value of <attr> across every policy: the value itself when they agree,
# 'mixed' when they do not. Reporting mixed rather than whatever cpu0 happens
# to say is what keeps `custom` meaningful — a half-applied change is exactly
# the state worth noticing.
relay::power::__uniform_value() {
    local attr=$1 p v first='' n=0
    while read -r p; do
        [[ -r $p/$attr ]] || continue
        v=$(<"$p/$attr")
        v=${v%% *}
        if ((n == 0)); then
            first=$v
        elif [[ $v != "$first" ]]; then
            printf 'mixed\n'
            return 0
        fi
        n=$((n + 1))
    done < <(relay::power::__policies)
    ((n)) || return 1
    printf '%s\n' "$first"
}

relay::power::__read_sysfs_state() {
    RELAY_POWER_GOVERNOR=$(relay::power::__uniform_value scaling_governor) || {
        rig::log::error "no cpufreq policies under $RELAY_SYSFS — this CPU has no scaling driver to drive"
        return "$RIG_EX_FAIL"
    }
    # Absent on older CPUs, on AMD without amd-pstate EPP, and whenever
    # intel_pstate is in passive mode. The governor still works there; only the
    # power/balance distinction is lost.
    RELAY_POWER_EPP=$(relay::power::__uniform_value energy_performance_preference) || RELAY_POWER_EPP=''
}

relay::power::__current_sysfs() {
    local name e

    # Policies that disagree with each other are a half-applied state rather
    # than a profile, whichever knob they disagree on.
    [[ $RELAY_POWER_GOVERNOR == mixed || $RELAY_POWER_EPP == mixed ]] && {
        printf 'custom\n'
        return 0
    }

    # With an EPP to read, it is the whole answer and the governor is not
    # consulted at all. power-profiles-daemon leaves the governor on powersave
    # even for its performance profile, so a reader that insisted on seeing the
    # performance governor would call ppd's own performance state 'custom'.
    if [[ -n $RELAY_POWER_EPP ]]; then
        [[ -n ${RELAY_POWER_EPP_ALIASES[$RELAY_POWER_EPP]:-} ]] && {
            printf '%s\n' "${RELAY_POWER_EPP_ALIASES[$RELAY_POWER_EPP]}"
            return 0
        }
        for name in "${RELAY_POWER_ORDER[@]}"; do
            IFS='|' read -r _ e _ _ <<<"${RELAY_POWER_PROFILES[$name]}"
            [[ $RELAY_POWER_EPP == "$e" ]] && {
                printf '%s\n' "$name"
                return 0
            }
        done
        printf 'custom\n'
        return 0
    fi

    # No EPP: the governor is all there is. performance is unambiguous, but
    # powersave could be either of the other two, so say custom rather than
    # pick one.
    [[ $RELAY_POWER_GOVERNOR == performance ]] && {
        printf 'performance\n'
        return 0
    }
    printf 'custom\n'
}

# Two shapes, decided per policy by whether the hardware has an EPP.
#
# With one, the EPP is the setting and the governor is pinned to powersave
# first: intel_pstate ties the two together, and under the performance governor
# the EPP is held at performance, so a write made there is at best ignored.
# Setting powersave first means the EPP write always lands and removes any need
# to care which profile we started in. This is the same end state ppd produces.
#
# Without one, the governor is the setting and gets written directly.
relay::power::__apply_sysfs() {
    local gov=$1 epp=$2
    local -a cmd=(
        sh -c '
			set -e
			gov=$1 epp=$2 root=$3
			for p in "$root"/devices/system/cpu/cpufreq/policy*/; do
				[ -e "$p/scaling_governor" ] || continue
				if [ -e "$p/energy_performance_preference" ]; then
					printf %s powersave > "$p/scaling_governor"
					printf %s "$epp" > "$p/energy_performance_preference"
				else
					printf %s "$gov" > "$p/scaling_governor"
				fi
			done
		' _ "$gov" "$epp" "$RELAY_SYSFS"
    )

    # Root already, or in a test tree we own: no point shelling out to sudo,
    # and under the tests there may not be one to shell out to.
    if ((EUID != 0)) && [[ $RELAY_SYSFS == /sys ]]; then
        rig::check::has sudo || {
            rig::log::error "need root to set the governor, and sudo is not installed"
            return "$RIG_EX_NODEP"
        }
        relay::power::__say "setting the cpufreq governor needs root..."
        cmd=(sudo "${cmd[@]}")
    fi

    "${cmd[@]}" || {
        rig::log::error "could not write the cpufreq knobs under $RELAY_SYSFS"
        return "$RIG_EX_FAIL"
    }
}

# ---- read / write -------------------------------------------------------------

# Answers in RELAY_POWER_PROFILE rather than on stdout, because the sysfs
# backend learns the governor and EPP on the way and both `list` and --json
# want them. A command substitution here would take those back out with the
# subshell.
relay::power::__current() {
    local active name p
    case $RELAY_POWER_BACKEND in
        ppd)
            active=$(powerprofilesctl get 2>/dev/null) || {
                rig::log::error "power-profiles-daemon stopped answering"
                return "$RIG_EX_FAIL"
            }
            active=${active//[$'\r\n ']/}
            RELAY_POWER_GOVERNOR='' RELAY_POWER_EPP=''
            for name in "${RELAY_POWER_ORDER[@]}"; do
                IFS='|' read -r _ _ p _ <<<"${RELAY_POWER_PROFILES[$name]}"
                [[ $active == "$p" ]] && {
                    RELAY_POWER_PROFILE=$name
                    return 0
                }
            done
            # ppd grew a profile there is no name for here. Passing it through
            # beats calling a real, named profile 'custom'.
            RELAY_POWER_PROFILE=$active
            ;;
        sysfs)
            relay::power::__read_sysfs_state || return $?
            RELAY_POWER_PROFILE=$(relay::power::__current_sysfs)
            ;;
    esac
}

# Reads the four globals, all of which __current has set by the time anything
# calls this.
relay::power::__emit() {
    if ((${RELAY_POWER_JSON:-0})); then
        printf '{"profile":"%s","backend":"%s","governor":"%s","epp":"%s"}\n' \
            "$RELAY_POWER_PROFILE" "$RELAY_POWER_BACKEND" \
            "$RELAY_POWER_GOVERNOR" "$RELAY_POWER_EPP"
    else
        printf '%s\n' "$RELAY_POWER_PROFILE"
    fi
}

relay::power::__init() {
    RELAY_POWER_JSON=0
    local -a rest=()
    local a
    for a in "$@"; do
        case $a in
            --json) RELAY_POWER_JSON=1 ;;
            -*)
                rig::log::error "unknown option '$a'"
                return "$RIG_EX_USAGE"
                ;;
            *)
                # One profile per call. `set saver performance` is a typo with
                # two readings and obeying either one silently is how a machine
                # ends up in the profile nobody asked for.
                ((${#rest[@]})) && {
                    rig::log::error "unexpected argument '$a' (one profile at a time)"
                    return "$RIG_EX_USAGE"
                }
                rest+=("$a")
                ;;
        esac
    done
    RELAY_POWER_GOVERNOR='' RELAY_POWER_EPP='' RELAY_POWER_PROFILE=''
    RELAY_POWER_BACKEND=$(relay::power::__detect_backend)
    RELAY_POWER_ARGS=("${rest[@]+"${rest[@]}"}")
    return 0
}

# ---- actions -------------------------------------------------------------------

relay::power::status() {
    relay::power::__init "$@" || return $?
    relay::power::__current || return $?
    relay::power::__emit
}

relay::power::set() {
    relay::power::__init "$@" || return $?
    local arg=${RELAY_POWER_ARGS[0]:-}
    [[ -n $arg ]] || {
        rig::log::error "set needs a profile (want: ${RELAY_POWER_ORDER[*]})"
        return "$RIG_EX_USAGE"
    }

    local want gov epp ppd
    want=$(relay::power::__resolve "$arg") || {
        rig::log::error "unknown profile '$arg' (want: ${RELAY_POWER_ORDER[*]})"
        return "$RIG_EX_USAGE"
    }
    IFS='|' read -r gov epp ppd _ <<<"${RELAY_POWER_PROFILES[$want]}"

    case $RELAY_POWER_BACKEND in
        ppd)
            powerprofilesctl set "$ppd" || {
                rig::log::error "power-profiles-daemon refused '$ppd' (see: powerprofilesctl list)"
                return "$RIG_EX_FAIL"
            }
            ;;
        sysfs) relay::power::__apply_sysfs "$gov" "$epp" || return $? ;;
    esac

    # Read back rather than echo the request. A governor the kernel declined, a
    # daemon that clamped the choice on battery, an EPP write that did not
    # stick — all of them look identical to a command that just prints what it
    # was asked for.
    relay::power::__current || return $?
    [[ $RELAY_POWER_PROFILE == "$want" ]] && {
        relay::power::__emit
        return 0
    }

    # A CPU with no EPP has only the governor, so saver and balance are one
    # setting there and reading back can never return either name. The write
    # still did everything the hardware can do, so this is a note, not the
    # failure the strict comparison above would have called it.
    if [[ $RELAY_POWER_BACKEND == sysfs && -z $RELAY_POWER_EPP && $RELAY_POWER_GOVERNOR == "$gov" ]]; then
        printf 'relay power: no EPP support here — saver and balance are both "%s"\n' \
            "$gov" >&2
        RELAY_POWER_PROFILE=$want
        relay::power::__emit
        return 0
    fi

    rig::log::error "asked for '$want' but the machine reports '$RELAY_POWER_PROFILE'"
    return "$RIG_EX_FAIL"
}

relay::power::list() {
    relay::power::__init "$@" || return $?
    relay::power::__current || return $?

    ((${RELAY_POWER_JSON:-0})) && {
        relay::power::__emit
        return 0
    }

    local name desc mark
    for name in "${RELAY_POWER_ORDER[@]}"; do
        IFS='|' read -r _ _ _ desc <<<"${RELAY_POWER_PROFILES[$name]}"
        mark=' '
        [[ $name == "$RELAY_POWER_PROFILE" ]] && mark='*'
        printf ' %s %-12s %s\n' "$mark" "$name" "$desc"
    done

    case $RELAY_POWER_BACKEND in
        ppd) printf '\nbackend: power-profiles-daemon\n' ;;
        sysfs)
            printf '\nbackend: cpufreq (power-profiles-daemon not running)\n'
            printf '  governor  %s\n' "$RELAY_POWER_GOVERNOR"
            printf '  epp       %s\n' "${RELAY_POWER_EPP:-unsupported on this CPU}"
            ;;
    esac

    [[ $RELAY_POWER_PROFILE == custom ]] &&
        printf '\nno profile matches those values — something else set them.\n'
    return 0
}

relay::power::__usage() {
    cat <<'EOF'
  relay power status                which profile am I in
  relay power set performance
  relay power set Saver             case does not matter
  relay power list                  the profiles, with the active one marked

profiles
  saver        longest battery life — the CPU boosts reluctantly
  balance      boosts when asked, idles down quickly
  performance  never hold the CPU back — hottest, shortest battery

Setting one prints the profile that ended up in effect, read back from the
machine rather than assumed — so a write the kernel declined is an error
here, not a silent no-op.

Names are matched case-insensitively, and the kernel's and
power-profiles-daemon's own spellings (power, powersave, power-saver,
balanced, ...) are accepted too.

options
  --json    {"profile":..,"backend":..,"governor":..,"epp":..}

backends
  power-profiles-daemon   used when installed and running. No password, and
                          it drives firmware knobs this does not.
  cpufreq (fallback)      the scaling governor and, where the CPU supports
                          it, the energy/performance preference. Needs root,
                          and the kernel is back to its boot defaults after
                          a reboot.

'custom' means the machine is in a state that is not one of the three —
something else moved the knobs, the policies disagree with each other, or
the CPU has no EPP and so cannot tell saver from balance. `list` shows the
raw values behind the name.

env
  RELAY_SYSFS   where to read and write the cpufreq knobs (default: /sys)
EOF
}
