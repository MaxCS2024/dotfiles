# deploy — make reality match the manifest.
#
# Idempotent, so running it after a git pull on a second machine is the whole
# setup process. Policy lives here; the symlinking itself is rig::link.

rig::load log link proc
rack::load manifest

RACK_MODULE_SUMMARY[deploy]="link everything in the manifest into place"
RACK_MODULE_ACTIONS[deploy]="run status remove adopt"
RACK_MODULE_STATUS[deploy]="ready"
RACK_MODULE_TIER[deploy]="core"

# run [--force] [--adopt] [name...]
rack::deploy::run() {
    local force=0 adopt=0
    local -a names=()

    while (($#)); do
        case $1 in
            --force) force=1 ;;
            --adopt) adopt=1 ;;
            --) ;;
            -*)
                rig::log::error "deploy: unknown option: $1"
                return "$RIG_EX_USAGE"
                ;;
            *) names+=("$1") ;;
        esac
        shift
    done

    local name source target reload state changed=0 failed=0

    while IFS=$'\t' read -r name source target reload; do
        state=$(rig::link::check "$source" "$target") || true

        case $state in
            ok)
                printf '  %-12s ok\n' "$name"
                continue
                ;;

            conflict)
                # Something real is in the way. Adopting moves it into the
                # repo and links back, which is the sane first-run move on a
                # machine that had configuration before it had a repo.
                if ((adopt)); then
                    if [[ -e $source ]]; then
                        rig::log::error "$name: cannot adopt, $source already exists in the repo"
                        failed=$((failed + 1))
                        continue
                    fi
                    if [[ ${RIG_DRY_RUN:-0} != 0 ]]; then
                        printf '  %-12s would adopt %s\n' "$name" "${target/#$HOME/\~}"
                        continue
                    fi
                    rig::link::adopt "$target" "$source" || {
                        failed=$((failed + 1))
                        continue
                    }
                    printf '  %-12s adopted\n' "$name"
                    changed=$((changed + 1))
                    continue
                fi
                if ((!force)); then
                    rig::log::error "$name: ${target/#$HOME/\~} exists and is not ours (--adopt or --force)"
                    failed=$((failed + 1))
                    continue
                fi
                ;;
        esac

        if [[ ${RIG_DRY_RUN:-0} != 0 ]]; then
            printf '  %-12s would link (%s)\n' "$name" "$state"
            continue
        fi

        local -a args=("$source" "$target")
        ((force)) && args+=(--force)
        if rig::link::make "${args[@]}"; then
            printf '  %-12s linked (%s)\n' "$name" "$state"
            changed=$((changed + 1))
        else
            failed=$((failed + 1))
        fi
    done < <(rack::manifest::select "${names[@]}")

    ((failed)) && {
        rig::log::error "$failed entr(ies) could not be deployed"
        return "$RIG_EX_FAIL"
    }
    ((changed)) || rig::log::info "nothing to do"
    return 0
}

# What deploy would say, without doing anything.
rack::deploy::status() {
    local name source target reload state
    while IFS=$'\t' read -r name source target reload; do
        state=$(rig::link::check "$source" "$target") || true
        printf '  %-12s %-9s %s\n' "$name" "$state" "${target/#$HOME/\~}"
    done < <(rack::manifest::select "$@")
}

# The one you need the moment you drop an app from the manifest.
rack::deploy::remove() {
    local name source target reload dotfiles removed=0
    dotfiles=$(rack::manifest::dotfiles)

    while IFS=$'\t' read -r name source target reload; do
        if ! rig::link::points_into "$target" "$dotfiles"; then
            [[ -e $target ]] && printf '  %-12s left alone (not ours)\n' "$name"
            continue
        fi
        if [[ ${RIG_DRY_RUN:-0} != 0 ]]; then
            printf '  %-12s would unlink\n' "$name"
            continue
        fi
        rig::link::remove "$target" --into "$dotfiles" &&
            printf '  %-12s unlinked\n' "$name"
        removed=$((removed + 1))
    done < <(rack::manifest::select "$@")

    ((removed)) || rig::log::info "nothing to remove"
}

# adopt <name...> — explicit form of the same move deploy --adopt makes.
rack::deploy::adopt() {
    (($#)) || {
        rig::log::error "adopt: name which entries to adopt"
        return "$RIG_EX_USAGE"
    }
    rack::deploy::run --adopt "$@"
}

rack::deploy::__default() { rack::deploy::run "$@"; }

rack::deploy::__usage() {
    cat <<'EOF'
  rack deploy                    everything in the manifest
  rack deploy hypr nvim          just these
  rack deploy --adopt            move what is already there into the repo first
  rack deploy --force            replace real files (they are gone)
  rack deploy status             what it would do
  rack deploy remove nvim        unlink, but only links pointing into the repo

Idempotent: already-correct entries are left alone, so running this after a
git pull is the whole setup step. Honours RIG_DRY_RUN=1.
EOF
}
