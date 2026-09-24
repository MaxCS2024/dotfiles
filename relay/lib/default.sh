# default — which app does each role: terminal, editor, browser, file manager.
#
# The interface to the default apps. The candidates, the order a default
# resolves in and what each app needs to be launched all live in
# hypr/modules/defaults.lua, because Hyprland has to read them in-process at
# config load (docs/adr/0001). This runs that same file as a script, through
# its deployed path under ~/.config/hypr, so the shell and the binds always
# get one answer. What this side owns is the part that is shell work:
# writing the default, telling XDG about it, reloading Hyprland, and
# starting the app.
#
# The words are the ones quickshell/CONTEXT.md defines: a role has
# candidates, resolves to a default, and has a handler that setting the
# default rewrites to match.

rig::load log check proc tmp trap

RELAY_MODULE_SUMMARY[default]="the default terminal, editor, browser and file manager"
RELAY_MODULE_ACTIONS[default]="get list set unset exec"
RELAY_MODULE_STATUS[default]="ready"
RELAY_MODULE_TIER[default]="core"

relay::default::__module() {
    printf '%s\n' "${RELAY_DEFAULTS_LUA:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/modules/defaults.lua}"
}

relay::default::__state_dir() {
    printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/rack/defaults"
}

# Made once, in the process that owns rig's cleanup stack: a temp file
# registered inside $(...) would be cleaned up by nobody.
relay::default::__init() {
    [[ -n ${RELAY_DEFAULT_OUT:-} ]] && return 0
    rig::tmp::file RELAY_DEFAULT_OUT && rig::tmp::file RELAY_DEFAULT_ERR
}

# Run the Lua side with its stdout in $RELAY_DEFAULT_OUT. Its complaints
# come back through rig's log, so they read like every other relay error.
relay::default::__lua() {
    local module status line

    rig::check::has lua || {
        rig::log::error "lua not found — the default apps need it (pacman -S lua)"
        return "$RIG_EX_NODEP"
    }
    module=$(relay::default::__module)
    [[ -r $module ]] || {
        rig::log::error "no $module — is hypr deployed? (rack deploy hypr)"
        return "$RIG_EX_FAIL"
    }

    relay::default::__init || return $?
    # `|| status=$?` rather than reading $? after: relay runs under set -e,
    # which would end the script here, before the message below is logged.
    status=0
    lua "$module" "$@" >"$RELAY_DEFAULT_OUT" 2>"$RELAY_DEFAULT_ERR" || status=$?
    while IFS= read -r line; do
        [[ -n $line ]] && rig::log::error "$line"
    done <"$RELAY_DEFAULT_ERR"
    return "$status"
}

# describe <array name> <role> [--stored <value> | --unset] — what the role
# resolves to (or would, with that stored), as role, source, name, label,
# installed, command, desktop, handler, mimes and candidates.
relay::default::__describe() {
    local -n __rd_into=$1
    local key value
    shift

    relay::default::__lua describe "$@" || return $?
    __rd_into=()
    while IFS=$'\t' read -r key value; do
        [[ -n $key ]] && __rd_into[$key]=$value
    done <"$RELAY_DEFAULT_OUT"
}

# The one role argument every action takes, checked before anything runs.
relay::default::__role() {
    [[ -n ${1:-} ]] || {
        rig::log::error "which role? (terminal, editor, browser, file-manager)"
        return "$RIG_EX_USAGE"
    }
}

# ---- reading -----------------------------------------------------------------

# get <role> — the command the role's keybind runs.
relay::default::get() {
    (($# <= 1)) || {
        rig::log::error "get takes one role (see: relay help default)"
        return "$RIG_EX_USAGE"
    }
    relay::default::__role "${1:-}" || return $?

    local -A found=()
    relay::default::__describe found "$1" || return $?
    printf '%s\n' "${found[command]}"
}

# list [--json] [role] — every role's default, or one role's candidates.
relay::default::list() {
    local json=0 role="" a
    for a in "$@"; do
        case $a in
            --json) json=1 ;;
            -*)
                rig::log::error "unknown option '$a' (see: relay help default)"
                return "$RIG_EX_USAGE"
                ;;
            *)
                [[ -z $role ]] || {
                    rig::log::error "unexpected argument '$a' (see: relay help default)"
                    return "$RIG_EX_USAGE"
                }
                role=$a
                ;;
        esac
    done

    # --json is every role with its candidates in one document, which is the
    # whole of what the Conf menu reads. A role narrows the text form only.
    if ((json)); then
        [[ -z $role ]] || {
            rig::log::error "--json lists every role; drop '$role'"
            return "$RIG_EX_USAGE"
        }
        relay::default::__lua list --json || return $?
    elif [[ -n $role ]]; then
        relay::default::__lua candidates "$role" || return $?
    else
        relay::default::__lua list || return $?
    fi
    cat -- "$RELAY_DEFAULT_OUT"
}

# ---- writing -----------------------------------------------------------------

relay::default::__write() {
    local path=$1 content=$2
    if ((${RIG_DRY_RUN:-0})); then
        printf 'would write %q to %s\n' "$content" "$path"
        return 0
    fi
    mkdir -p -- "${path%/*}" && printf '%s\n' "$content" >"$path"
}

# Point XDG at the default in <array name>. A default with no .desktop file
# (a custom command, or an app not installed) leaves the handler as it was:
# there is nothing to point it at.
relay::default::__handler() {
    local -n __rd_found=$1
    local desktop=${__rd_found[desktop]:-}
    local -a mimes=()

    if [[ -z $desktop ]]; then
        rig::log::warn "no .desktop file for this ${__rd_found[role]} — its handler is left as it was"
        return 0
    fi

    case ${__rd_found[handler]} in
        terminals-list)
            # The file xdg-terminal-exec reads.
            relay::default::__write "${XDG_CONFIG_HOME:-$HOME/.config}/xdg-terminals.list" "$desktop"
            ;;
        mime)
            rig::check::has xdg-mime || {
                rig::log::warn "xdg-mime not found — the ${__rd_found[role]} handler is left as it was"
                return 0
            }
            read -ra mimes <<<"${__rd_found[mimes]}"
            rig::proc::run xdg-mime default "$desktop" "${mimes[@]}"
            ;;
        web-browser)
            rig::check::has xdg-settings || {
                rig::log::warn "xdg-settings not found — the browser handler is left as it was"
                return 0
            }
            # With $BROWSER in the environment, xdg-settings acts on that
            # instead of the XDG database and reports success either way.
            rig::proc::run env -u BROWSER xdg-settings set default-web-browser "$desktop"
            ;;
    esac
}

# The binds captured their commands at config load, so a new default only
# reaches SUPER+RETURN once Hyprland reloads. Outside a Hyprland session
# there is nothing to reload: the next start reads the new default anyway.
relay::default::__reload() {
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && rig::check::has hyprctl || return 0
    if ((${RIG_DRY_RUN:-0})); then
        rig::proc::run hyprctl reload
    else
        hyprctl reload >/dev/null
    fi
}

relay::default::__say() {
    local -n __rd_said=$1
    if [[ ${__rd_said[source]} == custom ]]; then
        rig::log::success "${__rd_said[role]} is now: ${__rd_said[command]}"
    else
        rig::log::success "${__rd_said[role]} is now ${__rd_said[label]}"
    fi
}

# set <role> <candidate> | set <role> --command <command line>
relay::default::set() {
    local role="" value="" custom=0

    while (($#)); do
        case $1 in
            --command)
                (($# >= 2)) || {
                    rig::log::error "--command needs the command line"
                    return "$RIG_EX_USAGE"
                }
                [[ -z $value ]] || {
                    rig::log::error "a candidate or --command, not both"
                    return "$RIG_EX_USAGE"
                }
                custom=1 value=$2
                shift 2
                continue
                ;;
            -*)
                rig::log::error "unknown option '$1' (see: relay help default)"
                return "$RIG_EX_USAGE"
                ;;
            *)
                if [[ -z $role ]]; then
                    role=$1
                elif [[ -z $value && $custom == 0 ]]; then
                    value=$1
                else
                    rig::log::error "unexpected argument '$1' (see: relay help default)"
                    return "$RIG_EX_USAGE"
                fi
                ;;
        esac
        shift
    done

    relay::default::__role "$role" || return $?
    [[ -n ${value//[[:space:]]/} ]] || {
        rig::log::error "set $role to what? a candidate (relay default list $role) or --command"
        return "$RIG_EX_USAGE"
    }
    [[ $value != *$'\n'* ]] || {
        rig::log::error "a default is one line"
        return "$RIG_EX_USAGE"
    }

    local -A found=()
    relay::default::__describe found "$role" --stored "$value" || return $?

    # A bare word that is no candidate is almost always a typo, not a
    # command: `set browser firefx` should not quietly become a bind that
    # runs "firefx". Custom commands say so with --command.
    if ((!custom)) && [[ ${found[source]} == custom ]]; then
        rig::log::error "no candidate '$value' for $role (candidates: ${found[candidates]}; or use --command)"
        return "$RIG_EX_USAGE"
    fi
    if [[ ${found[source]} == set && ${found[installed]} == 0 ]]; then
        rig::log::warn "${found[label]} is not installed — set anyway; the $role keybind fails until it is"
    fi

    relay::default::__write "$(relay::default::__state_dir)/$role" "$value" || return $?
    relay::default::__handler found || return $?
    relay::default::__reload
    relay::default::__say found
}

# unset <role> — back to the first installed candidate.
relay::default::unset() {
    (($# <= 1)) || {
        rig::log::error "unset takes one role (see: relay help default)"
        return "$RIG_EX_USAGE"
    }
    relay::default::__role "${1:-}" || return $?

    local -A found=()
    relay::default::__describe found "$1" --unset || return $?

    rig::proc::run rm -f -- "$(relay::default::__state_dir)/$1" || return $?
    relay::default::__handler found || return $?
    relay::default::__reload
    relay::default::__say found
}

# ---- starting ----------------------------------------------------------------

# exec <role>
# exec terminal [--app-id <id>] [--title <title>] [-- <command...>]
# exec browser [--app <url>]
relay::default::exec() {
    local role=${1:-} app_id="" title="" url="" has_command=0
    local -a words=()

    relay::default::__role "$role" || return $?
    shift

    while (($#)); do
        case $1 in
            --app-id | --title | --app)
                (($# >= 2)) || {
                    rig::log::error "$1 needs a value"
                    return "$RIG_EX_USAGE"
                }
                case $1:$role in
                    --app-id:terminal) app_id=$2 ;;
                    --title:terminal) title=$2 ;;
                    --app:browser) url=$2 ;;
                    *)
                        rig::log::error "$1 is not an option for $role (see: relay help default)"
                        return "$RIG_EX_USAGE"
                        ;;
                esac
                shift 2
                continue
                ;;
            --)
                [[ $role == terminal ]] || {
                    rig::log::error "only the terminal runs a command (see: relay help default)"
                    return "$RIG_EX_USAGE"
                }
                shift
                has_command=1 words=("$@")
                break
                ;;
            *)
                rig::log::error "unexpected argument '$1' (see: relay help default)"
                return "$RIG_EX_USAGE"
                ;;
        esac
    done

    if ((has_command)) && ((${#words[@]} == 0)); then
        rig::log::error "nothing after -- to run"
        return "$RIG_EX_USAGE"
    fi

    # The words after -- are one shell command line, joined with spaces the
    # way ssh joins them, so `-- make -j8` and `-- 'make -j8'` are the same.
    if [[ $role == terminal ]]; then
        if ((has_command)); then
            relay::default::__lua argv terminal "$app_id" "$title" "${words[*]}" || return $?
        else
            relay::default::__lua argv terminal "$app_id" "$title" || return $?
        fi
    elif [[ -n $url ]]; then
        relay::default::__lua argv webapp "$url" || return $?
    else
        relay::default::__lua argv "$role" || return $?
    fi

    local -a argv=()
    mapfile -d '' -t argv <"$RELAY_DEFAULT_OUT"
    ((${#argv[@]})) || {
        rig::log::error "nothing to run for $role"
        return "$RIG_EX_FAIL"
    }

    if ((${RIG_DRY_RUN:-0})); then
        rig::proc::run "${argv[@]}"
        return
    fi

    # exec replaces this process, so rig's exit trap never runs: clean up
    # now. Replaced rather than waited on because uwsm-app stays until the
    # app it started exits, and a caller that spawned this detached should
    # not be left holding a bash for the lifetime of a terminal.
    rig::trap::fire
    exec "${argv[@]}"
}

relay::default::__usage() {
    cat <<'EOF'
  relay default get <role>
  relay default list [<role>] [--json]
  relay default set <role> <candidate>
  relay default set <role> --command <command line>
  relay default unset <role>
  relay default exec <role>
  relay default exec terminal [--app-id <id>] [--title <title>] [-- <command...>]
  relay default exec browser [--app <url>]

roles
  terminal, editor, browser, file-manager

A role's default is the candidate you set, else a custom command you set,
else the first candidate installed here. `list <role>` shows the
candidates. set and unset also point the XDG handler at the new default
and reload Hyprland, so the keybinds follow.

exec starts the default. For the terminal, the words after -- are one
shell command line; --app-id and --title are passed in whatever form that
terminal takes. `exec browser --app <url>` opens the page as a window of
its own where the browser can, and in an ordinary tab where it cannot.

options
  --json    list: every role and its candidates as JSON

env
  RELAY_DEFAULTS_LUA   the Lua module (default: ~/.config/hypr/modules/defaults.lua)
  XDG_STATE_HOME       where set defaults are kept, under rack/defaults/

examples
  relay default list
  relay default set browser firefox
  relay default set terminal --command "wezterm start"
  relay default exec terminal --title Update -- sudo pacman -Syu
EOF
}
