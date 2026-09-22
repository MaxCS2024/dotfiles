# health — failed units, pending updates, .pacnew files, disk, journal.
#
# Read-only. It never modifies the system and never needs sudo: every question
# here is answerable from world-readable state, which is what makes it safe to
# run from a menu or a status widget.
#
# The severity ladder is rig::diag's: ok < info < warn < problem, and only
# 'problem' affects the exit status, so `rack health` stays usable as a
# predicate in scripts — pending updates are a normal state, not a failure.
#
# Ported from bin/orbit-health.

rig::load log check diag

RACK_MODULE_SUMMARY[health]="failed units, updates, pacnew, disk, journal"
RACK_MODULE_ACTIONS[health]="report"
RACK_MODULE_STATUS[health]="ready"
RACK_MODULE_TIER[health]="general"

# Thresholds live here rather than inline so they are adjustable without
# hunting through the checks.
: "${RACK_HEALTH_DISK_WARN:=85}"
: "${RACK_HEALTH_DISK_PROBLEM:=95}"
: "${RACK_HEALTH_MIRROR_STALE_DAYS:=30}"
: "${RACK_HEALTH_CACHE_WARN_MB:=5000}"

# wc -l counts newlines, so an empty string would otherwise report as 1 line.
rack::health::__count() {
    [[ -n $1 ]] || {
        printf '0\n'
        return 0
    }
    printf '%s\n' "$1" | wc -l
}

# ---- checks ------------------------------------------------------------------

rack::health::__units() {
    local sys usr n_sys n_usr total names
    sys=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}') || sys=""
    # Fails when invoked outside a user session (eg. over plain ssh); not an error.
    usr=$(systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print $1}') || usr=""

    n_sys=$(rack::health::__count "$sys")
    n_usr=$(rack::health::__count "$usr")
    total=$((n_sys + n_usr))

    if ((total == 0)); then
        rig::diag::add units ok "no failed units"
        return 0
    fi

    names=$(printf '%s\n%s\n' "$sys" "$usr" | grep -v '^$' | paste -sd' ')
    rig::diag::add units problem "$total failed: $names" "" \
        "$(jq -nc --argjson s "$n_sys" --argjson u "$n_usr" '{system: $s, user: $u}')"
}

rack::health::__updates() {
    local repo="" aur="" flat="" n_repo=0 n_aur=0 n_flat=0 rc parts

    # checkupdates (pacman-contrib) syncs into a temporary database. Never use
    # `pacman -Sy` to check for updates — syncing without upgrading is how
    # partial-upgrade breakage happens.
    if rig::check::has checkupdates; then
        rc=0
        repo=$(checkupdates 2>/dev/null) || rc=$?
        # 2 means "no updates", which is success for our purposes.
        ((rc == 0 || rc == 2)) || repo=""
        n_repo=$(rack::health::__count "$repo")
    fi

    if rig::check::has yay; then
        aur=$(yay -Qua 2>/dev/null) || aur=""
        n_aur=$(rack::health::__count "$aur")
    fi

    if rig::check::has flatpak; then
        flat=$(flatpak remote-ls --updates --columns=application 2>/dev/null) || flat=""
        n_flat=$(rack::health::__count "$flat")
    fi

    if ! rig::check::has checkupdates; then
        rig::diag::add updates warn "cannot check (install pacman-contrib)"
        return 0
    fi

    if ((n_repo + n_aur + n_flat == 0)); then
        rig::diag::add updates ok "up to date"
        return 0
    fi

    parts=""
    ((n_repo)) && parts+="$n_repo repo, "
    ((n_aur)) && parts+="$n_aur aur, "
    ((n_flat)) && parts+="$n_flat flatpak, "
    parts=${parts%, }

    rig::diag::add updates info "$parts available (run: rack update)" "" \
        "$(jq -nc --argjson r "$n_repo" --argjson a "$n_aur" --argjson f "$n_flat" \
            '{repo: $r, aur: $a, flatpak: $f}')"
}

rack::health::__pacnew() {
    local files n
    # /etc is world-readable, so this needs no sudo. Errors are suppressed
    # rather than escalated because an unreadable subdirectory is not a health
    # finding in itself.
    files=$(find /etc -type f \( -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null) || files=""
    n=$(rack::health::__count "$files")

    if ((n == 0)); then
        rig::diag::add pacnew ok "none pending"
        return 0
    fi

    # Deliberately never auto-merged. Reconciling a .pacnew is a judgement call
    # about your own configuration, not something a health check should decide.
    rig::diag::add pacnew warn "$n pending (review with pacdiff)" "" \
        "$(jq -nc --arg f "$files" '{files: ($f | split("\n") | map(select(length > 0)))}')"
}

rack::health::__orphans() {
    local orphans n
    # Exits 1 when there are none, which is not an error.
    orphans=$(pacman -Qtdq 2>/dev/null) || orphans=""
    n=$(rack::health::__count "$orphans")

    if ((n == 0)); then
        rig::diag::add orphans ok "none"
    else
        rig::diag::add orphans warn "$n orphaned (run: rack clean)" "" \
            "$(jq -nc --argjson n "$n" '{count: $n}')"
    fi
}

rack::health::__disk() {
    local mount pct worst=0 worst_mount="" status
    while read -r mount pct; do
        pct=${pct%\%}
        if ((pct > worst)); then
            worst=$pct
            worst_mount=$mount
        fi
    done < <(df --output=target,pcent / /home 2>/dev/null | tail -n +2)

    if ((worst >= RACK_HEALTH_DISK_PROBLEM)); then
        status=problem
    elif ((worst >= RACK_HEALTH_DISK_WARN)); then
        status=warn
    else
        status=ok
    fi

    rig::diag::add disk "$status" "$worst_mount at ${worst}%" "" \
        "$(jq -nc --arg m "$worst_mount" --argjson p "$worst" '{mount: $m, percent: $p}')"
}

rack::health::__journal() {
    local n
    n=$(journalctl -p 3 -b --no-pager -q 2>/dev/null | wc -l) || n=0

    if ((n == 0)); then
        rig::diag::add journal ok "no errors this boot"
    else
        # Reported as a count, not dumped. Anyone acting on this wants the full
        # output with context, which is what the suggested command gives.
        rig::diag::add journal warn "$n errors this boot (journalctl -p 3 -b)" "" \
            "$(jq -nc --argjson n "$n" '{errors: $n}')"
    fi
}

rack::health::__cache() {
    local mb status
    mb=$(du -sm /var/cache/pacman/pkg 2>/dev/null | cut -f1) || mb=0
    [[ -n $mb ]] || mb=0

    if ((mb >= RACK_HEALTH_CACHE_WARN_MB)); then
        status=warn
        rig::diag::add cache "$status" "${mb}MB (run: rack clean)" "" \
            "$(jq -nc --argjson m "$mb" '{megabytes: $m}')"
    else
        rig::diag::add cache ok "${mb}MB" "" \
            "$(jq -nc --argjson m "$mb" '{megabytes: $m}')"
    fi
}

rack::health::__mirrors() {
    local mtime age
    if [[ ! -r /etc/pacman.d/mirrorlist ]]; then
        rig::diag::add mirrors warn "mirrorlist not readable"
        return 0
    fi

    mtime=$(stat -c %Y /etc/pacman.d/mirrorlist)
    age=$((($(date +%s) - mtime) / 86400))

    if ((age >= RACK_HEALTH_MIRROR_STALE_DAYS)); then
        rig::diag::add mirrors warn "${age}d old (run: rack mirrors)" "" \
            "$(jq -nc --argjson a "$age" '{age_days: $a}')"
    else
        rig::diag::add mirrors ok "${age}d old" "" \
            "$(jq -nc --argjson a "$age" '{age_days: $a}')"
    fi
}

rack::health::__run_checks() {
    rack::health::__units
    rack::health::__updates
    rack::health::__pacnew
    rack::health::__orphans
    rack::health::__disk
    rack::health::__journal
    rack::health::__cache
    rack::health::__mirrors
}

rack::health::report() {
    while (($#)); do
        case "$1" in
            --json) RIG_DIAG_JSON=1 ;;
            *)
                rig::log::error "unknown option: $1"
                return "$RIG_EX_USAGE"
                ;;
        esac
        shift
    done

    rig::check::has pacman || {
        rig::log::error "not an Arch system (pacman not found)"
        return "$RIG_EX_NODEP"
    }
    # Every check builds its detail with jq, so it is required either way here
    # rather than only under --json.
    rig::check::require jq || return "$RIG_EX_NODEP"

    # These names are longer than the subsystem checks', so the column widens.
    RIG_DIAG_WIDTH=14
    rig::diag::status "system health" rack::health::__run_checks
}

rack::health::__default() { rack::health::report "$@"; }

rack::health::__usage() {
    cat <<'EOF'
  rack health           report on system state
  rack health --json    machine-readable (requires jq)

Reports on failed services, available updates, pending .pacnew files,
orphaned packages, disk usage, journal errors, package cache size, and
mirrorlist age.

Read-only. Never modifies the system and never needs sudo.

exit status
  0  no problems (warnings and available updates are not problems)
  1  at least one problem found

env
  RACK_HEALTH_DISK_WARN           default 85
  RACK_HEALTH_DISK_PROBLEM        default 95
  RACK_HEALTH_MIRROR_STALE_DAYS   default 30
  RACK_HEALTH_CACHE_WARN_MB       default 5000
EOF
}
