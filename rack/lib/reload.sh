# reload — tell the running programs that their configuration moved.
#
# The manifest's third column is a shell command per application, and this is
# what runs it. Deploying a file and reloading the program that reads it are
# separate steps on purpose: `rack deploy` links, `rack reload` re-reads.
#
# The command is a shell string rather than an argv vector, which is the
# manifest's design ("reload commands live in data rather than code"): the
# entries are `pkill -SIGUSR2 waybar` and `hyprctl reload`, and some of them
# want a pipeline. It is configuration written by the person running it, not
# input from anywhere else, so `sh -c` is the right amount of machinery. A
# failing reload is reported and does not stop the others — a dead waybar must
# not keep hyprland from re-reading.

rig::load log proc
rack::load manifest

RACK_MODULE_SUMMARY[reload]="run each application's reload command"
RACK_MODULE_ACTIONS[reload]="run list"
RACK_MODULE_STATUS[reload]="ready"
RACK_MODULE_TIER[reload]="core"

# rack::reload::run [name...] — every entry, or just the named ones.
rack::reload::run() {
    local -a names=()
    while (($#)); do
        case $1 in
            -*)
                rig::log::error "unknown option: $1"
                return "$RIG_EX_USAGE"
                ;;
            *) names+=("$1") ;;
        esac
        shift
    done

    local name source target reload ran=0 failed=0
    while IFS=$'\t' read -r name source target reload; do
        [[ -n $reload ]] || continue
        ran=$((ran + 1))

        if ((${RIG_DRY_RUN:-0})); then
            printf '  %-12s would run: %s\n' "$name" "$reload"
            continue
        fi

        if sh -c "$reload" >/dev/null 2>&1; then
            printf '  %-12s reloaded\n' "$name"
        else
            # Not fatal: the usual cause is that the program is not running,
            # which is a perfectly ordinary state for a machine mid-session.
            printf '  %-12s reload failed (not running?)\n' "$name"
            failed=$((failed + 1))
        fi
    done < <(rack::manifest::select "${names[@]+"${names[@]}"}")

    ((ran)) || {
        rig::log::info "nothing to reload"
        return 0
    }
    ((failed)) && return "$RIG_EX_FAIL"
    return 0
}

# What would run, without running it. `rack reload list` answers "which of
# these even has a reload command" without the dry-run flag.
rack::reload::list() {
    local name source target reload
    while IFS=$'\t' read -r name source target reload; do
        printf '  %-12s %s\n' "$name" "${reload:--}"
    done < <(rack::manifest::select "$@")
}

rack::reload::__default() { rack::reload::run "$@"; }

rack::reload::__usage() {
    cat <<'EOF'
  rack reload               every application in the manifest
  rack reload hypr          just this one
  rack reload list          which entries have a reload command at all

A reload that fails is reported and does not stop the others: the usual
cause is that the program simply is not running.

env
  RIG_DRY_RUN=1   print each command instead of running it
EOF
}
