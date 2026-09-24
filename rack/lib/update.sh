# update — repository packages, then AUR, then flatpaks.
#
# Each stage must succeed before the next runs: continuing past a failed pacman
# upgrade would build AUR packages against a half-updated system.
#
# Afterwards it reports what each stage changed, whether a reboot is needed and
# whether the upgrade left any .pacnew files to reconcile.
#
# Ported from bin/orbit-update.

rig::load log check proc

RACK_MODULE_SUMMARY[update]="update pacman, AUR and flatpak packages"
RACK_MODULE_ACTIONS[update]="run"
RACK_MODULE_STATUS[update]="ready"
RACK_MODULE_TIER[update]="general"

# ---- presentation ------------------------------------------------------------

# Three stages always, and a skipped one still prints its header and its
# number. "[2/3] AUR packages" followed by "skipped (--no-aur)" is a truer
# account of the run than renumbering around it and leaving the user to wonder
# whether the stage ran and found nothing or never ran at all.
readonly RACK_UPDATE_STAGE_COUNT=3

rack::update::__colors() {
    if rig::log::color_enabled; then
        C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m'
        C_BOLD=$'\033[1m' C_DIM=$'\033[2m' C_OFF=$'\033[0m'
    else
        C_RED='' C_GREEN='' C_YELLOW='' C_BOLD='' C_DIM='' C_OFF=''
    fi
}

# The logo. Shown once at the top of an interactive run, before the managers
# take over the terminal — a moment to see the run has started and by what.
# Skipped when stdout is not a terminal (the settings pane captures this
# output), so it never lands in a log or a pipe.
rack::update::__banner() {
    [[ -t 1 ]] || return 0
    printf '%s' "$C_BOLD"
    cat <<'EOF'
┏━━━━━━━━━━┓ ┏━━━━┓ ┏━━━━━━━━━━┓
┃          ┃ ┃    ┃ ┃          ┃
┃          ┃ ┗━━━━┛ ┃          ┃
┃          ┃ ┏━━━━┓ ┃          ┃
┃          ┃ ┃    ┃ ┃          ┃
┗━━━━━━━━━━┛ ┗━━━━┛ ┗━━━━━━━━━━┛
EOF
    printf '%s' "$C_OFF"
}

rack::update::__stage() {
    _stage_n=$((_stage_n + 1))
    printf '\n%s[%d/%d] %s%s\n' "$C_BOLD" "$_stage_n" "$RACK_UPDATE_STAGE_COUNT" "$1" "$C_OFF"
}

rack::update::__note() { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }

# Every stage and check records its verdict here, and nothing prints until the
# run is over. The managers put hundreds of lines on the terminal between the
# first stage and the last, so a verdict announced when it is reached has
# scrolled off by the time anyone is ready to read it.
#
# _rows keeps the order so the summary reads in the order things happened; a
# stage that never ran simply never appears.
rack::update::__record() {
    _rows+=("$1")
    _level[$1]=$2
    _text[$1]=$3
}

rack::update::__level_colour() {
    case $1 in
        ok) printf '%s' "$C_GREEN" ;;
        warn) printf '%s' "$C_YELLOW" ;;
        bad) printf '%s' "$C_RED" ;;
    esac
}

# The column width and the two-space indent match rig::diag::print, so
# `rack update` and `relay network status` produce the same shape of table.
rack::update::__summary() {
    printf '\n%ssummary%s\n' "$C_BOLD" "$C_OFF"
    local key
    for key in "${_rows[@]}"; do
        printf '  %-11s%s%s%s\n' \
            "$key" "$(rack::update::__level_colour "${_level[$key]}")" "${_text[$key]}" "$C_OFF"
    done
    [[ -n $_summary_extra ]] && printf '%s\n' "$_summary_extra"
    return 0
}

# ---- what changed ------------------------------------------------------------

# Counted from pacman's own database rather than by reading what the managers
# printed: their output is theirs to reformat, and both stages have to keep the
# terminal to themselves for password prompts, PKGBUILD diffs and progress
# bars, so there is no piped copy to parse in the first place.
rack::update::__pkg_snapshot() { pacman -Q 2>/dev/null | sort || true; }

rack::update::__flatpak_snapshot() {
    flatpak list --app --columns=application,version 2>/dev/null | sort || true
}

# Lines in the second snapshot and not the first — a package that arrived, or
# one whose version moved. Both are "changed" here, which is the honest word:
# an upgrade that also pulls a new dependency did both.
rack::update::__snapshot_changed() {
    comm -13 <(printf '%s\n' "$1") <(printf '%s\n' "$2") |
        grep -c '[^[:space:]]' || true
}

# "3 packages" / "1 package". A count that reads wrong is the kind of small
# wrongness that makes the rest of the output look careless.
rack::update::__plural() {
    printf '%s %s' "$1" "$2$( (($1 == 1)) || printf 's')"
}

# ---- post-update checks ------------------------------------------------------

rack::update::__check_reboot() {
    # The running kernel's module tree is removed when its package is replaced,
    # so a missing directory means modules can no longer be loaded and a reboot
    # is required. This works for any kernel package — linux, -lts, -zen — and
    # needs no version-string parsing.
    if [[ ! -d /usr/lib/modules/$(uname -r) ]]; then
        rack::update::__record reboot warn "required — the running kernel was replaced"
        return 0
    fi
    rack::update::__record reboot ok "not required"
}

rack::update::__check_pacnew() {
    local files n
    files=$(find /etc -type f \( -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null) || files=""
    if [[ -z $files ]]; then
        rack::update::__record pacnew ok "none pending"
        return 0
    fi
    n=$(printf '%s\n' "$files" | wc -l)
    # Surfaced here because an upgrade is what creates them, and this is the
    # one moment the user is guaranteed to be looking.
    rack::update::__record pacnew warn "$(rack::update::__plural "$n" file) pending — review with pacdiff"
    _summary_extra=$(printf '%s\n' "$files" | sed 's/^/               /')
}

# ---- stages ------------------------------------------------------------------

rack::update::__repo() {
    rack::update::__stage "repository packages"
    local before after n
    before=$(rack::update::__pkg_snapshot)

    local -a args=(-Syu)
    ((_yes)) && args+=(--noconfirm)

    # No `|| true` anywhere in this function. A failed repo upgrade must stop
    # the run — this is the whole point of the command. The summary still
    # prints: which stages did *not* run is the thing worth knowing here, and
    # pacman has already said why above.
    if ! sudo pacman "${args[@]}"; then
        rack::update::__record repo bad "failed — see pacman's output above"
        rack::update::__record aur warn "not run"
        rack::update::__record flatpak warn "not run"
        rack::update::__summary
        rig::log::error "pacman failed — stopped before the AUR and flatpak stages"
        return "$RIG_EX_FAIL"
    fi

    after=$(rack::update::__pkg_snapshot)
    n=$(rack::update::__snapshot_changed "$before" "$after")
    ((n)) && rack::update::__record repo ok "$(rack::update::__plural "$n" package) changed" ||
        rack::update::__record repo ok "already up to date"
}

rack::update::__aur() {
    rack::update::__stage "AUR packages"

    local why=""
    ((_skip_aur)) && why="--no-aur"
    [[ -z $why ]] && ! rig::check::has yay && why="yay not installed"
    if [[ -n $why ]]; then
        rack::update::__note "skipped ($why)"
        rack::update::__record aur warn "skipped ($why)"
        return 0
    fi

    local before after n
    before=$(rack::update::__pkg_snapshot)

    local -a args=(-Sua)
    ((_yes)) && args+=(--noconfirm)

    # A failed AUR build is not fatal the way a failed repo upgrade is: the
    # system is already consistent, one package just did not build. Carry on to
    # the next stage rather than aborting, but remember it — see _stage_failed.
    if ! yay "${args[@]}"; then
        _stage_failed=1
        rack::update::__record aur bad "one or more packages did not build — review above"
        return 0
    fi

    after=$(rack::update::__pkg_snapshot)
    n=$(rack::update::__snapshot_changed "$before" "$after")
    ((n)) && rack::update::__record aur ok "$(rack::update::__plural "$n" package) changed" ||
        rack::update::__record aur ok "already up to date"
}

rack::update::__flatpak() {
    rack::update::__stage "flatpak"

    local why=""
    ((_skip_flatpak)) && why="--no-flatpak"
    [[ -z $why ]] && ! rig::check::has flatpak && why="flatpak not installed"
    if [[ -n $why ]]; then
        rack::update::__note "skipped ($why)"
        rack::update::__record flatpak warn "skipped ($why)"
        return 0
    fi

    local before after n
    before=$(rack::update::__flatpak_snapshot)

    local -a args=(update)
    ((_yes)) && args+=(-y)

    # Fails the run the same way a failed AUR build does. This stage used to
    # report its errors and still exit 0, which made `update && reboot` and the
    # settings pane treat a broken flatpak update as a clean one.
    if ! flatpak "${args[@]}"; then
        _stage_failed=1
        rack::update::__record flatpak bad "update reported errors — review above"
        return 0
    fi

    after=$(rack::update::__flatpak_snapshot)
    n=$(rack::update::__snapshot_changed "$before" "$after")
    ((n)) && rack::update::__record flatpak ok "$(rack::update::__plural "$n" app) changed" ||
        rack::update::__record flatpak ok "already up to date"
}

# ---- run -----------------------------------------------------------------------

rack::update::run() {
    local _yes=0 _skip_aur=0 _skip_flatpak=0
    local _stage_n=0 _stage_failed=0 _summary_extra=""
    local -a _rows=()
    local -A _level=() _text=()
    local C_RED C_GREEN C_YELLOW C_BOLD C_DIM C_OFF

    while (($#)); do
        case "$1" in
            --yes | -y) _yes=1 ;;
            --no-aur) _skip_aur=1 ;;
            --no-flatpak) _skip_flatpak=1 ;;
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
    rack::update::__colors
    rack::update::__banner

    # A stale lock from an interrupted run makes pacman fail with a confusing
    # message. Say plainly what it is and let the user decide.
    if [[ -e /var/lib/pacman/db.lck ]]; then
        rig::log::error "pacman database is locked (/var/lib/pacman/db.lck) — another
	package manager may be running. If nothing is, remove it with:
	    sudo rm /var/lib/pacman/db.lck"
        return "$RIG_EX_FAIL"
    fi

    # _stage_failed is set by any non-repo stage that failed. Those stages do
    # not stop the run — the system is still consistent and the later stages
    # are worth attempting — but the run as a whole did not do what was asked,
    # so it must not report success. A failed repo stage never reaches this.
    rack::update::__repo || return $?
    rack::update::__aur
    rack::update::__flatpak

    rack::update::__check_reboot
    rack::update::__check_pacnew
    rack::update::__summary

    ((_stage_failed)) && return "$RIG_EX_FAIL"
    return 0
}

rack::update::__default() { rack::update::run "$@"; }

rack::update::__usage() {
    cat <<'EOF'
  rack update [--yes] [--no-aur] [--no-flatpak]

Updates repository packages, then AUR packages, then flatpaks. Each stage
must succeed before the next runs — continuing past a failed pacman upgrade
would build AUR packages against a half-updated system.

Afterwards, reports what each stage changed, whether a reboot is needed and
whether the upgrade left any .pacnew files to reconcile.

options
  --yes, -y      non-interactive (implies --noconfirm)
  --no-aur       skip the AUR stage
  --no-flatpak   skip the flatpak stage

Exits non-zero if any stage failed, including a flatpak update that reported
errors. A skipped stage is not a failure.

env
  RIG_COLOR   auto|always|never — NO_COLOR is honoured
EOF
}
