# sync — pull the repo, then make the machine match it again.
#
# Refuses to run with a dirty tree. A pull that has to merge, or that lands on
# top of uncommitted edits, is a conflict to resolve by hand, not something a
# convenience command should attempt while it also holds the deploy step.
#
# Ported from bin/orbit-sync (a built-in of bin/orbit). Two differences worth
# knowing: the relink is `rack deploy` rather than two stow invocations, and
# quickshell comes along with it because it is a manifest entry now rather than
# a special case in the script.

rig::load log check proc
rack::load manifest deploy reload

RACK_MODULE_SUMMARY[sync]="git pull, then deploy what changed"
RACK_MODULE_ACTIONS[sync]="run"
RACK_MODULE_STATUS[sync]="ready"
RACK_MODULE_TIER[sync]="general"

# rack does not source relay — the dependency runs one way only. Invoking it as
# a command is the same weak coupling the manifest's reload column uses, and it
# is what gets a themed, glyphed toast instead of the plain freedesktop one.
# Without relay, rig's own notify says the same thing, or logs it.
rack::sync::__notify() {
    local summary=$1 body=$2 glyph=${3:-}
    if rig::check::has relay; then
        relay notif send "$summary" "$body" ${glyph:+-g "$glyph"} || true
    else
        rig::notify::send "$summary" "$body" || true
    fi
}

rack::sync::run() {
    local dotfiles
    dotfiles=$(rack::manifest::dotfiles) || return $?

    [[ -d $dotfiles/.git ]] || {
        rig::log::error "$dotfiles is not a git repository"
        return "$RIG_EX_FAIL"
    }
    rig::check::require git || return "$RIG_EX_NODEP"

    [[ -z $(git -C "$dotfiles" status --porcelain) ]] || {
        rig::log::error "uncommitted changes in $dotfiles — commit or stash before syncing"
        return "$RIG_EX_FAIL"
    }

    printf 'pulling %s...\n' "$dotfiles"
    git -C "$dotfiles" pull --ff-only || {
        rig::log::error "pull failed — nothing was deployed"
        return "$RIG_EX_FAIL"
    }

    printf '\ndeploying...\n'
    rack::deploy::run "$@" || return $?

    printf '\nreloading...\n'
    rack::reload::run || true

    rig::log::success "synced"
    rack::sync::__notify "Dotfiles synced" "pulled and deployed $dotfiles" 󰓦
}

rack::sync::__default() { rack::sync::run "$@"; }

rack::sync::__usage() {
    cat <<'EOF'
  rack sync         git pull --ff-only, then deploy and reload

Refuses to run with uncommitted changes: a pull that has to merge is a
conflict to resolve by hand, not something to attempt underneath a deploy.

Options are passed through to `rack deploy`.

env
  RIG_DRY_RUN=1   deploy and reload print what they would do
EOF
}
