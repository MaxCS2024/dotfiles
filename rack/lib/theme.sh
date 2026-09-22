# theme — the reason rack exists rather than a stow invocation.
#
# Deploying is a solved problem. Switching a theme is not: it means writing
# colours into several applications' configs and then telling the running
# instances to pick them up, and no general tool knows how to do that for
# your particular set of programs.
#
# The mechanism is deliberately dumb. A theme is a file of key = value. Any
# file ending in .in anywhere under the dotfiles is a template; {{key}} in it
# is replaced and the result written beside it without the .in. Nothing knows
# what a colour is, so adding an application means adding a template, not
# editing this module.

rig::load log path proc config
rack::load manifest reload

RACK_MODULE_SUMMARY[theme]="render templates for a theme, then reload"
RACK_MODULE_ACTIONS[theme]="set list current render vars templates"
RACK_MODULE_STATUS[theme]="ready"
RACK_MODULE_TIER[theme]="core"

rack::theme::__dir() {
    printf '%s\n' "${RACK_THEME_DIR:-$RACK_ROOT/themes}"
}

rack::theme::list() {
    local dir file
    dir=$(rack::theme::__dir)
    [[ -d $dir ]] || {
        rig::log::error "no themes directory at $dir"
        return "$RIG_EX_FAIL"
    }
    for file in "$dir"/*.conf; do
        [[ -f $file ]] || continue
        file=${file##*/}
        printf '%s\n' "${file%.conf}"
    done
}

rack::theme::current() {
    rig::config::get theme "${1:-}"
}

# Load a theme file into the associative array named by the caller. Same
# out-variable shape as rig::tmp, for the same subshell reason.
rack::theme::__load() {
    local name=$1 into=$2 file key value line
    file="$(rack::theme::__dir)/${name}.conf"

    [[ -r $file ]] || {
        rig::log::error "no such theme: $name (rack theme list)"
        return "$RIG_EX_USAGE"
    }

    while IFS= read -r line || [[ -n $line ]]; do
        # Whole-line comments only. A trailing # cannot be a comment here
        # because every colour value starts with one.
        [[ ${line} =~ ^[[:space:]]*# ]] && continue
        [[ -z ${line//[[:space:]]/} ]] && continue
        [[ $line == *=* ]] || continue

        key=${line%%=*}
        value=${line#*=}
        key=${key//[[:space:]]/}
        value=${value#"${value%%[![:space:]]*}"}
        value=${value%"${value##*[![:space:]]}"}
        value=${value#\"}
        value=${value%\"}

        printf -v "${into}[$key]" '%s' "$value"
    done <"$file"
}

rack::theme::vars() {
    local name=${1:-}
    [[ -n $name ]] || name=$(rack::theme::current)
    [[ -n $name ]] || {
        rig::log::error "vars: name a theme"
        return "$RIG_EX_USAGE"
    }

    local -A vars=()
    rack::theme::__load "$name" vars || return $?
    local key
    while read -r key; do
        printf '  %-16s %s\n' "$key" "${vars[$key]}"
    done < <(printf '%s\n' "${!vars[@]}" | sort)
}

rack::theme::templates() {
    local dotfiles
    dotfiles=$(rack::manifest::dotfiles)
    find "$dotfiles" -type f -name '*.in' -not -path '*/.git/*' 2>/dev/null | sort
}

# render [name] — substitute, but do not reload. Useful on its own when you
# are editing a template and want to see the result.
rack::theme::render() {
    local name=${1:-}
    [[ -n $name ]] || name=$(rack::theme::current)
    [[ -n $name ]] || {
        rig::log::error "render: name a theme"
        return "$RIG_EX_USAGE"
    }

    local -A vars=()
    rack::theme::__load "$name" vars || return $?
    ((${#vars[@]})) || {
        rig::log::error "theme $name defines nothing"
        return "$RIG_EX_FAIL"
    }

    local template output content key rendered=0 missing=0

    while IFS= read -r template; do
        [[ -n $template ]] || continue
        output=${template%.in}

        content=$(<"$template")
        for key in "${!vars[@]}"; do
            content=${content//\{\{$key\}\}/${vars[$key]}}
        done

        # A placeholder the theme does not define is almost always a typo in
        # one or the other, and silently writing {{accent}} into a config is
        # a confusing way to find out.
        if [[ $content == *'{{'*'}}'* ]]; then
            rig::log::warn "${template##*/}: unresolved placeholders remain"
            missing=$((missing + 1))
        fi

        if [[ ${RIG_DRY_RUN:-0} != 0 ]]; then
            printf '  would write %s\n' "${output/#$HOME/\~}"
            continue
        fi

        printf '%s\n' "$content" >"$output" || {
            rig::log::error "cannot write $output"
            return "$RIG_EX_FAIL"
        }
        printf '  %s\n' "${output/#$HOME/\~}"
        rendered=$((rendered + 1))
    done < <(rack::theme::templates)

    ((rendered || ${RIG_DRY_RUN:-0} != 0)) || rig::log::warn "no .in templates found"
    ((missing)) && return "$RIG_EX_FAIL"
    return 0
}

# Write the choice where rig can read it. One writer, many readers — this is
# the only place in the three tools that writes this file.
rack::theme::__record() {
    local name=$1 file tmp
    file=$(rig::config::path)

    [[ ${RIG_DRY_RUN:-0} != 0 ]] && {
        printf '  would record theme = %s in %s\n' "$name" "${file/#$HOME/\~}"
        return 0
    }

    mkdir -p -- "${file%/*}"
    tmp="${file}.new"
    {
        printf '# written by rack — edit through `rack theme`, not by hand\n'
        [[ -r $file ]] && grep -vE '^[[:space:]]*(theme[[:space:]]*=|# written by rack)' -- "$file" || true
        printf 'theme = %s\n' "$name"
    } >"$tmp"
    mv -- "$tmp" "$file"
}

# set <name> — the whole ritual, in the right order.
rack::theme::set() {
    local name=${1:-}
    shift || true
    [[ -n $name ]] || {
        rig::log::error "set: name a theme (rack theme list)"
        return "$RIG_EX_USAGE"
    }

    local -A probe=()
    rack::theme::__load "$name" probe || return $?

    rig::log::info "rendering $name"
    rack::theme::render "$name" || return $?

    rack::theme::__record "$name"

    rig::log::info "reloading"
    rack::reload::run "$@" || true

    rig::log::success "theme is now $name"
}

# `rack theme dark` — the form anyone would try first.
rack::theme::__default() {
    (($#)) || {
        rack::theme::current
        return 0
    }
    rack::theme::set "$@"
}

rack::theme::__usage() {
    cat <<'EOF'
  rack theme dark              render, record, reload
  rack theme list
  rack theme current
  rack theme vars dark         what the theme defines
  rack theme render dark       substitute without reloading
  rack theme templates         every .in file found

how it works
  themes/dark.conf     accent = #89b4fa
  hypr/colors.conf.in  col.active_border = rgb({{accent}})
  -> writes hypr/colors.conf, then runs the manifest's reload commands.

Adding an application means adding a template, not editing this module.
Rendered outputs are generated files — gitignore them, or commit them and
accept the churn.

env
  RACK_THEME_DIR   default: <rack repo>/themes
EOF
}
