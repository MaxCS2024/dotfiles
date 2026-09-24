# diff — has anything drifted from what is committed?
#
# Answers the question you actually have at 2am: is what I am running the same
# as what is in the repo, or did I edit something in place and forget?

rig::load log link check
rack::load manifest

RACK_MODULE_SUMMARY[diff]="drift between the repo and what is deployed"
RACK_MODULE_ACTIONS[diff]="run show"
RACK_MODULE_STATUS[diff]="ready"
RACK_MODULE_TIER[diff]="core"

# A correct symlink cannot have different content — the file is the file. So
# drift only ever means the link is wrong, or something real replaced it.
# When it is a real file, showing the actual diff is the useful part.
rack::diff::run() {
    local name source target reload state entries drift=0

    # Selected up front, not read through a process substitution, which
    # drops select's status: `rack diff tol` would log the unknown name and
    # then say everything matches. deploy.sh has the same note.
    entries=$(rack::manifest::select "$@") || return $?

    while IFS=$'\t' read -r name source target reload; do
        [[ -n $name ]] || continue
        state=$(rig::link::check "$source" "$target") || true

        case $state in
            ok) continue ;;

            absent)
                printf '  %-12s not deployed\n' "$name"
                drift=$((drift + 1))
                ;;

            stale)
                printf '  %-12s links elsewhere: %s\n' "$name" \
                    "$(rig::link::target "$target")"
                drift=$((drift + 1))
                ;;

            broken)
                printf '  %-12s dangling link\n' "$name"
                drift=$((drift + 1))
                ;;

            conflict)
                printf '  %-12s real file, not a link\n' "$name"
                if [[ -f $target && -f $source ]] && ! cmp -s -- "$target" "$source"; then
                    printf '               content differs from the repo\n'
                elif [[ -d $target ]]; then
                    printf '               a real directory is in the way\n'
                fi
                drift=$((drift + 1))
                ;;
        esac
    done <<<"$entries"

    if ((drift)); then
        rig::log::warn "$drift entr(ies) have drifted — rack deploy, or rack diff show <name>"
        return "$RIG_EX_FAIL"
    fi
    rig::log::success "everything matches the manifest"
}

# show <name> — the actual content diff, when there is one to show.
rack::diff::show() {
    local want=${1:-}
    [[ -n $want ]] || {
        rig::log::error "diff show: name an entry"
        return "$RIG_EX_USAGE"
    }

    local name source target reload
    IFS=$'\t' read -r name source target reload < <(rack::manifest::get "$want") || {
        rig::log::error "not in the manifest: $want"
        return "$RIG_EX_USAGE"
    }

    if [[ ! -e $target ]]; then
        rig::log::info "$name is not deployed"
        return 0
    fi
    if [[ -L $target ]]; then
        rig::log::info "$name is a link to $(rig::link::target "$target") — no content to diff"
        return 0
    fi

    if [[ -d $target && -d $source ]]; then
        diff -ru --color=auto -- "$source" "$target" || true
    elif [[ -f $target && -f $source ]]; then
        diff -u --color=auto -- "$source" "$target" || true
    else
        rig::log::warn "$name: repo and target are different kinds of thing"
    fi
}

rack::diff::__default() { rack::diff::run "$@"; }

rack::diff::__usage() {
    cat <<'EOF'
  rack diff                  everything
  rack diff hypr nvim        just these
  rack diff show hypr        the actual content diff, when it is a real file

A correct symlink cannot drift in content, so anything reported here means the
link is wrong or something real replaced it.
EOF
}
