# update — repository packages, then AUR, then flatpaks.
#
# Each stage must succeed before the next runs: continuing past a failed pacman
# upgrade would build AUR packages against a half-updated system.
#
# Before any of that it looks at what is waiting, all three sources at once,
# and lists it — so the run opens with what it is about to do rather than with
# a sudo prompt. A source with nothing waiting is not run at all, which means
# an already current system never asks for a password.
#
# Afterwards it reports what each stage changed and how long it took, whether
# a reboot is needed and whether the upgrade left any .pacnew files to
# reconcile.
#
# Ported from bin/orbit-update.

rig::load log check proc tmp
rack::load ui

RACK_MODULE_SUMMARY[update]="update pacman, AUR and flatpak packages"
RACK_MODULE_ACTIONS[update]="run"
RACK_MODULE_STATUS[update]="ready"
RACK_MODULE_TIER[update]="general"

# ---- presentation ------------------------------------------------------------

# Three stages always, and a skipped one still prints its header and its
# number. "2/3 AUR packages" followed by "skipped (--no-aur)" is a truer
# account of the run than renumbering around it and leaving the user to wonder
# whether the stage ran and found nothing or never ran at all.
readonly RACK_UPDATE_STAGE_COUNT=3

# How many packages the preview names per source before it says "and N more".
# The managers print the full list themselves a moment later; this is the
# glance, not the manifest.
readonly RACK_UPDATE_PREVIEW_ROWS=8

# When the last real upgrade started, from pacman's own log. A skipped run
# (nothing waiting) never reaches pacman, so it doesn't reset this — which is
# what "last updated" should mean.
rack::update::__last_run() {
    local line stamp then now ago
    [[ -r /var/log/pacman.log ]] || return 0
    line=$(grep -F 'starting full system upgrade' /var/log/pacman.log 2>/dev/null | tail -n1)
    [[ -n $line ]] || return 0
    stamp=${line#[}
    stamp=${stamp%%]*}
    then=$(date -d "$stamp" +%s 2>/dev/null) || return 0
    now=$(date +%s)
    ago=$((now - then))
    if ((ago < 3600)); then
        printf 'last updated %s' "$( ((ago < 120)) && echo "just now" || echo "$((ago / 60)) minutes ago")"
    elif ((ago < 86400)); then
        printf 'last updated %s' "$(rack::ui::plural $((ago / 3600)) hour) ago"
    elif ((ago < 14 * 86400)); then
        printf 'last updated %s' "$(rack::ui::plural $((ago / 86400)) day) ago"
    else
        printf 'last updated %s' "$(date -d "@$then" '+%-d %b')"
    fi
}

# The logo, with the machine beside it: what is being updated, on what, and
# how long since it last was. Printed once, before anything else takes the
# terminal. Skipped when stdout is not a terminal (the settings pane captures
# this output), so it never lands in a log or a pipe; a narrow window gets the
# text without the mark.
rack::update::__banner() {
    rack::ui::rich || return 0
    RACK_UI_HEADED=1
    local host distro="Arch Linux"
    host=$(cat /etc/hostname 2>/dev/null || uname -n)
    # shellcheck disable=SC1091
    [[ -r /etc/os-release ]] && distro=$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-$distro}")

    local -a text=(
        ""
        "${C_BOLD}System update${C_OFF}"
        "${C_MUTED}${distro} · ${host}${C_OFF}"
        "${C_MUTED}kernel $(uname -r)${C_OFF}"
        "${C_MUTED}$(rack::update::__last_run)${C_OFF}"
        ""
    )
    local -a mark=(
        "┏━━━━━━━━━━┓ ┏━━━━┓ ┏━━━━━━━━━━┓"
        "┃          ┃ ┃    ┃ ┃          ┃"
        "┃          ┃ ┗━━━━┛ ┃          ┃"
        "┃          ┃ ┏━━━━┓ ┃          ┃"
        "┃          ┃ ┃    ┃ ┃          ┃"
        "┗━━━━━━━━━━┛ ┗━━━━┛ ┗━━━━━━━━━━┛"
    )
    local i
    printf '\n'
    if ((RACK_UI_WIDTH < 64)); then
        for i in 1 2 3 4; do printf '  %s\n' "${text[i]}"; done
        return 0
    fi
    for i in "${!mark[@]}"; do
        printf '  %s%s%s   %s\n' "$C_ACCENT" "${mark[i]}" "$C_OFF" "${text[i]}"
    done
}

rack::update::__stage() {
    _stage_n=$((_stage_n + 1))
    if rack::ui::rich; then
        rack::ui::rule "$_stage_n/$RACK_UPDATE_STAGE_COUNT" "$1" "${2:-}"
    else
        printf '\n[%d/%d] %s%s\n' "$_stage_n" "$RACK_UPDATE_STAGE_COUNT" "$1" "${2:+ ($2)}"
    fi
}

# What a stage's heading says on its right: skipped, nothing waiting, the
# count the preview found, or nothing when the lookup could not tell.
rack::update::__stage_note() {
    local key=$1 why=$2 waiting=${_waiting[$1]-}
    if [[ -n $why ]]; then
        printf 'skipped'
    elif [[ $waiting == 0 ]]; then
        printf 'nothing waiting'
    elif [[ -n $waiting ]]; then
        rack::ui::plural "$waiting" update
    fi
}

rack::update::__note() { printf '  %s%s%s\n' "$C_MUTED" "$*" "$C_OFF"; }

# The line under a stage once its manager hands the terminal back — the
# verdict for that stage, where you are already looking.
rack::update::__done() {
    local key=$1
    printf '\n  %s %s' "$(rack::ui::glyph "${_level[$key]}")" "${_text[$key]}"
    [[ -n ${_time[$key]:-} ]] && printf ' %sin %s%s' "$C_MUTED" "${_time[$key]}" "$C_OFF"
    printf '\n'
}

# Every stage and check records its verdict here, and the summary repeats them
# all at the end. The managers put hundreds of lines on the terminal between
# the first stage and the last, so a verdict announced only when it is reached
# has scrolled off by the time anyone is ready to read it.
#
# _rows keeps the order so the summary reads in the order things happened; a
# stage that never ran simply never appears.
rack::update::__record() {
    _rows+=("$1")
    _level[$1]=$2
    _text[$1]=$3
}

rack::update::__summary() {
    declare -A label=(
        [repo]="Repository" [aur]="AUR" [flatpak]="Flatpak"
        [reboot]="Reboot" [pacnew]=".pacnew"
    )
    rack::ui::rule "" "Summary"
    rack::ui::rich || printf '\nsummary\n'
    local key colour worst=ok
    for key in "${_rows[@]}"; do
        case ${_level[$key]} in
            bad) worst=bad ;;
            warn) [[ $worst == ok ]] && worst=warn ;;
        esac
        colour=""
        [[ ${_level[$key]} == skip ]] && colour=$C_MUTED
        printf '  %s  %-12s%s%s%s' "$(rack::ui::glyph "${_level[$key]}")" \
            "${label[$key]:-$key}" "$colour" "${_text[$key]}" "$C_OFF"
        [[ -n ${_time[$key]:-} ]] && printf '  %s%s%s' "$C_MUTED" "${_time[$key]}" "$C_OFF"
        printf '\n'
    done
    [[ -n $_summary_extra ]] && printf '%s%s%s\n' "$C_MUTED" "$_summary_extra" "$C_OFF"

    local took
    took=$(rack::ui::duration $((SECONDS - _started)))
    printf '\n'
    case $worst in
        ok) printf '  %sAll done%s %sin %s%s\n' "$C_GREEN$C_BOLD" "$C_OFF" "$C_MUTED" "$took" "$C_OFF" ;;
        warn) printf '  %sDone, with something to look at above%s %sin %s%s\n' \
            "$C_YELLOW$C_BOLD" "$C_OFF" "$C_MUTED" "$took" "$C_OFF" ;;
        bad) printf '  %sFinished with problems — see above%s %safter %s%s\n' \
            "$C_RED$C_BOLD" "$C_OFF" "$C_MUTED" "$took" "$C_OFF" ;;
    esac
    return 0
}

# ---- what's waiting ------------------------------------------------------------

# All three lookups run at once, into files in a temp directory: pacman's
# takes about two seconds, the AUR's two and flatpak's five or six, so side by
# side the wait is the slowest of them rather than the sum. None of them
# touches the real sync database — checkupdates syncs a private copy, and
# `pacman -Sy` without the -u is how partial upgrades happen.
#
# Each writes <name>.rc beside its output. A lookup that failed (offline, a
# mirror down) leaves its source "unknown", and an unknown source runs its
# stage exactly as before the preview existed — the preview may only ever
# save work, never skip an update that was due.
# The lookups run in background subshells, which inherit rack's `set -e`: a
# bare `checkupdates; echo $?` would die at exit 2 ("none waiting") before
# writing it. __try records the status without letting errexit see it.
rack::update::__try() {
    local rc_file=$1 rc=0
    shift
    "$@" || rc=$?
    echo "$rc" >"$rc_file"
}

rack::update::__lookup() {
    local dir=$1
    local -a pids=()
    if rig::check::has checkupdates; then
        rack::update::__try "$dir/repo.rc" checkupdates >"$dir/repo" 2>/dev/null &
        pids+=($!)
    fi
    if ((!_skip_aur)) && rig::check::has yay; then
        # yay -Qua exits 1 both when nothing is waiting and when it failed;
        # only the second says anything on stderr.
        rack::update::__try "$dir/aur.rc" yay -Qua >"$dir/aur" 2>"$dir/aur.err" &
        pids+=($!)
    fi
    if ((!_skip_flatpak)) && rig::check::has flatpak; then
        rack::update::__try "$dir/flatpak.rc" flatpak remote-ls --updates --app \
            --columns=application,name,version >"$dir/flatpak" 2>/dev/null &
        pids+=($!)
        rack::update::__try "$dir/flatpak-all.rc" flatpak remote-ls --updates \
            --columns=application >"$dir/flatpak-all" 2>/dev/null &
        pids+=($!)
        rack::update::__try "$dir/flatpak-installed.rc" flatpak list --app \
            --columns=application,version >"$dir/flatpak-installed" 2>/dev/null &
        pids+=($!)
    fi

    # Waits on these pids only: a bare `wait` would also wait for the
    # spinner, which never ends on its own.
    rack::ui::spin_start "Looking for updates…"
    ((${#pids[@]})) && { wait "${pids[@]}" || true; }
    rack::ui::spin_stop
}

# Reads one source's lookup into _waiting[<key>] (a count, or empty for
# unknown) and _preview[<key>] (the rows to show, name \037 old \037 new).
rack::update::__read_repo() {
    local dir=$1 rc
    [[ -f $dir/repo.rc ]] || return 0
    rc=$(<"$dir/repo.rc")
    # checkupdates: 0 updates, 2 none, anything else it could not tell.
    case $rc in
        0) _preview[repo]=$(awk '{ print $1 "\037" $2 "\037" $4 }' "$dir/repo") ;;
        2) _preview[repo]="" ;;
        *) return 0 ;;
    esac
    _waiting[repo]=$(rack::update::__count "${_preview[repo]}")
}

rack::update::__read_aur() {
    local dir=$1 rc
    [[ -f $dir/aur.rc ]] || return 0
    rc=$(<"$dir/aur.rc")
    ((rc != 0)) && [[ -s $dir/aur.err ]] && return 0
    _preview[aur]=$(awk '{ print $1 "\037" $2 "\037" $4 }' "$dir/aur")
    _waiting[aur]=$(rack::update::__count "${_preview[aur]}")
}

# Apps by their display name with the installed version beside the new one;
# runtimes, which nobody picks by name, only as a count.
rack::update::__read_flatpak() {
    local dir=$1
    [[ -f $dir/flatpak.rc && -f $dir/flatpak-all.rc ]] || return 0
    [[ $(<"$dir/flatpak.rc") == 0 && $(<"$dir/flatpak-all.rc") == 0 ]] || return 0
    local n_all n_apps
    n_all=$(rack::update::__count "$(<"$dir/flatpak-all")")
    _preview[flatpak]=$(awk -F'\t' '
        NR == FNR { have[$1] = $2; next }
        { print ($2 != "" ? $2 : $1) "\037" have[$1] "\037" ($3 != "" ? $3 : "new build") }
    ' "$dir/flatpak-installed" "$dir/flatpak")
    n_apps=$(rack::update::__count "${_preview[flatpak]}")
    _runtimes=$((n_all - n_apps))
    ((_runtimes < 0)) && _runtimes=0
    _waiting[flatpak]=$n_all
}

rack::update::__count() {
    [[ -z $1 ]] && { echo 0; return 0; }
    printf '%s\n' "$1" | grep -c '[^[:space:]]' || true
}

# One source's block: its name and count, then up to PREVIEW_ROWS packages as
# name  old → new, then how many more there are.
rack::update::__show_source() {
    local key=$1 title=$2
    local n=${_waiting[$key]-}
    if [[ -z $n ]]; then
        printf '\n  %s%s%s  %scouldn'\''t check — the stage will look for itself%s\n' \
            "$C_BOLD" "$title" "$C_OFF" "$C_YELLOW" "$C_OFF"
        return 0
    fi
    if ((n == 0)); then
        printf '\n  %s%s%s  %sup to date%s\n' "$C_BOLD" "$title" "$C_OFF" "$C_MUTED" "$C_OFF"
        return 0
    fi
    printf '\n  %s%s%s  %s%s%s\n' "$C_BOLD" "$title" "$C_OFF" "$C_ACCENT" "$n" "$C_OFF"

    local name old new shown=0 rows=0
    [[ -n ${_preview[$key]} ]] && rows=$(rack::update::__count "${_preview[$key]}")
    # Fields are split on \037, not a tab: tab is whitespace to `read`, so an
    # empty field (a flatpak with no installed version) would collapse and
    # shift the next one into its place.
    while IFS=$'\037' read -r name old new; do
        [[ -z $name ]] && continue
        ((shown >= RACK_UPDATE_PREVIEW_ROWS)) && break
        shown=$((shown + 1))
        if [[ -n $old ]]; then
            printf '    %-26s %s%s → %s%s\n' "$name" "$C_MUTED" "$old" "$C_OFF" "$new"
        else
            printf '    %-26s %s\n' "$name" "$new"
        fi
    done <<<"${_preview[$key]}"
    ((rows > shown)) && rack::update::__note "  and $((rows - shown)) more"
    [[ $key == flatpak ]] && ((_runtimes)) &&
        rack::update::__note "  and $(rack::ui::plural "$_runtimes" runtime)"
    return 0
}

rack::update::__preview() {
    local dir
    rig::tmp::dir dir
    rack::update::__lookup "$dir"
    rack::update::__read_repo "$dir"
    ((_skip_aur)) || rack::update::__read_aur "$dir"
    ((_skip_flatpak)) || rack::update::__read_flatpak "$dir"

    local total=0 unknown=0 key
    for key in repo aur flatpak; do
        [[ $key == aur ]] && ((_skip_aur)) && continue
        [[ $key == flatpak ]] && ((_skip_flatpak)) && continue
        [[ $key == aur ]] && ! rig::check::has yay && continue
        [[ $key == flatpak ]] && ! rig::check::has flatpak && continue
        if [[ -z ${_waiting[$key]-} ]]; then
            unknown=1
        else
            total=$((total + _waiting[$key]))
        fi
    done

    if ((total == 0 && !unknown)); then
        _all_current=1
        printf '\n  %s✓ Everything is up to date.%s\n' "$C_GREEN$C_BOLD" "$C_OFF"
        return 0
    fi

    local note=""
    ((total)) && note=$(rack::ui::plural "$total" update)
    rack::ui::rule "" "Waiting" "$note" "$C_ACCENT"
    rack::ui::rich || printf '\nwaiting%s\n' "${note:+ ($note)}"
    rack::update::__show_source repo "Repository"
    ((_skip_aur)) || ! rig::check::has yay || rack::update::__show_source aur "AUR"
    ((_skip_flatpak)) || ! rig::check::has flatpak || rack::update::__show_source flatpak "Flatpak"

    # A kernel in the list means the summary will end on "reboot required";
    # saying so now lets you decide whether this is the moment for it.
    if printf '%s\n' "${_preview[repo]-}" "${_preview[aur]-}" |
        grep -qE "^linux(-lts|-zen|-hardened|-rt)?"$'\037'; then
        printf '\n  %s! A new kernel is in this update — reboot once it is done.%s\n' \
            "$C_YELLOW" "$C_OFF"
    fi
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

# A stage the preview found nothing for. Its header still prints, with the
# reason, and the manager is never started — for the repo stage that is the
# sudo prompt that no longer appears on a system that is already current.
rack::update::__nothing_waiting() {
    local key=$1
    [[ ${_waiting[$key]-} == 0 ]] || return 1
    rack::update::__record "$key" skip "nothing waiting"
    return 0
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
    rack::update::__record pacnew warn "$(rack::ui::plural "$n" file) pending — review with pacdiff"
    _summary_extra=$(printf '%s\n' "$files" | sed 's/^/                 /')
}

# ---- stages ------------------------------------------------------------------

rack::update::__repo() {
    rack::update::__stage "Repository packages" "$(rack::update::__stage_note repo "")"
    rack::update::__nothing_waiting repo && return 0

    local before after n t0=$SECONDS
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
        rack::update::__done repo
        rack::update::__summary
        rig::log::error "pacman failed — stopped before the AUR and flatpak stages"
        return "$RIG_EX_FAIL"
    fi

    after=$(rack::update::__pkg_snapshot)
    n=$(rack::update::__snapshot_changed "$before" "$after")
    _time[repo]=$(rack::ui::duration $((SECONDS - t0)))
    ((n)) && rack::update::__record repo ok "$(rack::ui::plural "$n" package) changed" ||
        rack::update::__record repo ok "already up to date"
    rack::update::__done repo
}

rack::update::__aur() {
    local why=""
    ((_skip_aur)) && why="--no-aur"
    [[ -z $why ]] && ! rig::check::has yay && why="yay not installed"

    rack::update::__stage "AUR packages" "$(rack::update::__stage_note aur "$why")"
    if [[ -n $why ]]; then
        rack::update::__record aur skip "skipped ($why)"
        return 0
    fi
    rack::update::__nothing_waiting aur && return 0

    local before after n t0=$SECONDS
    before=$(rack::update::__pkg_snapshot)

    local -a args=(-Sua)
    ((_yes)) && args+=(--noconfirm)

    # A failed AUR build is not fatal the way a failed repo upgrade is: the
    # system is already consistent, one package just did not build. Carry on to
    # the next stage rather than aborting, but remember it — see _stage_failed.
    if ! yay "${args[@]}"; then
        _stage_failed=1
        rack::update::__record aur bad "one or more packages did not build — review above"
        rack::update::__done aur
        return 0
    fi

    after=$(rack::update::__pkg_snapshot)
    n=$(rack::update::__snapshot_changed "$before" "$after")
    _time[aur]=$(rack::ui::duration $((SECONDS - t0)))
    ((n)) && rack::update::__record aur ok "$(rack::ui::plural "$n" package) changed" ||
        rack::update::__record aur ok "already up to date"
    rack::update::__done aur
}

rack::update::__flatpak() {
    local why=""
    ((_skip_flatpak)) && why="--no-flatpak"
    [[ -z $why ]] && ! rig::check::has flatpak && why="flatpak not installed"

    rack::update::__stage "Flatpak" "$(rack::update::__stage_note flatpak "$why")"
    if [[ -n $why ]]; then
        rack::update::__record flatpak skip "skipped ($why)"
        return 0
    fi
    rack::update::__nothing_waiting flatpak && return 0

    local before after n t0=$SECONDS
    before=$(rack::update::__flatpak_snapshot)

    local -a args=(update)
    ((_yes)) && args+=(-y)

    # Fails the run the same way a failed AUR build does. This stage used to
    # report its errors and still exit 0, which made `update && reboot` and the
    # settings pane treat a broken flatpak update as a clean one.
    if ! flatpak "${args[@]}"; then
        _stage_failed=1
        rack::update::__record flatpak bad "update reported errors — review above"
        rack::update::__done flatpak
        return 0
    fi

    after=$(rack::update::__flatpak_snapshot)
    n=$(rack::update::__snapshot_changed "$before" "$after")
    _time[flatpak]=$(rack::ui::duration $((SECONDS - t0)))
    # Runtimes are not in the app snapshot, so a run that only moved runtimes
    # counts no apps; say what the preview saw instead of "up to date".
    if ((n)); then
        rack::update::__record flatpak ok "$(rack::ui::plural "$n" app) changed"
    elif ((_runtimes)); then
        rack::update::__record flatpak ok "$(rack::ui::plural "$_runtimes" runtime) updated"
    else
        rack::update::__record flatpak ok "already up to date"
    fi
    rack::update::__done flatpak
}

# ---- run -----------------------------------------------------------------------

rack::update::run() {
    local _yes=0 _skip_aur=0 _skip_flatpak=0
    local _stage_n=0 _stage_failed=0 _summary_extra="" _runtimes=0 _all_current=0
    local _started=$SECONDS
    local -a _rows=()
    local -A _level=() _text=() _time=() _waiting=() _preview=()

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
    rack::ui::init
    rack::update::__banner

    # A stale lock from an interrupted run makes pacman fail with a confusing
    # message. Say plainly what it is and let the user decide.
    if [[ -e /var/lib/pacman/db.lck ]]; then
        rig::log::error "pacman database is locked (/var/lib/pacman/db.lck) — another
	package manager may be running. If nothing is, remove it with:
	    sudo rm /var/lib/pacman/db.lck"
        return "$RIG_EX_FAIL"
    fi

    rack::update::__preview

    # _stage_failed is set by any non-repo stage that failed. Those stages do
    # not stop the run — the system is still consistent and the later stages
    # are worth attempting — but the run as a whole did not do what was asked,
    # so it must not report success. A failed repo stage never reaches this.
    #
    # When the preview found nothing anywhere there is nothing to stage: three
    # headers saying "nothing waiting" under a line that already said so is
    # noise, so the run goes straight to the checks.
    if ((!_all_current)); then
        rack::update::__repo || return $?
        rack::update::__aur
        rack::update::__flatpak
    fi

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

Looks up what is waiting in all three sources, lists it, then updates
repository packages, then AUR packages, then flatpaks. Each stage must succeed
before the next runs — continuing past a failed pacman upgrade would build AUR
packages against a half-updated system.

A source with nothing waiting is not run, so an up-to-date system never asks
for sudo. A source whose lookup failed (offline, say) runs as usual.

Afterwards, reports what each stage changed and how long it took, whether a
reboot is needed and whether the upgrade left any .pacnew files to reconcile.

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
