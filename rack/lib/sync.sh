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
rack::load manifest deploy reload ui

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

# One step's heading: a numbered rule on a terminal, the old line plain.
rack::sync::__step() {
    if rack::ui::rich; then
        rack::ui::rule "$1/3" "$2"
    else
        (($1 > 1)) && printf '\n'
        printf '%s\n' "$3"
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

    # Plain, the three steps are the one-line announcements they always were;
    # on a terminal, numbered rules, with deploy and reload drawing their own
    # rows under them (the header is printed once, here).
    local started=$SECONDS before after
    before=$(git -C "$dotfiles" rev-parse --short HEAD 2>/dev/null || true)
    rack::ui::header "Sync" "${dotfiles/#$HOME/\~} · $(git -C "$dotfiles" rev-parse --abbrev-ref HEAD 2>/dev/null) at $before"

    rack::sync::__step 1 "Pull" "pulling $dotfiles..."
    # On a terminal the row under this says what came in, so git's own
    # diffstat is left out; plain, git talks as it always did.
    local -a quiet=()
    rack::ui::rich && quiet=(--quiet)
    git -C "$dotfiles" pull --ff-only "${quiet[@]}" || {
        rack::ui::finish bad "pull failed — nothing was deployed"
        return "$RIG_EX_FAIL"
    }
    after=$(git -C "$dotfiles" rev-parse --short HEAD 2>/dev/null || true)
    if rack::ui::rich; then
        if [[ $before == "$after" ]]; then
            rack::ui::row skip "git" "already up to date"
        else
            rack::ui::row ok "git" "$before → $after" \
                "$(rack::ui::plural "$(git -C "$dotfiles" rev-list --count "$before..$after")" commit)"
        fi
    fi

    local RACK_UI_NESTED=1
    rack::sync::__step 2 "Deploy" "deploying..."
    rack::deploy::run "$@" || return $?

    rack::sync::__step 3 "Reload" "reloading..."
    rack::reload::run || true
    RACK_UI_NESTED=0

    if rack::ui::rich; then
        rack::ui::rule "" "Done"
        rack::ui::finish ok "Synced" "in $(rack::ui::duration $((SECONDS - started)))"
    else
        rig::log::success "synced"
    fi
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
