# link — idempotent symlinks, and nothing else.
#
# The mechanism only. What gets linked where is policy, and policy belongs to
# whatever is doing the deploying — not in a general library.

rig::load log

RIG_MODULE_SUMMARY[link]="idempotent symlinks and their status"
RIG_MODULE_ACTIONS[link]="make check remove adopt target points_into"
RIG_MODULE_STATUS[link]="ready"
RIG_MODULE_TIER[link]="core"

# Where a link actually goes, symlinks resolved. Empty for anything else.
rig::link::target() {
    local path=${1:-}
    [[ -L $path ]] || return 1
    readlink -f -- "$path" 2>/dev/null
}

# Is this path a link into that directory? The predicate every deploy tool
# needs before it dares replace something.
rig::link::points_into() {
    local path=${1:-} dir=${2:-} target
    target=$(rig::link::target "$path") || return 1
    dir=$(readlink -f -- "$dir" 2>/dev/null) || return 1
    [[ $target == "$dir" || $target == "$dir"/* ]]
}

# check <src> <dst> — prints one word and returns 0 only when it is already
# right, so callers can branch on the word or just on the status.
#
#   ok        a link from dst to src, as asked
#   absent    nothing there
#   stale     a link, but pointing somewhere else
#   broken    a link to nothing
#   conflict  a real file or directory
rig::link::check() {
    local src=${1:-} dst=${2:-} resolved

    if [[ ! -e $dst && ! -L $dst ]]; then
        printf 'absent\n'
        return 1
    fi

    if [[ -L $dst ]]; then
        resolved=$(readlink -f -- "$dst" 2>/dev/null)
        if [[ -z $resolved || ! -e $resolved ]]; then
            printf 'broken\n'
            return 1
        fi
        if [[ $resolved == "$(readlink -f -- "$src" 2>/dev/null)" ]]; then
            printf 'ok\n'
            return 0
        fi
        printf 'stale\n'
        return 1
    fi

    printf 'conflict\n'
    return 1
}

# make <src> <dst> [--force]
# Already correct is success and changes nothing. A real file at dst is
# refused: --force is the caller saying it accepts the loss.
rig::link::make() {
    local src="" dst="" force=0

    while (($#)); do
        case $1 in
            --force) force=1 ;;
            *)
                if [[ -z $src ]]; then
                    src=$1
                elif [[ -z $dst ]]; then
                    dst=$1
                else
                    rig::log::error "link make: too many arguments"
                    return "${RIG_EX_USAGE:-2}"
                fi
                ;;
        esac
        shift
    done

    [[ -n $src && -n $dst ]] || {
        rig::log::error "link make: need a source and a destination"
        return "${RIG_EX_USAGE:-2}"
    }
    [[ -e $src ]] || {
        rig::log::error "link make: no such source: $src"
        return "${RIG_EX_FAIL:-1}"
    }

    local state
    state=$(rig::link::check "$src" "$dst") && return 0

    case $state in
        absent) ;;
        stale | broken) rm -f -- "$dst" ;;
        conflict)
            if ((force)); then
                rm -rf -- "$dst"
            else
                rig::log::error "link make: $dst exists and is not a link"
                return "${RIG_EX_FAIL:-1}"
            fi
            ;;
    esac

    mkdir -p -- "${dst%/*}" 2>/dev/null
    ln -s -- "$(readlink -f -- "$src")" "$dst"
}

# remove <dst> [--into DIR]
# With --into, removes only a link that points inside DIR — the guard that
# stops an uninstall taking something it did not create.
rig::link::remove() {
    local dst=${1:-} into=""
    shift || true
    while (($#)); do
        case $1 in
            --into)
                into=${2:-}
                shift 2
                ;;
            *) shift ;;
        esac
    done

    [[ -L $dst ]] || return 0
    if [[ -n $into ]] && ! rig::link::points_into "$dst" "$into"; then
        rig::log::warn "link remove: $dst does not point into $into; leaving it"
        return "${RIG_EX_FAIL:-1}"
    fi
    rm -f -- "$dst"
}

# adopt <existing> <repo-path>
# Move a real file into the repo and link it back — the first-run move for a
# machine that already had configuration before you had a repo.
rig::link::adopt() {
    local existing=${1:-} dest=${2:-}

    [[ -n $existing && -n $dest ]] || {
        rig::log::error "link adopt: need an existing path and a destination"
        return "${RIG_EX_USAGE:-2}"
    }
    [[ -e $existing ]] || {
        rig::log::error "link adopt: no such path: $existing"
        return "${RIG_EX_FAIL:-1}"
    }
    [[ -L $existing ]] && {
        rig::log::error "link adopt: $existing is already a link"
        return "${RIG_EX_FAIL:-1}"
    }
    [[ -e $dest ]] && {
        rig::log::error "link adopt: $dest already exists in the repo"
        return "${RIG_EX_FAIL:-1}"
    }

    mkdir -p -- "${dest%/*}"
    mv -- "$existing" "$dest" || return "${RIG_EX_FAIL:-1}"
    rig::link::make "$dest" "$existing"
}

rig::link::__usage() {
    cat <<'EOF'
  rig link make ~/dots/hypr ~/.config/hypr    idempotent; refuses real files
  rig link check ~/dots/hypr ~/.config/hypr   ok|absent|stale|broken|conflict
  rig link remove ~/.config/hypr --into ~/dots
  rig link adopt ~/.zshrc ~/dots/zsh/.zshrc   move into the repo, link back

Mechanism only. Deciding what to link where is policy — that lives in rack.
EOF
}
