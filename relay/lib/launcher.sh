# launcher — app-launcher entries for web apps and terminal (TUI) apps.
#
# A web app is a page that opens as a window of its own, in the default
# browser's app mode; a TUI is a command that opens in the default
# terminal. Neither ships a desktop entry, so neither shows up in the app
# launcher until something writes one. This is that something, and the
# Conf menu's Install › Web apps and Install › TUI rows call it.
#
# One file per launcher, relay-launcher-<slug>.desktop in the user's
# applications directory. The file is the whole record: its X-Relay-Kind
# and X-Relay-Target keys say what it opens, so `list` reads the files
# and there is no second store to fall out of step with them.
#
# Exec is `relay launcher run <slug>`, not the browser or the command
# itself, for two reasons:
#
#   * the default browser and terminal are looked up when the launcher
#     is opened, not baked in when it was made, so changing the default
#     under Apps › Defaults carries every launcher with it;
#   * a slug is [a-z0-9-] and needs no quoting, where a URL or a command
#     line in Exec needs the desktop spec's two layers of escaping, which
#     not every launcher reads the same way.

rig::load log check

RELAY_MODULE_SUMMARY[launcher]="launcher entries for web apps and terminal apps"
RELAY_MODULE_ACTIONS[launcher]="web tui list remove run"
RELAY_MODULE_STATUS[launcher]="ready"
RELAY_MODULE_TIER[launcher]="general"

relay::launcher::__dir() {
    printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
}

relay::launcher::__icon_dir() {
    printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/icons/relay-launcher"
}

# "Proton Mail" -> proton-mail. Lowercase ASCII letters and digits, runs of
# anything else as one dash, none at either end.
relay::launcher::__slug() {
    local slug
    slug=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
    printf '%s\n' "$slug"
}

relay::launcher::__file() {
    printf '%s/relay-launcher-%s.desktop\n' "$(relay::launcher::__dir)" "$1"
}

# A desktop entry's string values: a backslash is written \\, and a line
# break can't be written at all, so control characters are refused before
# anything reaches here.
relay::launcher::__escape() {
    local value=${1//\\/\\\\}
    printf '%s\n' "$value"
}

relay::launcher::__unescape() {
    local value=${1//\\\\/$'\x01'}
    value=${value//$'\x01'/\\}
    printf '%s\n' "$value"
}

# One key's value from a desktop file, first match, unescaped.
relay::launcher::__key() {
    local file=$1 key=$2 line
    while IFS= read -r line; do
        [[ $line == "$key="* ]] || continue
        relay::launcher::__unescape "${line#"$key="}"
        return 0
    done <"$file"
    return 1
}

# The name and the target both end up on one line of the file.
relay::launcher::__plain() {
    local what=$1 value=$2
    [[ -n $value ]] || {
        rig::log::error "the $what is empty"
        return "$RIG_EX_USAGE"
    }
    [[ $value != *[[:cntrl:]]* ]] || {
        rig::log::error "the $what has a line break or control character in it"
        return "$RIG_EX_USAGE"
    }
}

# What to put in Exec: this relay by its full path, since a launcher can be
# started from a session whose PATH lacks ~/.local/bin.
relay::launcher::__self() {
    local self
    self=$(command -v relay 2>/dev/null) || self=$HOME/.local/bin/relay
    printf '%s\n' "$self"
}

# The site's own icon, from the site: apple-touch-icon.png is a square
# PNG of a useful size on most sites, favicon.ico the fallback. Prints the
# saved path, or nothing when neither is an image (a login page served in
# its place, say), and the entry takes a generic icon instead.
# RELAY_LAUNCHER_FETCH=0 skips the network, which the tests rely on.
relay::launcher::__fetch_icon() {
    local url=$1 slug=$2 origin dir tmp candidate mime ext
    [[ ${RELAY_LAUNCHER_FETCH:-1} != 0 ]] || return 0
    rig::check::has curl || return 0
    rig::check::has file || return 0

    [[ $url =~ ^(https?://[^/?#]+) ]] || return 0
    origin=${BASH_REMATCH[1]}
    dir=$(relay::launcher::__icon_dir)
    mkdir -p "$dir" || return 0
    tmp="$dir/.$slug.part"

    for candidate in apple-touch-icon.png favicon.ico; do
        curl -fsSL --max-time 5 --proto '=https,http' -o "$tmp" "$origin/$candidate" 2>/dev/null || continue
        mime=$(file --brief --mime-type "$tmp" 2>/dev/null) || continue
        case $mime in
            image/png) ext=png ;;
            image/vnd.microsoft.icon | image/x-icon) ext=ico ;;
            image/svg+xml) ext=svg ;;
            *) continue ;;
        esac
        rm -f "$dir/$slug".*
        mv -f "$tmp" "$dir/$slug.$ext" || break
        printf '%s\n' "$dir/$slug.$ext"
        return 0
    done
    rm -f "$tmp"
    return 0
}

relay::launcher::__write() {
    local kind=$1 name=$2 target=$3 icon=$4 slug file dir tmp categories
    slug=$(relay::launcher::__slug "$name")
    [[ -n $slug ]] || {
        rig::log::error "'$name' has no letters or digits to name the file after"
        return "$RIG_EX_USAGE"
    }
    case $kind in
        web) categories="Network;WebBrowser;" ;;
        tui) categories="Utility;ConsoleOnly;" ;;
    esac

    dir=$(relay::launcher::__dir)
    mkdir -p "$dir" || return "$RIG_EX_FAIL"
    file=$(relay::launcher::__file "$slug")
    tmp="$file.part"

    # Written beside the real file and moved over it, so a launcher that
    # rescans mid-write never reads half an entry.
    {
        printf '[Desktop Entry]\n'
        printf 'Type=Application\n'
        printf 'Name=%s\n' "$(relay::launcher::__escape "$name")"
        printf 'Comment=%s\n' "$(relay::launcher::__escape "$target")"
        printf 'Exec=%s launcher run %s\n' "$(relay::launcher::__self)" "$slug"
        printf 'Icon=%s\n' "$icon"
        printf 'Terminal=false\n'
        printf 'Categories=%s\n' "$categories"
        printf 'X-Relay-Kind=%s\n' "$kind"
        printf 'X-Relay-Target=%s\n' "$(relay::launcher::__escape "$target")"
    } >"$tmp" && mv -f "$tmp" "$file" || {
        rm -f "$tmp"
        rig::log::error "couldn't write $file"
        return "$RIG_EX_FAIL"
    }
    printf '%s\n' "$file"
}

# relay launcher web <name> <url>
relay::launcher::web() {
    (($# == 2)) || {
        rig::log::error "usage: relay launcher web <name> <url>"
        return "$RIG_EX_USAGE"
    }
    local name=$1 url=$2 slug icon
    relay::launcher::__plain name "$name" || return $?
    relay::launcher::__plain URL "$url" || return $?
    [[ $url =~ ^https?://[^[:space:]/]+ && $url != *[[:space:]]* ]] || {
        rig::log::error "'$url' is not an http:// or https:// address"
        return "$RIG_EX_USAGE"
    }

    slug=$(relay::launcher::__slug "$name")
    icon=""
    [[ -z $slug ]] || icon=$(relay::launcher::__fetch_icon "$url" "$slug")
    relay::launcher::__write web "$name" "$url" "${icon:-web-browser}"
}

# relay launcher tui <name> [--] <command...>
relay::launcher::tui() {
    (($# >= 2)) || {
        rig::log::error "usage: relay launcher tui <name> <command...>"
        return "$RIG_EX_USAGE"
    }
    local name=$1
    shift
    [[ ${1-} != -- ]] || shift
    # Joined the way `relay default exec terminal -- ...` joins them: one
    # sh command line, so `-- ncdu /` and `-- 'ncdu /'` are the same.
    local command="$*"
    relay::launcher::__plain name "$name" || return $?
    relay::launcher::__plain command "$command" || return $?
    relay::launcher::__write tui "$name" "$command" utilities-terminal
}

# One tab-separated line per launcher: kind, slug, name, target. Tabs
# can't be in a name or a target (control characters are refused), so the
# columns are unambiguous.
relay::launcher::list() {
    (($# == 0)) || {
        rig::log::error "unexpected argument '$1' (see: relay help launcher)"
        return "$RIG_EX_USAGE"
    }
    local dir file slug kind name target
    dir=$(relay::launcher::__dir)
    [[ -d $dir ]] || return 0
    shopt -s nullglob
    for file in "$dir"/relay-launcher-*.desktop; do
        slug=${file##*/relay-launcher-}
        slug=${slug%.desktop}
        kind=$(relay::launcher::__key "$file" X-Relay-Kind) || continue
        name=$(relay::launcher::__key "$file" Name) || name=$slug
        target=$(relay::launcher::__key "$file" X-Relay-Target) || target=""
        printf '%s\t%s\t%s\t%s\n' "$kind" "$slug" "$name" "$target"
    done
    shopt -u nullglob
}

# relay launcher remove <name|slug>
relay::launcher::remove() {
    (($# == 1)) || {
        rig::log::error "usage: relay launcher remove <name>"
        return "$RIG_EX_USAGE"
    }
    local slug file
    slug=$(relay::launcher::__slug "$1")
    file=$(relay::launcher::__file "$slug")
    [[ -n $slug && -f $file ]] || {
        rig::log::error "no launcher called '$1' (see: relay launcher list)"
        return "$RIG_EX_FAIL"
    }
    rm -f "$file" "$(relay::launcher::__icon_dir)/$slug".* || return "$RIG_EX_FAIL"
    printf 'removed %s\n' "$slug"
}

# What Exec calls: open the target in whatever the default is right now.
relay::launcher::run() {
    (($# == 1)) || {
        rig::log::error "usage: relay launcher run <slug>"
        return "$RIG_EX_USAGE"
    }
    local file kind name target
    file=$(relay::launcher::__file "$(relay::launcher::__slug "$1")")
    [[ -f $file ]] || {
        rig::log::error "no launcher called '$1' (see: relay launcher list)"
        return "$RIG_EX_FAIL"
    }
    kind=$(relay::launcher::__key "$file" X-Relay-Kind) || kind=""
    name=$(relay::launcher::__key "$file" Name) || name=$1
    target=$(relay::launcher::__key "$file" X-Relay-Target) || target=""
    [[ -n $target ]] || {
        rig::log::error "$file says nothing to open (no X-Relay-Target)"
        return "$RIG_EX_FAIL"
    }

    relay::load default
    case $kind in
        web) relay::default::exec browser --app "$target" ;;
        tui) relay::default::exec terminal --title "$name" -- "$target" ;;
        *)
            rig::log::error "$file is of a kind this doesn't know: '$kind'"
            return "$RIG_EX_FAIL"
            ;;
    esac
}

relay::launcher::__usage() {
    cat <<'EOF'
  relay launcher web <name> <url>
  relay launcher tui <name> <command...>
  relay launcher list
  relay launcher remove <name>
  relay launcher run <name>

web makes a launcher entry that opens <url> as a window of its own, in the
default browser's app mode (a tab, when the browser has no app mode). It
fetches the site's icon if it can.

tui makes one that runs <command> in the default terminal.

Both write ~/.local/share/applications/relay-launcher-<name>.desktop, with
the name lowercased and dashed. The same name again replaces the entry.
The default browser and terminal are looked up each time a launcher opens.

list prints kind, name, label and target, one launcher per line, tab
separated. run is what the entries themselves call.

examples
  relay launcher web "Proton Mail" https://mail.proton.me/
  relay launcher tui Lazygit lazygit
  relay launcher remove "Proton Mail"
EOF
}
