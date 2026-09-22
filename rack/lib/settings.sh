# settings — read-only inspection of schema.json and the live quickshell
# settings.json.
#
# Two files answer "what is this desktop set to": rack/schema.json, which
# declares every setting the shell has along with its default, and the
# settings.json quickshell writes under its own data directory. This reads both
# and reports the effective value, marking which ones are still defaults.
#
# Nothing here writes. Changing a setting is the shell's job (its settings
# panes own the validation), and a CLI that wrote the same file behind the
# running shell's back would be overwritten by the next autosave.
#
# Ported from bin/orbit-config, renamed because rig already has a `config`
# module for the values rack itself stores, and two things called config in one
# process is one too many. The schema moved from orbit/schema.json to
# rack/schema.json with it.

rig::load log check

RACK_MODULE_SUMMARY[settings]="inspect the shell's schema and live settings"
RACK_MODULE_ACTIONS[settings]="list get schema path"
RACK_MODULE_STATUS[settings]="ready"
RACK_MODULE_TIER[settings]="general"

rack::settings::__schema() {
    printf '%s\n' "${RACK_SCHEMA:-$RACK_ROOT/schema.json}"
}

rack::settings::__require_schema() {
    local s
    s=$(rack::settings::__schema)
    [[ -f $s ]] || {
        rig::log::error "schema not found: $s"
        return "$RIG_EX_FAIL"
    }
    rig::check::require jq || return "$RIG_EX_NODEP"
}

# ---- settings file resolution -----------------------------------------------

# Quickshell.dataPath("settings.json") resolves under a per-shell hash
# directory (by-shell/<hash>, not by-id as you'd guess from the API name —
# confirmed by inspecting $XDG_DATA_HOME/quickshell on a running system). That
# hash isn't derivable from the config name, so on a single-shell machine we
# discover it by looking for the one settings.json that exists; RACK_SETTINGS
# bypasses discovery entirely for testing or multi-shell setups.
rack::settings::path() {
    if [[ -n ${RACK_SETTINGS:-} ]]; then
        printf '%s\n' "$RACK_SETTINGS"
        return 0
    fi

    local base="${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/by-shell"
    local -a hits
    shopt -s nullglob
    hits=("$base"/*/settings.json)
    case ${#hits[@]} in
        1)
            printf '%s\n' "${hits[0]}"
            shopt -u nullglob
            return 0
            ;;
        0) ;;
        *)
            shopt -u nullglob
            rig::log::error "multiple settings.json found under $base — set RACK_SETTINGS to pick one"
            return "$RIG_EX_FAIL"
            ;;
    esac

    # No settings.json has been written yet. If there's exactly one per-shell
    # directory, that's presumably the one quickshell will use.
    local -a dirs
    dirs=("$base"/*/)
    shopt -u nullglob
    if [[ ${#dirs[@]} -eq 1 ]]; then
        printf '%s\n' "${dirs[0]}settings.json"
        return 0
    fi

    rig::log::error "can't determine the live settings.json under $base (none written yet, and shell dirs aren't unique) — set RACK_SETTINGS"
    return "$RIG_EX_FAIL"
}

# ---- schema access ------------------------------------------------------------

rack::settings::__keys() {
    jq -r '.settings | keys[]' "$(rack::settings::__schema)"
}

rack::settings::__key_in_schema() {
    jq -e --arg k "$1" '.settings | has($k)' "$(rack::settings::__schema)" >/dev/null
}

# Reads the live settings file, if any. Prints "{}" (not an error) when the
# file is missing — callers fall back to schema defaults for that case. Exit
# status reflects whether the file, if present, was valid JSON.
rack::settings::__read_live() {
    local path=$1
    [[ -e $path ]] || {
        printf '{}'
        return 0
    }
    jq -e '.' "$path" 2>/dev/null
}

# ---- actions -------------------------------------------------------------------

rack::settings::schema() {
    rack::settings::__require_schema || return $?
    local s json=0
    s=$(rack::settings::__schema)
    [[ ${1-} == --json ]] && json=1

    if ((json)); then
        cat "$s"
        return 0
    fi

    printf 'shell settings schema (version %s)\n\n' "$(jq -r '.version' "$s")"
    local key
    while IFS= read -r key; do
        jq -r --arg k "$key" '
			.settings[$k] as $s |
			"\($k)  (\($s.type), pane: \($s.pane), applies: \($s.applies))\n" +
			"  label: \($s.label)\n" +
			"  default: \($s.default)" +
			(if $s.enum then "\n  enum: \($s.enum | join(", "))" else "" end) +
			(if $s.min != null then "\n  min: \($s.min)" else "" end) +
			(if $s.max != null then "\n  max: \($s.max)" else "" end) +
			(if $s.description then "\n  \($s.description)" else "" end)
		' "$s"
        printf '\n'
    done < <(rack::settings::__keys)
}

rack::settings::list() {
    rack::settings::__require_schema || return $?
    local s json=0
    s=$(rack::settings::__schema)
    [[ ${1-} == --json ]] && json=1

    local path live
    path=$(rack::settings::path) || return $?
    live=$(rack::settings::__read_live "$path") || {
        rig::log::error "malformed settings file: $path"
        return "$RIG_EX_FAIL"
    }

    if ((json)); then
        jq -n --argjson schema "$(cat "$s")" --argjson live "$live" '
			$schema.settings | to_entries | map(
				.key as $k | {
					key: $k,
					value: (if ($live | has($k)) then $live[$k] else .value.default end)
				}
			) | from_entries
		'
        return 0
    fi

    local key value_json suffix
    while IFS= read -r key; do
        if jq -e --arg k "$key" 'has($k)' <<<"$live" >/dev/null; then
            value_json=$(jq -c --arg k "$key" '.[$k]' <<<"$live")
            suffix=""
        else
            value_json=$(jq -c --arg k "$key" '.settings[$k].default' "$s")
            suffix=" (default)"
        fi
        printf '%-24s %s%s\n' "$key" "$value_json" "$suffix"
    done < <(rack::settings::__keys)

    # Report settings present in the file but absent from the schema — might be
    # written by a newer shell than this schema describes.
    local unknown
    unknown=$(jq -r --argjson schema "$(cat "$s")" '
		keys[] as $k | select($schema.settings | has($k) | not) | $k
	' <<<"$live")
    [[ -z $unknown ]] || {
        printf '\nunknown (in file, not in schema):\n'
        while IFS= read -r key; do
            printf '  %-22s %s\n' "$key" "$(jq -c --arg k "$key" '.[$k]' <<<"$live")"
        done <<<"$unknown"
    }
}

rack::settings::get() {
    rack::settings::__require_schema || return $?
    local s key=${1-} json=0
    s=$(rack::settings::__schema)
    [[ -n $key && $key != --json ]] || {
        rig::log::error "usage: rack settings get <key> [--json]"
        return "$RIG_EX_USAGE"
    }
    [[ ${2-} == --json ]] && json=1

    rack::settings::__key_in_schema "$key" || {
        rig::log::error "unknown key '$key' (see: rack settings schema)"
        return "$RIG_EX_USAGE"
    }

    local path live value_json
    path=$(rack::settings::path) || return $?
    live=$(rack::settings::__read_live "$path") || {
        rig::log::error "malformed settings file: $path"
        return "$RIG_EX_FAIL"
    }

    if jq -e --arg k "$key" 'has($k)' <<<"$live" >/dev/null; then
        value_json=$(jq -c --arg k "$key" '.[$k]' <<<"$live")
    else
        value_json=$(jq -c --arg k "$key" '.settings[$k].default' "$s")
    fi

    if ((json)); then
        printf '%s\n' "$value_json"
    else
        jq -r 'if type == "string" then . else tostring end' <<<"$value_json"
    fi
}

rack::settings::__default() { rack::settings::list "$@"; }

rack::settings::__usage() {
    cat <<'EOF'
  rack settings list           every setting with its current value
  rack settings get <key>      one value, bare, to stdout
  rack settings schema         the schema, human-readable
  rack settings path           resolved path to the live settings file

Read-only: changing a setting is the shell's own job, and a write here would
be overwritten by the running shell's next autosave.

options
  --json    machine-readable (list, get, schema)

env
  RACK_SCHEMA     override the schema path (default: rack/schema.json)
  RACK_SETTINGS   override live-settings discovery
EOF
}
