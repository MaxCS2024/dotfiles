# ui — how rack looks on a terminal.
#
# Every command draws from the same few pieces, so they read as one app rather
# than a dozen scripts: a header with the mark, rules for sections, a glyph per
# row (✓ ! ✗ ·), and one closing line that says how it went.
#
# Only on a terminal. When stdout is not one — the Conf menu reading
# `rack features list`, the tests, a pipe — every command prints exactly what
# it printed before this existed, and the verdicts go through rig::log as they
# always did. So each call site here has a plain twin, and the helpers that
# only decorate (header, rule, spinner) simply do nothing when plain.
#
# Colours are the terminal's ANSI slots, never RGB: the sixteen are the
# shell's palette (quickshell/main/theme/appcolors.js writes them), blue the
# accent and bright black the muted text, so this follows the wallpaper.

rig::load log trap

# ---- setup -------------------------------------------------------------------

# Idempotent; every helper calls it, so a module never has to.
rack::ui::init() {
    [[ -n ${RACK_UI_READY:-} ]] && return 0
    RACK_UI_READY=1
    RACK_UI_RICH=0
    [[ -t 1 && ${RACK_UI:-auto} != plain ]] && RACK_UI_RICH=1
    if ((RACK_UI_RICH)) && rig::log::color_enabled; then
        C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m'
        C_ACCENT=$'\033[34m' C_MUTED=$'\033[90m'
        C_BOLD=$'\033[1m' C_OFF=$'\033[0m'
    else
        C_RED='' C_GREEN='' C_YELLOW='' C_ACCENT='' C_MUTED='' C_BOLD='' C_OFF=''
    fi
    # Capped, because a task window is 60% of the monitor and a rule across
    # all of it reads as a page break, not a heading.
    local cols
    cols=$(tput cols 2>/dev/null) || cols=80
    ((cols > 84)) && cols=84
    ((cols < 40)) && cols=40
    RACK_UI_WIDTH=$((cols - 4))
    : "${RACK_UI_NAME_WIDTH:=14}"
    return 0
}

rack::ui::rich() {
    rack::ui::init
    ((RACK_UI_RICH))
}

# ---- words -------------------------------------------------------------------

# "3 packages" / "1 package", or "2 entries" given the plural. A count that
# reads wrong is the kind of small wrongness that makes the rest of the
# output look careless.
rack::ui::plural() {
    if (($1 == 1)); then
        printf '%s %s' "$1" "$2"
    else
        printf '%s %s' "$1" "${3:-${2}s}"
    fi
}

# "1m 12s", "48s".
rack::ui::duration() {
    local s=$1
    ((s >= 60)) && {
        printf '%dm %02ds' $((s / 60)) $((s % 60))
        return 0
    }
    printf '%ds' "$s"
}

# ---- pieces --------------------------------------------------------------------

# The mark in miniature, the command's name, and one line of context. Printed
# once per process: `rack sync` runs deploy and reload inside itself, and
# those must not each open with a header of their own.
rack::ui::header() {
    rack::ui::rich || return 0
    [[ -n ${RACK_UI_HEADED:-} ]] && return 0
    RACK_UI_HEADED=1
    printf '\n  %s┏━━┓┏┓┏━━┓%s  %s%s%s\n' "$C_ACCENT" "$C_OFF" "$C_BOLD" "$1" "$C_OFF"
    printf '  %s┗━━┛┗┛┗━━┛%s  %s%s%s\n' "$C_ACCENT" "$C_OFF" "$C_MUTED" "${2:-}" "$C_OFF"
}

# A heading with a rule running out to the width:  ── 1/3  Title ─────── note
# The note is plain text, painted in the colour given (muted by default), so
# its length is its width.
rack::ui::rule() {
    rack::ui::rich || return 0
    local lead=$1 title=$2 note=${3:-} note_colour=${4:-$C_MUTED}
    local plain="── ${lead:+$lead  }$title "
    [[ -n $note ]] && plain+=" $note"
    local fill=$((RACK_UI_WIDTH - ${#plain} - 1))
    ((fill < 3)) && fill=3
    local bar
    printf -v bar '%*s' "$fill" ''
    bar=${bar// /─}
    printf '\n  %s──%s ' "$C_MUTED" "$C_OFF"
    [[ -n $lead ]] && printf '%s%s%s  ' "$C_ACCENT" "$lead" "$C_OFF"
    printf '%s%s%s %s%s%s' "$C_BOLD" "$title" "$C_OFF" "$C_MUTED" "$bar" "$C_OFF"
    [[ -n $note ]] && printf ' %s%s%s' "$note_colour" "$note" "$C_OFF"
    printf '\n'
}

# ok ✓, warn !, bad ✗, info i, and skip · for a row with nothing to report —
# a stage with nothing to do, something switched off on purpose.
rack::ui::glyph() {
    rack::ui::init
    case $1 in
        ok) printf '%s✓%s' "$C_GREEN" "$C_OFF" ;;
        warn) printf '%s!%s' "$C_YELLOW" "$C_OFF" ;;
        bad) printf '%s✗%s' "$C_RED" "$C_OFF" ;;
        info) printf '%si%s' "$C_ACCENT" "$C_OFF" ;;
        *) printf '%s·%s' "$C_MUTED" "$C_OFF" ;;
    esac
}

# row <level> <name> <text> [aside]
#   ✓ hypr           linked         ~/.config/hypr
# A skip row is muted all the way along; the aside always is. A list whose
# asides should line up sets RACK_UI_TEXT_WIDTH.
rack::ui::row() {
    rack::ui::init
    local level=$1 name=$2 text=$3 aside=${4:-} tint=""
    [[ $level == skip ]] && tint=$C_MUTED
    printf '  %s %-*s %s%-*s%s' "$(rack::ui::glyph "$level")" "$RACK_UI_NAME_WIDTH" "$name" \
        "$tint" "${RACK_UI_TEXT_WIDTH:-0}" "$text" "$C_OFF"
    [[ -n $aside ]] && printf '  %s%s%s' "$C_MUTED" "$aside" "$C_OFF"
    printf '\n'
}

# item <level> <name> <plain text> [rich text] [aside]
# The one-line-per-entry shape most commands print. Plain, it is the old
#   "  hypr         linked (absent)"
# at RACK_UI_PLAIN_WIDTH, word for word; on a terminal, a row, with the
# rich text if there is one.
rack::ui::item() {
    local level=$1 name=$2 plain=$3 rich=${4:-} aside=${5:-}
    if rack::ui::rich; then
        rack::ui::row "$level" "$name" "${rich:-$plain}" "$aside"
    else
        printf '  %-*s %s\n' "${RACK_UI_PLAIN_WIDTH:-12}" "$name" "$plain"
    fi
}

# Muted text under a row or a rule, indented to sit with the rows.
rack::ui::note() {
    rack::ui::init
    printf '    %s%s%s\n' "$C_MUTED" "$*" "$C_OFF"
}

# say <level> <text> — a line in the middle of a run. On a terminal it is a
# glyph and the text (to stderr for warn and bad, like any error); plain, it
# is rig::log exactly as before.
rack::ui::say() {
    local level=$1
    shift
    if rack::ui::rich; then
        case $level in
            warn | bad) printf '  %s %s\n' "$(rack::ui::glyph "$level")" "$*" >&2 ;;
            *) printf '  %s %s\n' "$(rack::ui::glyph "$level")" "$*" ;;
        esac
        return 0
    fi
    case $level in
        ok) rig::log::success "$*" ;;
        warn) rig::log::warn "$*" ;;
        bad) rig::log::error "$*" ;;
        *) rig::log::info "$*" ;;
    esac
}

# finish <level> <text> [aside] — the closing line: how the whole run went,
# in its colour, with the aside (a time, a hint) muted after it. Plain, it is
# the rig::log line the command always ended on.
rack::ui::finish() {
    local level=$1 text=$2 aside=${3:-}
    if ! rack::ui::rich; then
        rack::ui::say "$level" "$text"
        return 0
    fi
    # Inside another command (sync runs deploy and reload) the closing line
    # is one step's, not the run's: a row, not the bold line the run ends on.
    if ((${RACK_UI_NESTED:-0})); then
        printf '  %s %s' "$(rack::ui::glyph "$level")" "$text"
        [[ -n $aside ]] && printf '  %s%s%s' "$C_MUTED" "$aside" "$C_OFF"
        printf '\n'
        return 0
    fi
    local colour=$C_MUTED
    case $level in
        ok) colour=$C_GREEN ;;
        warn) colour=$C_YELLOW ;;
        bad) colour=$C_RED ;;
        info) colour=$C_ACCENT ;;
    esac
    printf '\n  %s%s%s' "$colour$C_BOLD" "$text" "$C_OFF"
    [[ -n $aside ]] && printf '  %s%s%s' "$C_MUTED" "$aside" "$C_OFF"
    printf '\n'
}

# ---- waiting -------------------------------------------------------------------

# A spinner for work that prints nothing while it runs — lookups, checks,
# reflector ranking mirrors. It is its own process drawing on one line, so the
# work stays in this shell (health's checks fill arrays here); spin_stop
# clears the line before anything else is drawn. Nothing on a pipe.
rack::ui::spin_start() {
    rack::ui::rich || return 0
    local message=$1
    (
        trap - EXIT
        frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
        while :; do
            printf '\r  %s%s%s %s%s%s' "$C_ACCENT" "${frames:i%10:1}" "$C_OFF" \
                "$C_MUTED" "$message" "$C_OFF"
            i=$((i + 1))
            sleep 0.08
        done
    ) &
    RACK_UI_SPINNER=$!
    rig::trap::add "kill $RACK_UI_SPINNER 2>/dev/null || true"
}

rack::ui::spin_stop() {
    [[ -n ${RACK_UI_SPINNER:-} ]] || return 0
    kill "$RACK_UI_SPINNER" 2>/dev/null || true
    wait "$RACK_UI_SPINNER" 2>/dev/null || true
    RACK_UI_SPINNER=""
    printf '\r\033[K'
}
