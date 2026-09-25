# mirrors — refresh the pacman mirrorlist, keeping a restorable backup.
#
# The new list is written to a temporary file and checked for usable Server
# lines before it replaces the live one, so a failed or truncated reflector run
# cannot leave you unable to install anything.
#
# Ported from bin/orbit-mirrors. The hand-rolled EXIT trap is gone: rig's tmp
# module registers the cleanup on the trap stack when it hands out the file,
# which covers the argument-error paths the original needed a pre-initialised
# global to survive.

rig::load log check proc tmp trap
rack::load ui

RACK_MODULE_SUMMARY[mirrors]="refresh the pacman mirrorlist with reflector"
RACK_MODULE_ACTIONS[mirrors]="run"
RACK_MODULE_STATUS[mirrors]="ready"
RACK_MODULE_TIER[mirrors]="general"

: "${RACK_MIRRORS_LIST:=/etc/pacman.d/mirrorlist}"
: "${RACK_MIRRORS_BACKUP_DIR:=/etc/pacman.d/mirrorlist.d}"
: "${RACK_MIRRORS_KEEP_BACKUPS:=5}"
: "${RACK_MIRRORS_LATEST:=20}"

rack::mirrors::run() {
    local country="" dry=0

    while (($#)); do
        case "$1" in
            --country)
                shift
                (($#)) || {
                    rig::log::error "--country needs a value"
                    return "$RIG_EX_USAGE"
                }
                country=$1
                ;;
            --dry-run | -n) dry=1 ;;
            *)
                rig::log::error "unknown option: $1"
                return "$RIG_EX_USAGE"
                ;;
        esac
        shift
    done

    rig::check::require reflector || return "$RIG_EX_NODEP"

    local -a args=(--latest "$RACK_MIRRORS_LATEST" --protocol https --sort rate)
    [[ -n $country ]] && args+=(--country "$country")

    local tmp
    rig::tmp::file tmp || return $?

    rack::ui::header "Mirrors" "the $RACK_MIRRORS_LATEST fastest HTTPS mirrors${country:+ in $country}, via reflector$(
        ((dry)) && printf ' · dry run')"
    RACK_UI_NAME_WIDTH=10
    if rack::ui::rich; then
        printf '\n'
        rack::ui::spin_start "Ranking mirrors${country:+ in $country}…"
    else
        printf 'querying mirrors%s...\n' "${country:+ in $country}"
    fi
    # On a terminal reflector's stderr is held back while the spinner runs
    # and shown after it, one muted line per warning (a mirror that timed out
    # while being rated is routine); plain, it goes straight through.
    local rc=0 errors="" line
    if rack::ui::rich; then
        rig::tmp::file errors || return $?
        reflector "${args[@]}" --save "$tmp" 2>"$errors" || rc=$?
        rack::ui::spin_stop
        if [[ -s $errors ]]; then
            rack::ui::row warn "reflector" "$(rack::ui::plural "$(grep -c . "$errors")" warning)"
            while IFS= read -r line; do
                line=${line#\[*\] }
                rack::ui::note "  ${line#WARNING: }"
            done <"$errors"
            printf '\n'
        fi
    else
        reflector "${args[@]}" --save "$tmp" || rc=$?
    fi
    ((rc == 0)) || {
        rack::ui::finish bad "reflector failed — $RACK_MIRRORS_LIST left untouched"
        return "$RIG_EX_FAIL"
    }

    # A reflector run that dies partway can leave a file that parses but points
    # nowhere. Checking for actual Server lines is what makes the swap safe.
    local count
    count=$(grep -c '^Server = ' "$tmp" || true)
    ((count > 0)) || {
        rack::ui::finish bad "reflector returned no mirrors — $RACK_MIRRORS_LIST left untouched"
        return "$RIG_EX_FAIL"
    }

    if ((dry)); then
        if rack::ui::rich; then
            local server
            while read -r server; do
                rack::ui::note "  ${server#Server = }"
            done < <(grep '^Server = ' "$tmp")
            rack::ui::finish info "Dry run — would install $count mirrors"
        else
            printf '\nwould install %s mirrors:\n' "$count"
            grep '^Server = ' "$tmp" | sed 's/^Server = /  /'
        fi
        return 0
    fi

    local stamp backup
    stamp=$(date +%Y%m%d-%H%M%S)
    backup="$RACK_MIRRORS_BACKUP_DIR/mirrorlist.$stamp"

    sudo mkdir -p "$RACK_MIRRORS_BACKUP_DIR"
    if [[ -f $RACK_MIRRORS_LIST ]]; then
        sudo cp "$RACK_MIRRORS_LIST" "$backup"
        if rack::ui::rich; then
            rack::ui::row ok "backed up" "the old list" "$backup"
        else
            printf 'backed up to %s\n' "$backup"
        fi
    fi

    # install(1) rather than cp so ownership and mode are set in one step and
    # the file is never briefly world-writable.
    sudo install -m 0644 -o root -g root "$tmp" "$RACK_MIRRORS_LIST"
    if rack::ui::rich; then
        rack::ui::row ok "installed" "$count mirrors" "$RACK_MIRRORS_LIST"
    else
        printf 'installed %s mirrors\n' "$count"
    fi

    # Oldest backups pruned last, so a failure above never costs you a backup.
    local -a old
    mapfile -t old < <(sudo find "$RACK_MIRRORS_BACKUP_DIR" -maxdepth 1 -name 'mirrorlist.*' -printf '%T@ %p\n' 2>/dev/null |
        sort -rn | tail -n "+$((RACK_MIRRORS_KEEP_BACKUPS + 1))" | cut -d' ' -f2-)
    ((${#old[@]})) && sudo rm -f "${old[@]}"

    if rack::ui::rich; then
        rack::ui::finish ok "Mirrorlist refreshed" "next: rack update"
    else
        printf '\nrun: rack update\n'
    fi
}

rack::mirrors::__default() { rack::mirrors::run "$@"; }

rack::mirrors::__usage() {
    cat <<'EOF'
  rack mirrors [--country <name>] [--dry-run]

Fetches the 20 most recently synced HTTPS mirrors, sorted by download rate,
and installs them as /etc/pacman.d/mirrorlist.

The new list is written to a temporary file and checked for usable Server
lines before it replaces the live one, so a failed or truncated reflector
run cannot leave you unable to install anything.

The previous list is kept in /etc/pacman.d/mirrorlist.d (last 5 retained).

options
  --country <name>   restrict to one country, eg. --country Sweden
  --dry-run, -n      show the mirrors that would be used, change nothing

env
  RACK_MIRRORS_LATEST         how many mirrors to fetch (default 20)
  RACK_MIRRORS_KEEP_BACKUPS   default 5
EOF
}
