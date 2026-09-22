# bar — status output in the shape Waybar expects.
#
# Hand-building this JSON in every module is how you end up with a bar that
# breaks on an apostrophe in a song title. One escaper, used everywhere.

RELAY_MODULE_SUMMARY[bar]="Waybar JSON output, escaped properly"
RELAY_MODULE_ACTIONS[bar]="emit error hidden escape"
RELAY_MODULE_STATUS[bar]="ready"
RELAY_MODULE_TIER[bar]="core"

# Backslash first, or it re-escapes everything that follows. Exotic control
# characters are dropped rather than encoded: they have no business in a bar
# label, and \u escaping them in bash is more code than the case deserves.
relay::bar::escape() {
    local s=${1:-}
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    s=${s//$'\b'/\\b}
    s=${s//$'\f'/\\f}
    printf '%s' "$s" | LC_ALL=C tr -d '\000-\010\013\016-\037\177'
}

# emit [--text S] [--tooltip S] [--class S] [--alt S] [--percentage N]
# Order of keys is fixed so the output diffs cleanly when you are debugging.
relay::bar::emit() {
    local text="" tooltip="" class="" alt="" percentage=""

    while (($#)); do
        case $1 in
            -t | --text)
                text=${2:-}
                shift 2
                ;;
            --tooltip)
                tooltip=${2:-}
                shift 2
                ;;
            -c | --class)
                class=${2:-}
                shift 2
                ;;
            --alt)
                alt=${2:-}
                shift 2
                ;;
            -p | --percentage)
                percentage=${2:-}
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                rig::log::error "bar emit: unknown option: $1"
                return "$RIG_EX_USAGE"
                ;;
        esac
    done

    local -a parts=()
    parts+=("\"text\":\"$(relay::bar::escape "$text")\"")
    [[ -n $alt ]] && parts+=("\"alt\":\"$(relay::bar::escape "$alt")\"")
    [[ -n $tooltip ]] && parts+=("\"tooltip\":\"$(relay::bar::escape "$tooltip")\"")
    [[ -n $class ]] && parts+=("\"class\":\"$(relay::bar::escape "$class")\"")

    if [[ -n $percentage ]]; then
        if [[ $percentage =~ ^-?[0-9]+$ ]]; then
            parts+=("\"percentage\":$percentage")
        else
            rig::log::warn "bar emit: percentage is not a number: $percentage"
        fi
    fi

    local IFS=,
    printf '{%s}\n' "${parts[*]}"
}

relay::bar::error() {
    relay::bar::emit --text "!" --tooltip "${1:-error}" --class error
}

# Waybar hides a module whose output is an empty object.
relay::bar::hidden() { printf '{}\n'; }

relay::bar::__usage() {
    cat <<'EOF'
  relay bar emit --text "42%" --class warning --percentage 42
  relay bar emit --text "$title" --tooltip "$artist"     quotes are safe
  relay bar error "mount failed"
  relay bar hidden                                       waybar hides the module

In waybar: "exec": "relay volume status", "return-type": "json"
EOF
}
