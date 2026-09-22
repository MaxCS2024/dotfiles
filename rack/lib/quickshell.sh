# quickshell — the multi-config layout that one manifest line cannot express.
#
# Every config under quickshell/ is a sibling that has to land at
# ~/.config/quickshell/<name> for `qs -c <name>` to find it, and the manifest
# carries one line per config to do exactly that. So linking is `rack deploy`
# and drift is `rack diff`, the same as everything else — what is left here is
# the part that is genuinely quickshell-shaped: scaffolding a new experiment,
# and saying which configs exist and which are actually linked.
#
# Ported from `orbit quickshell` (a built-in of bin/orbit). Its link/unlink
# subcommands are gone rather than reimplemented: they were a bespoke stow
# invocation with a bespoke target, which is precisely what a manifest entry
# replaces. `doctor` is `rack diff`.

rig::load log check link
rack::load manifest

RACK_MODULE_SUMMARY[quickshell]="scaffold and list the shell's configs"
RACK_MODULE_ACTIONS[quickshell]="list new"
RACK_MODULE_STATUS[quickshell]="ready"
RACK_MODULE_TIER[quickshell]="general"

rack::quickshell::__dir() {
    local dotfiles
    dotfiles=$(rack::manifest::dotfiles) || return $?
    printf '%s/quickshell\n' "$dotfiles"
}

rack::quickshell::__target() {
    printf '%s/quickshell\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

rack::quickshell::list() {
    local dir target name link
    dir=$(rack::quickshell::__dir) || return $?
    target=$(rack::quickshell::__target)

    local found=0
    for name in "$dir"/*/; do
        [[ -d $name ]] || continue
        name=$(basename "$name")
        found=1
        link="$target/$name"
        if [[ -L $link && -e $link ]]; then
            printf '  %-16s linked%s\n' "$name" \
                "$([[ $name == main ]] && printf ' (daily driver)')"
        elif [[ -L $link ]]; then
            printf '  %-16s broken symlink -> %s\n' "$name" "$(readlink "$link")"
        else
            printf '  %-16s not linked (run: rack deploy quickshell/%s)\n' "$name" "$name"
        fi
    done
    ((found)) || printf '  no configs under %s\n' "$dir"
}

rack::quickshell::new() {
    local name=${1-}
    [[ -n $name ]] || {
        rig::log::error "usage: rack quickshell new <name>"
        return "$RIG_EX_USAGE"
    }

    local dir
    dir=$(rack::quickshell::__dir) || return $?
    local script="$dir/new-config.sh"
    [[ -x $script ]] || {
        rig::log::error "not executable: $script"
        return "$RIG_EX_FAIL"
    }

    "$script" "$name" || return $?

    # A new config is a new manifest line — deploy cannot link what the table
    # does not mention, and silently doing nothing is the confusing outcome.
    cat <<EOF

Add it to $(rack::manifest::path):

    quickshell/$name   ~/.config/quickshell/$name   -

then: rack deploy quickshell/$name && qs -c $name
EOF
}

rack::quickshell::__default() { rack::quickshell::list "$@"; }

rack::quickshell::__usage() {
    cat <<'EOF'
  rack quickshell list        which configs exist, and which are linked
  rack quickshell new <name>  scaffold a new experiment config

Linking is `rack deploy` and drift is `rack diff`: each config is a manifest
entry (quickshell/<name> -> ~/.config/quickshell/<name>), not a special case.
EOF
}
