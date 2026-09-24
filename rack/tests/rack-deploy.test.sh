#!/usr/bin/env bash
# tests for rack's deploy module
#
# Same shape as relay's tests: plain bash, no framework, one function per
# test. What is under test moves real files around, so each test gets a
# throwaway machine of its own:
#
#   - HOME is a fresh directory, so every target (~/.config/..., ~/.zshenv)
#     and the backups under ~/.local/state/rack land inside it.
#   - The dotfiles are a fresh tree with its own rack/manifest.conf, named
#     by RACK_MANIFEST. Sources resolve against the directory above it, as
#     they do in the real repo.
#
# Everything goes through the `rack deploy` command, which is the interface;
# the assertions are on what ends up on disk, what it prints and how it
# exits.
#
#   ./tests/rack-deploy.test.sh          # all tests
#   ./tests/rack-deploy.test.sh force    # only tests whose name matches
set -uo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
RACK="$ROOT/rack"

FILTER=${1-}
PASS=0
FAIL=0
FAILURES=()

ORIG_HOME=$HOME
ORIG_TMPDIR=${TMPDIR:-/tmp}

# ---- harness -----------------------------------------------------------------

setup() {
	# Stop dead if this fails: every path below is "$TMP/...", and an empty
	# $TMP would make them real directories at the root of the machine.
	TMP=$(TMPDIR=$ORIG_TMPDIR mktemp -d) && [[ -d $TMP && $TMP == "$ORIG_TMPDIR"/* ]] || {
		printf 'harness error: cannot make a temp directory\n' >&2
		exit 1
	}
	DOTS="$TMP/dots"
	mkdir -p "$TMP/home" "$DOTS/rack" "$TMP/runtime"

	export HOME="$TMP/home"
	export RACK_MANIFEST="$DOTS/rack/manifest.conf"
	export XDG_RUNTIME_DIR="$TMP/runtime"
	export RIG_COLOR=never RIG_LOG_JOURNAL=never
	unset RACK_DOTFILES RIG_DRY_RUN XDG_STATE_HOME XDG_CONFIG_HOME
	: >"$RACK_MANIFEST"
}

teardown() {
	export HOME="$ORIG_HOME"
	[[ -n ${TMP:-} && -d $TMP ]] && rm -rf "$TMP"
	return 0
}

# entry <name> <target> — a manifest line, and the repo copy it links to.
entry() {
	printf '%s  %s  -\n' "$1" "$2" >>"$RACK_MANIFEST"
}

# app <name> [file] — the repo's copy of an app's config: a directory with
# one file in it, or a single file when the name has a slash in it.
app() {
	if [[ $1 == */* ]]; then
		mkdir -p "$DOTS/${1%/*}"
		printf 'repo %s\n' "$1" >"$DOTS/$1"
	else
		mkdir -p "$DOTS/$1"
		printf 'repo %s\n' "$1" >"$DOTS/$1/${2:-config}"
	fi
}

run() {
	OUT=$("$RACK" deploy "$@" 2>"$TMP/err")
	STATUS=$?
	ERR=$(cat "$TMP/err")
	return 0
}

backups() { find "$HOME/.local/state/rack/backups" -mindepth 1 -maxdepth 1 2>/dev/null; }

fail() {
	FAIL=$((FAIL + 1))
	FAILURES+=("$CURRENT: $1")
	printf '  \033[31mFAIL\033[0m %s\n        %s\n' "$CURRENT" "$1"
}

ok() {
	PASS=$((PASS + 1))
	printf '  \033[32mok\033[0m   %s\n' "$CURRENT"
}

assert_eq() {
	[[ $2 == "$3" ]] || {
		fail "$1: expected [$3], got [$2]"
		return 1
	}
}

assert_has() {
	[[ $2 == *"$3"* ]] || {
		fail "$1: expected to contain [$3], got [$2]"
		return 1
	}
}

# assert_linked <target> <repo path> — a link, to exactly that.
assert_linked() {
	[[ -L $1 ]] || {
		fail "$1 is not a link"
		return 1
	}
	assert_eq "$1 points to" "$(readlink -f "$1")" "$(readlink -f "$2")"
}

it() { CURRENT=$1; }

# ---- linking -----------------------------------------------------------------

test_absent_is_linked() {
	it "a target that isn't there is linked"
	app hypr
	entry hypr "~/.config/hypr"
	run
	assert_eq "status" "$STATUS" 0 || return
	assert_linked "$HOME/.config/hypr" "$DOTS/hypr" || return
	assert_has "said" "$OUT" "linked (absent)" || return
	ok
}

test_second_run_changes_nothing() {
	it "deploy is idempotent: a second run is all ok"
	app hypr
	entry hypr "~/.config/hypr"
	run
	run
	assert_eq "status" "$STATUS" 0 || return
	assert_has "said" "$OUT" "ok" || return
	assert_has "said" "$ERR" "nothing to do" || return
	ok
}

test_stale_link_is_replaced() {
	it "a link pointing somewhere else is replaced"
	app hypr
	entry hypr "~/.config/hypr"
	mkdir -p "$TMP/elsewhere" "$HOME/.config"
	ln -s "$TMP/elsewhere" "$HOME/.config/hypr"
	run
	assert_eq "status" "$STATUS" 0 || return
	assert_linked "$HOME/.config/hypr" "$DOTS/hypr" || return
	assert_has "said" "$OUT" "linked (stale)" || return
	[[ -d $TMP/elsewhere ]] || { fail "removed what the old link pointed at"; return; }
	ok
}

test_broken_link_is_replaced() {
	it "a link to nothing is replaced"
	app hypr
	entry hypr "~/.config/hypr"
	mkdir -p "$HOME/.config"
	ln -s "$TMP/gone" "$HOME/.config/hypr"
	run
	assert_linked "$HOME/.config/hypr" "$DOTS/hypr" || return
	assert_has "said" "$OUT" "linked (broken)" || return
	ok
}

test_single_file_target() {
	it "a single file lands where its target says, even at the top of HOME"
	app zshenv/.zshenv
	entry zshenv/.zshenv "~/.zshenv"
	run
	assert_eq "status" "$STATUS" 0 || return
	assert_linked "$HOME/.zshenv" "$DOTS/zshenv/.zshenv" || return
	ok
}

test_only_the_named_entries() {
	it "naming entries deploys those and no others"
	app hypr
	app nvim
	entry hypr "~/.config/hypr"
	entry nvim "~/.config/nvim"
	run nvim
	assert_eq "status" "$STATUS" 0 || return
	assert_linked "$HOME/.config/nvim" "$DOTS/nvim" || return
	[[ -e $HOME/.config/hypr ]] && { fail "deployed hypr too"; return; }
	ok
}

test_unknown_name_is_an_error() {
	it "a name that isn't in the manifest is a usage error, not nothing to do"
	app hypr
	entry hypr "~/.config/hypr"
	run hyrp
	assert_eq "status" "$STATUS" 2 || return
	assert_has "said" "$ERR" "not in the manifest: hyrp" || return
	[[ -e $HOME/.config/hypr ]] && { fail "deployed something anyway"; return; }
	ok
}

test_unknown_name_everywhere() {
	it "status and remove refuse an unknown name the same way"
	app hypr
	entry hypr "~/.config/hypr"
	"$RACK" deploy status hyrp >/dev/null 2>&1
	assert_eq "status" "$?" 2 || return
	"$RACK" deploy remove hyrp >/dev/null 2>&1
	assert_eq "remove" "$?" 2 || return
	ok
}

test_empty_manifest() {
	it "an empty manifest is nothing to do, not an entry with no name"
	run
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "no rows" "$OUT" "" || return
	assert_has "said" "$ERR" "nothing to do" || return
	ok
}

test_comments_and_blank_lines_are_skipped() {
	it "manifest comments and blank lines are not entries"
	app hypr
	printf '# a comment\n\n   # indented\n' >>"$RACK_MANIFEST"
	entry hypr "~/.config/hypr"
	run
	assert_eq "status" "$STATUS" 0 || return
	assert_linked "$HOME/.config/hypr" "$DOTS/hypr" || return
	ok
}

test_dotfiles_override() {
	it "RACK_DOTFILES moves where sources are found"
	mkdir -p "$TMP/other/hypr"
	echo other >"$TMP/other/hypr/config"
	entry hypr "~/.config/hypr"
	RACK_DOTFILES="$TMP/other" run
	assert_linked "$HOME/.config/hypr" "$TMP/other/hypr" || return
	ok
}

# ---- something real in the way ---------------------------------------------

test_conflict_is_refused() {
	it "a real config in the way is refused, and left exactly as it was"
	app hypr
	entry hypr "~/.config/hypr"
	mkdir -p "$HOME/.config/hypr"
	echo "mine" >"$HOME/.config/hypr/hyprland.lua"
	run
	assert_eq "status" "$STATUS" 1 || return
	assert_has "names the flag that works" "$ERR" "--force moves it aside" || return
	[[ -L $HOME/.config/hypr ]] && { fail "linked over it"; return; }
	assert_eq "content" "$(cat "$HOME/.config/hypr/hyprland.lua")" "mine" || return
	ok
}

test_conflict_without_repo_copy_suggests_adopt() {
	it "with no repo copy to link, the refusal names --adopt instead"
	entry hypr "~/.config/hypr"
	mkdir -p "$HOME/.config/hypr"
	echo "mine" >"$HOME/.config/hypr/hyprland.lua"
	run
	assert_eq "status" "$STATUS" 1 || return
	assert_has "names --adopt" "$ERR" "--adopt moves it into the repo" || return
	ok
}

test_force_moves_aside_then_links() {
	it "--force moves the config aside, under its path in HOME, and links"
	app hypr
	entry hypr "~/.config/hypr"
	mkdir -p "$HOME/.config/hypr"
	echo "mine" >"$HOME/.config/hypr/hyprland.lua"
	run --force
	assert_eq "status" "$STATUS" 0 || return
	assert_linked "$HOME/.config/hypr" "$DOTS/hypr" || return
	local saved
	saved=$(backups)
	[[ -n $saved ]] || { fail "no backup"; return; }
	assert_eq "kept, not deleted" "$(cat "$saved/.config/hypr/hyprland.lua" 2>/dev/null)" "mine" || return
	assert_has "said where" "$OUT" "moved aside to ~/.local/state/rack/backups/" || return
	ok
}

test_force_outside_home() {
	it "a target outside HOME is backed up under its absolute path"
	app tool
	entry tool "$TMP/outside/tool"
	mkdir -p "$TMP/outside/tool"
	echo "theirs" >"$TMP/outside/tool/config"
	run --force
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "kept" "$(cat "$(backups)/${TMP#/}/outside/tool/config" 2>/dev/null)" "theirs" || return
	ok
}

# ---- an app's own first-launch config ---------------------------------------

test_untouched_data() {
	# name | what the app wrote
	cat <<-'EOF'
		ghostty's empty config|
		hyprland's new marker|hl.config({ autogenerated = true })
		hyprland's old marker|autogenerated = 1
		an indented marker|    hl.config({ autogenerated = true })
	EOF
}

test_untouched_defaults_move_without_force() {
	local row label body
	while IFS='|' read -r label body; do
		teardown
		setup
		it "an untouched default moves aside without --force: $label"
		app app
		entry app "~/.config/app"
		mkdir -p "$HOME/.config/app"
		printf '%s' "$body" >"$HOME/.config/app/config"
		run
		assert_eq "status" "$STATUS" 0 || return
		assert_linked "$HOME/.config/app" "$DOTS/app" || return
		assert_has "said why" "$OUT" "(untouched default)" || return
		[[ -n $(backups) ]] || { fail "not kept"; return; }
		ok
	done < <(test_untouched_data)
}

test_edited_default_needs_force() {
	it "a default with anything of yours in it needs --force"
	app hypr
	entry hypr "~/.config/hypr"
	mkdir -p "$HOME/.config/hypr"
	echo 'hl.config({ autogenerated = true })' >"$HOME/.config/hypr/hyprland.lua"
	echo 'bind = SUPER, Q, killactive' >"$HOME/.config/hypr/binds.conf"
	run
	assert_eq "status" "$STATUS" 1 || return
	[[ -L $HOME/.config/hypr ]] && { fail "linked over it"; return; }
	ok
}

test_marker_must_start_the_line() {
	it "the autogenerated marker only counts at the start of a line"
	app hypr
	entry hypr "~/.config/hypr"
	mkdir -p "$HOME/.config/hypr"
	echo '-- I removed autogenerated = 1 on purpose' >"$HOME/.config/hypr/hyprland.lua"
	run
	assert_eq "status" "$STATUS" 1 || return
	ok
}

test_empty_directory_moves_without_force() {
	it "an empty directory holds no config, so it moves aside without --force"
	app app
	entry app "~/.config/app"
	mkdir -p "$HOME/.config/app"
	run
	assert_eq "status" "$STATUS" 0 || return
	assert_linked "$HOME/.config/app" "$DOTS/app" || return
	ok
}

# ---- adopting ------------------------------------------------------------------

test_adopt_moves_into_the_repo() {
	it "--adopt moves an existing config into the repo and links it back"
	entry hypr "~/.config/hypr"
	mkdir -p "$HOME/.config/hypr"
	echo "mine" >"$HOME/.config/hypr/hyprland.lua"
	run --adopt
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "in the repo" "$(cat "$DOTS/hypr/hyprland.lua" 2>/dev/null)" "mine" || return
	assert_linked "$HOME/.config/hypr" "$DOTS/hypr" || return
	assert_has "said" "$OUT" "adopted" || return
	ok
}

test_adopt_refuses_over_a_repo_copy() {
	it "--adopt won't replace the repo's own copy"
	app hypr
	entry hypr "~/.config/hypr"
	mkdir -p "$HOME/.config/hypr"
	echo "mine" >"$HOME/.config/hypr/hyprland.lua"
	run --adopt
	assert_eq "status" "$STATUS" 1 || return
	assert_eq "repo untouched" "$(cat "$DOTS/hypr/config")" "repo hypr" || return
	assert_eq "home untouched" "$(cat "$HOME/.config/hypr/hyprland.lua")" "mine" || return
	ok
}

test_adopt_action() {
	it "rack deploy adopt <name> is the same move, and wants a name"
	entry hypr "~/.config/hypr"
	mkdir -p "$HOME/.config/hypr"
	echo "mine" >"$HOME/.config/hypr/hyprland.lua"
	run adopt
	assert_eq "no name" "$STATUS" 2 || return
	run adopt hypr
	assert_eq "status" "$STATUS" 0 || return
	assert_linked "$HOME/.config/hypr" "$DOTS/hypr" || return
	ok
}

# ---- dry run, status, remove ------------------------------------------------

test_dry_run_changes_nothing() {
	it "RIG_DRY_RUN=1 says what it would do and changes nothing"
	app hypr
	app nvim
	entry hypr "~/.config/hypr"
	entry nvim "~/.config/nvim"
	mkdir -p "$HOME/.config/nvim"
	echo "mine" >"$HOME/.config/nvim/init.lua"
	RIG_DRY_RUN=1 run --force
	assert_eq "status" "$STATUS" 0 || return
	assert_has "would link" "$OUT" "would link" || return
	assert_has "would move" "$OUT" "would move aside" || return
	[[ -e $HOME/.config/hypr ]] && { fail "linked hypr"; return; }
	[[ -L $HOME/.config/nvim ]] && { fail "replaced nvim"; return; }
	[[ -z $(backups) ]] || { fail "made a backup"; return; }
	ok
}

test_status_reports_without_changing() {
	it "status names each entry's state and changes nothing"
	app hypr
	app nvim
	entry hypr "~/.config/hypr"
	entry nvim "~/.config/nvim"
	mkdir -p "$HOME/.config/nvim"
	OUT=$("$RACK" deploy status 2>&1)
	assert_has "absent" "$OUT" "hypr         absent" || return
	assert_has "conflict" "$OUT" "nvim         conflict" || return
	[[ -e $HOME/.config/hypr ]] && { fail "linked"; return; }
	ok
}

test_remove_unlinks_only_ours() {
	it "remove unlinks links into the repo and leaves anything else alone"
	app hypr
	app nvim
	entry hypr "~/.config/hypr"
	entry nvim "~/.config/nvim"
	run hypr
	mkdir -p "$HOME/.config/nvim"
	echo "mine" >"$HOME/.config/nvim/init.lua"
	OUT=$("$RACK" deploy remove 2>&1)
	STATUS=$?
	assert_eq "status" "$STATUS" 0 || return
	[[ -e $HOME/.config/hypr ]] && { fail "hypr still linked"; return; }
	[[ -d $DOTS/hypr ]] || { fail "removed the repo copy"; return; }
	assert_eq "nvim kept" "$(cat "$HOME/.config/nvim/init.lua")" "mine" || return
	assert_has "said" "$OUT" "left alone (not ours)" || return
	ok
}

test_unknown_option() {
	it "an unknown option is a usage error"
	run --forse
	assert_eq "status" "$STATUS" 2 || return
	ok
}

# ---- runner ------------------------------------------------------------------

main() {
	[[ -x $RACK ]] || {
		printf 'rack not found or not executable: %s\n' "$RACK" >&2
		exit 1
	}

	local tests t
	mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_' | grep -v '_data$' | sort)

	printf 'rack deploy\n'
	for t in "${tests[@]}"; do
		[[ -n $FILTER && $t != *"$FILTER"* ]] && continue
		CURRENT=$t
		setup
		"$t"
		teardown
	done

	printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
	((FAIL == 0)) || {
		printf '\nfailures:\n'
		printf '  %s\n' "${FAILURES[@]}"
		exit 1
	}
}

main "$@"
