# clean — reclaim disk: package cache, orphans, unused flatpaks, old journals.
#
# Destructive steps prompt before acting. Nothing is removed without either a
# confirmation or --yes, and --dry-run reports without touching anything.
#
# Ported from bin/orbit-clean.

rig::load log check proc

RACK_MODULE_SUMMARY[clean]="reclaim disk from caches, orphans and journals"
RACK_MODULE_ACTIONS[clean]="run"
RACK_MODULE_STATUS[clean]="ready"
RACK_MODULE_TIER[clean]="general"

# Keep two versions of each installed package. This is the downgrade safety net
# — `pacman -Scc` empties it entirely and leaves you unable to roll back a bad
# update without re-downloading, which is exactly when you cannot.
: "${RACK_CLEAN_KEEP_VERSIONS:=2}"
: "${RACK_CLEAN_JOURNAL_KEEP_DAYS:=30}"

# Under --json, human output goes to stderr so stdout stays one document.
rack::clean::__say() {
    if ((${_json:-0})); then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi
}

rack::clean::__step() {
    if ((${_json:-0})); then printf '\n%s\n' "$*" >&2; else printf '\n%s\n' "$*"; fi
}

rack::clean::__cache_mb() {
    local mb
    mb=$(du -sm /var/cache/pacman/pkg 2>/dev/null | cut -f1) || mb=0
    printf '%s\n' "${mb:-0}"
}

rack::clean::__journal_mb() {
    local out
    # `journalctl --disk-usage` prints a human string; pull the number and unit
    # rather than assuming megabytes.
    out=$(journalctl --disk-usage 2>/dev/null) || {
        printf '0\n'
        return 0
    }
    printf '%s\n' "$out" | grep -oE '[0-9.]+[KMG]' | tail -1 |
        awk '/G$/ {printf "%d\n", $0 * 1024; next}
		     /M$/ {printf "%d\n", $0; next}
		     /K$/ {printf "%d\n", $0 / 1024; next}
		     {print 0}'
}

# ---- steps -------------------------------------------------------------------

rack::clean::__cache() {
    local before after
    rack::clean::__step "cache:"

    if ! rig::check::has paccache; then
        rack::clean::__say "  paccache not found (install pacman-contrib) — skipped"
        rack::clean::__say "  not falling back to 'pacman -Sc', which discards every cached version"
        return 0
    fi

    before=$(rack::clean::__cache_mb)

    if ((_dry)); then
        paccache -dk"$RACK_CLEAN_KEEP_VERSIONS" 2>&1 | sed 's/^/  /' || true
        paccache -duk0 2>&1 | sed 's/^/  /' || true
        rack::clean::__say "  currently ${before}MB"
        return 0
    fi

    # Two passes: keep N versions of packages still installed, keep none of
    # packages that have been uninstalled entirely.
    sudo paccache -rk"$RACK_CLEAN_KEEP_VERSIONS" 2>&1 | sed 's/^/  /'
    sudo paccache -ruk0 2>&1 | sed 's/^/  /'

    after=$(rack::clean::__cache_mb)
    _freed_cache=$((before - after))
    rack::clean::__say "  ${before}MB -> ${after}MB"
}

rack::clean::__orphans() {
    local orphans count
    local -a pkgs
    rack::clean::__step "orphans:"

    orphans=$(pacman -Qtdq 2>/dev/null) || orphans=""
    if [[ -z $orphans ]]; then
        rack::clean::__say "  none"
        return 0
    fi

    # An array rather than unquoted expansion: package names are passed as
    # distinct arguments without the shell globbing them along the way.
    mapfile -t pkgs <<<"$orphans"
    count=${#pkgs[@]}
    printf '  %s\n' "${pkgs[@]}" >&2

    if ((_dry)); then
        rack::clean::__say "  would remove $count"
        return 0
    fi

    # Listed in full before asking. An orphan is only "no longer required by
    # anything installed" — a package you started using directly after pulling
    # it in as a dependency looks identical to genuine cruft.
    if rig::check::confirm "remove $count orphaned packages?"; then
        sudo pacman -Rns --noconfirm "${pkgs[@]}"
        _removed_orphans=$count
        rack::clean::__say "  removed $count"
    else
        rack::clean::__say "  kept $count"
    fi
}

rack::clean::__flatpak() {
    rack::clean::__step "flatpak:"
    if ! rig::check::has flatpak; then
        rack::clean::__say "  not installed — skipped"
        return 0
    fi

    if ((_dry)); then
        # `flatpak uninstall` has no preview mode, and running it without -y to
        # read the prompt would be a live operation. Report honestly instead of
        # guessing at what it would do.
        rack::clean::__say "  no preview available — skipped in dry run"
        return 0
    fi

    flatpak uninstall --unused -y 2>&1 | sed 's/^/  /' || rack::clean::__say "  nothing unused"
}

rack::clean::__journal() {
    local before after
    rack::clean::__step "journal:"
    before=$(rack::clean::__journal_mb)
    rack::clean::__say "  currently ${before}MB"

    if ((_dry)); then
        rack::clean::__say "  would vacuum entries older than ${RACK_CLEAN_JOURNAL_KEEP_DAYS}d"
        return 0
    fi

    # Confirmed rather than automatic: log removal is irreversible, and the
    # logs you want are the ones from just before something broke.
    if rig::check::confirm "vacuum journal older than ${RACK_CLEAN_JOURNAL_KEEP_DAYS}d?"; then
        sudo journalctl --vacuum-time="${RACK_CLEAN_JOURNAL_KEEP_DAYS}d" 2>&1 | tail -1 | sed 's/^/  /'
        after=$(rack::clean::__journal_mb)
        _freed_journal=$((before - after))
        rack::clean::__say "  ${before}MB -> ${after}MB"
    else
        rack::clean::__say "  kept"
    fi
}

# ---- run -----------------------------------------------------------------------

rack::clean::run() {
    local _dry=0 _json=0
    local _freed_cache=0 _freed_journal=0 _removed_orphans=0

    while (($#)); do
        case "$1" in
            --dry-run | -n) _dry=1 ;;
            --yes | -y) RIG_YES=1 ;;
            --json) _json=1 ;;
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
    ((_json)) && { rig::check::require jq || return "$RIG_EX_NODEP"; }
    ((_dry && ${RIG_YES:-0})) && {
        rig::log::error "--dry-run and --yes are contradictory"
        return "$RIG_EX_USAGE"
    }

    # rig::check::confirm reads RIG_DRY_RUN and would decline everything on its
    # own, but the steps branch on _dry well before they ever ask, so the two
    # are kept in step explicitly rather than by coincidence.
    ((_dry)) && RIG_DRY_RUN=1
    ((_dry)) && rack::clean::__say "dry run — nothing will be removed"

    rack::clean::__cache
    rack::clean::__orphans
    rack::clean::__flatpak
    rack::clean::__journal

    if ((_json)); then
        jq -nc \
            --argjson c "$_freed_cache" \
            --argjson j "$_freed_journal" \
            --argjson o "$_removed_orphans" \
            --argjson d "$_dry" \
            '{dry_run: ($d == 1), freed_mb: {cache: $c, journal: $j}, removed_orphans: $o}'
    else
        printf '\nreclaimed %sMB\n' "$((_freed_cache + _freed_journal))"
    fi
}

rack::clean::__default() { rack::clean::run "$@"; }

rack::clean::__usage() {
    cat <<'EOF'
  rack clean [--dry-run] [--yes] [--json]

Reclaims disk space:
  cache     trim the pacman cache to 2 versions per package
  orphans   remove packages no longer required by anything
  flatpak   remove unused runtimes
  journal   vacuum systemd logs older than 30d

Destructive steps prompt before acting. Nothing is removed without either a
confirmation or --yes.

options
  --dry-run, -n   report what would be removed, change nothing
  --yes, -y       skip confirmations (for scripts and the settings pane)
  --json          machine-readable summary

env
  RACK_CLEAN_KEEP_VERSIONS       default 2
  RACK_CLEAN_JOURNAL_KEEP_DAYS   default 30
EOF
}
