#!/usr/bin/env bash
# tests for relay's default module
#
# Same shape as relay-toggle.test.sh next door: plain bash, no framework. What
# is different is the machine under test. A default resolves against what is
# installed, so every test builds a machine of its own and nothing from the
# real one may leak in:
#
#   - PATH is a directory of symlinks to the handful of tools relay needs, plus
#     $TMP/apps, where "installing" an app is creating a file. /usr/bin is not
#     on it: the real kitty or vim there would decide the answers.
#   - flatpak's installations are FLATPAK_SYSTEM_DIR and FLATPAK_USER_DIR, the
#     variables flatpak itself honours, pointed at empty directories.
#   - xdg-mime, xdg-settings, hyprctl, uwsm-app, xdg-open and busctl (what
#     relay notif sends through) are stubs that append their argv to $CALLS,
#     one call per line, so the assertions check exactly what a command would
#     have told the desktop.
#
#   ./tests/relay-default.test.sh            # all tests
#   ./tests/relay-default.test.sh handler    # only tests whose name matches
#
# Everything goes through `relay default`, which is the interface. The one
# exception is the test that asks hypr/modules/vars.lua directly, because
# the binds are the other caller and must get the same answer.
set -uo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
RELAY="$ROOT/relay"
HYPR="$ROOT/../hypr"

FILTER=${1-}
PASS=0
FAIL=0
FAILURES=()

ORIG_PATH=$PATH
ORIG_HOME=$HOME
ORIG_TMPDIR=${TMPDIR:-/tmp}

# ---- harness -----------------------------------------------------------------

# A stub that records its own name and argv as one line of $CALLS.
recorder() {
	cat >"$1" <<-'EOF'
		#!/usr/bin/env bash
		printf '%s' "${0##*/}" >>"$RELAY_TEST_CALLS"
		printf ' %s' "$@" >>"$RELAY_TEST_CALLS"
		printf '\n' >>"$RELAY_TEST_CALLS"
	EOF
	chmod +x "$1"
}

setup() {
	# Made under the original TMPDIR: the last test's TMPDIR pointed inside a
	# directory teardown has since removed. And stop dead if this fails --
	# every path below is "$TMP/...", and an empty $TMP makes them the real
	# /bin, /home and the rest.
	TMP=$(TMPDIR=$ORIG_TMPDIR mktemp -d) && [[ -d $TMP ]] || {
		printf 'harness error: cannot make a temp directory\n' >&2
		exit 1
	}
	CALLS="$TMP/calls"
	: >"$CALLS"
	mkdir -p "$TMP/sys" "$TMP/bin" "$TMP/apps" "$TMP/home" "$TMP/share/applications" \
		"$TMP/flatpak/system/exports/bin" "$TMP/flatpak/user/exports/bin" "$TMP/tmp"

	local tool src
	for tool in bash env lua readlink dirname basename cat mkdir rm mktemp id sort sh; do
		src=$(PATH=$ORIG_PATH command -v "$tool") || continue
		ln -sf "$src" "$TMP/sys/$tool"
	done

	local stub
	for stub in xdg-mime xdg-settings hyprctl uwsm-app xdg-open busctl; do
		recorder "$TMP/bin/$stub"
	done
	# xdg-settings says which $BROWSER it saw, since the point of `env -u` is
	# that it sees none.
	cat >>"$TMP/bin/xdg-settings" <<-'EOF'
		printf 'BROWSER=%s\n' "${BROWSER-unset}" >>"$RELAY_TEST_CALLS"
	EOF

	export RELAY_TEST_CALLS="$CALLS"
	export HOME="$TMP/home"
	# Only what runs under test gets this PATH (see run); the harness keeps
	# its own, since it needs chmod, jq and the rest to build the machine.
	TEST_PATH="$TMP/apps:$TMP/bin:$TMP/sys"
	export TMPDIR="$TMP/tmp"
	export FLATPAK_SYSTEM_DIR="$TMP/flatpak/system"
	export FLATPAK_USER_DIR="$TMP/flatpak/user"
	export XDG_DATA_DIRS="$TMP/share"
	export RELAY_DEFAULTS_LUA="$HYPR/modules/defaults.lua"
	export HYPRLAND_INSTANCE_SIGNATURE=test
	export BROWSER=should-be-ignored
	export RIG_COLOR=never RIG_LOG_JOURNAL=never
	unset XDG_STATE_HOME XDG_CONFIG_HOME XDG_DATA_HOME RIG_DRY_RUN XDG_RUNTIME_DIR

	# The stubs are only protection if they are what is found. A PATH that
	# reached the real xdg-mime would rewrite the handlers of whoever ran this.
	local resolved
	resolved=$(PATH=$TEST_PATH command -v xdg-mime)
	[[ $resolved == "$TMP/"* ]] || {
		printf 'harness error: xdg-mime resolves to %s, not the stub\n' "$resolved" >&2
		exit 1
	}
}

teardown() {
	export HOME="$ORIG_HOME"
	unset TMPDIR
	[[ -n ${TMP:-} && -d $TMP ]] && rm -rf "$TMP"
	return 0
}

# install <bin> — a native app is a file on PATH that records how it was run.
install() {
	recorder "$TMP/apps/$1"
}

# flatpak <ref> [user] — a flatpak is its export.
flatpak() {
	: >"$TMP/flatpak/${2:-system}/exports/bin/$1"
}

# desktop <id> — a .desktop file the handler can be pointed at.
desktop() {
	: >"$TMP/share/applications/$1"
}

no_uwsm() {
	rm -f "$TMP/bin/uwsm-app"
}

state() {
	mkdir -p "$HOME/.local/state/rack/defaults"
	printf '%s\n' "$2" >"$HOME/.local/state/rack/defaults/$1"
}

run() {
	OUT=$(PATH=$TEST_PATH "$RELAY" default "$@" 2>"$TMP/err")
	STATUS=$?
	ERR=$(cat "$TMP/err")
	return 0
}

calls() { cat "$CALLS"; }

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

it() { CURRENT=$1; }

# ---- resolving ---------------------------------------------------------------

test_fallback_is_first_installed() {
	it "with nothing set, the first installed candidate is the default"
	install foot
	install alacritty
	run get terminal
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "command" "$OUT" "uwsm-app -- foot" || return
	ok
}

test_fallback_follows_the_ranking() {
	it "the ranking decides between installed candidates, not the order installed"
	install foot
	install kitty
	run get terminal
	assert_eq "command" "$OUT" "uwsm-app -- kitty" || return
	ok
}

test_nothing_installed_names_the_first() {
	it "with nothing installed, the first candidate is named anyway"
	run get terminal
	assert_eq "command" "$OUT" "uwsm-app -- kitty" || return
	run list
	assert_has "list" "$OUT" "nothing installed" || return
	ok
}

test_flatpak_system() {
	it "a candidate only installed as a flatpak runs as one"
	flatpak com.mitchellh.ghostty
	run get terminal
	assert_eq "command" "$OUT" "uwsm-app -- flatpak run com.mitchellh.ghostty" || return
	ok
}

test_flatpak_user() {
	it "a per-user flatpak counts as installed"
	flatpak com.brave.Browser user
	run get browser
	assert_eq "command" "$OUT" "uwsm-app -- flatpak run com.brave.Browser --password-store=basic" || return
	ok
}

test_native_beats_flatpak() {
	it "the same candidate installed both ways runs natively"
	install brave
	flatpak com.brave.Browser
	run get browser
	assert_eq "command" "$OUT" "uwsm-app -- brave --password-store=basic" || return
	ok
}

test_no_uwsm_no_prefix() {
	it "without uwsm, commands are not wrapped in uwsm-app"
	no_uwsm
	install foot
	run get terminal
	assert_eq "command" "$OUT" "foot" || return
	ok
}

test_terminal_editor_is_unwrapped() {
	it "a terminal editor is a command, never wrapped"
	install nvim
	run get editor
	assert_eq "command" "$OUT" "nvim" || return
	ok
}

test_state_dir_follows_xdg() {
	it "XDG_STATE_HOME moves where set defaults are kept"
	install foot
	install kitty
	export XDG_STATE_HOME="$TMP/state"
	run set terminal foot
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "file" "$(cat "$TMP/state/rack/defaults/terminal")" "foot" || return
	[[ -e $HOME/.local/state/rack/defaults/terminal ]] && { fail "also wrote under HOME"; return; }
	ok
}

# ---- setting -----------------------------------------------------------------

test_set_candidate() {
	it "set stores the candidate's name, and get resolves it"
	install kitty
	install foot
	run set terminal foot
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "file" "$(cat "$HOME/.local/state/rack/defaults/terminal")" "foot" || return
	run get terminal
	assert_eq "command" "$OUT" "uwsm-app -- foot" || return
	ok
}

test_set_follows_how_it_is_installed() {
	it "a set default is spelled for how it is installed at the time"
	install brave
	run set browser brave
	run get browser
	assert_eq "native" "$OUT" "uwsm-app -- brave --password-store=basic" || return
	rm -f "$TMP/apps/brave"
	flatpak com.brave.Browser
	run get browser
	assert_eq "flatpak" "$OUT" "uwsm-app -- flatpak run com.brave.Browser --password-store=basic" || return
	ok
}

test_set_uninstalled_warns_and_sets() {
	it "a candidate that is not installed is set, with a warning"
	run set browser firefox
	assert_eq "status" "$STATUS" 0 || return
	assert_has "warning" "$ERR" "not installed" || return
	run get browser
	assert_eq "command" "$OUT" "uwsm-app -- firefox" || return
	ok
}

test_set_but_uninstalled_stands_in() {
	it "a set candidate that was uninstalled gives way to the first installed one"
	install kitty
	state terminal foot
	run get terminal
	assert_eq "command" "$OUT" "uwsm-app -- kitty" || return
	run list
	assert_has "said why" "$OUT" "Foot is set, not installed" || return
	run list --json
	assert_has "source" "$OUT" '"source":"missing"' || return
	assert_has "wanted" "$OUT" '"wanted":"foot"' || return
	ok
}

test_set_again_once_reinstalled() {
	it "the set candidate comes back once it is installed again"
	install kitty
	state terminal foot
	install foot
	run get terminal
	assert_eq "command" "$OUT" "uwsm-app -- foot" || return
	ok
}

test_set_uninstalled_names_the_stand_in() {
	it "setting a candidate that is not installed says what opens instead"
	install kitty
	run set terminal foot
	assert_eq "status" "$STATUS" 0 || return
	assert_has "warning" "$ERR" "Foot is not installed" || return
	assert_has "stand-in" "$ERR" "Kitty opens until it is" || return
	ok
}

test_set_typo_is_refused() {
	it "a name that is no candidate is refused, not taken as a command"
	run set browser firefx
	assert_eq "status" "$STATUS" 2 || return
	assert_has "message" "$ERR" "brave firefox chromium chrome zen" || return
	[[ -e $HOME/.local/state/rack/defaults/browser ]] && { fail "wrote the state anyway"; return; }
	assert_eq "calls" "$(calls)" "" || return
	ok
}

test_set_custom_command() {
	it "--command sets a custom command, which runs as written"
	run set terminal --command "wezterm start --always-new-process"
	assert_eq "status" "$STATUS" 0 || return
	run get terminal
	assert_eq "command" "$OUT" "wezterm start --always-new-process" || return
	run list
	assert_has "list" "$OUT" "custom command" || return
	ok
}

test_old_command_line_state_is_custom() {
	it "a state file from before names were stored reads as a custom command"
	install ghostty
	state terminal "uwsm-app -- ghostty"
	run get terminal
	assert_eq "command" "$OUT" "uwsm-app -- ghostty" || return
	run list
	assert_has "list" "$OUT" "custom command" || return
	ok
}

test_unset() {
	it "unset goes back to the first installed candidate"
	install kitty
	install foot
	state terminal foot
	run unset terminal
	assert_eq "status" "$STATUS" 0 || return
	[[ -e $HOME/.local/state/rack/defaults/terminal ]] && { fail "state file still there"; return; }
	run get terminal
	assert_eq "command" "$OUT" "uwsm-app -- kitty" || return
	ok
}

test_set_needs_a_value() {
	it "set with no candidate is a usage error"
	run set terminal
	assert_eq "status" "$STATUS" 2 || return
	ok
}

test_set_candidate_and_command_is_an_error() {
	it "a candidate and --command together is a usage error"
	install foot
	run set terminal foot --command "wezterm start"
	assert_eq "status" "$STATUS" 2 || return
	[[ -e $HOME/.local/state/rack/defaults/terminal ]] && { fail "wrote the state anyway"; return; }
	ok
}

test_dry_run_changes_nothing() {
	it "RIG_DRY_RUN=1 writes nothing and calls nothing"
	install firefox
	desktop firefox.desktop
	RIG_DRY_RUN=1 run set browser firefox
	assert_eq "status" "$STATUS" 0 || return
	[[ -e $HOME/.local/state/rack/defaults/browser ]] && { fail "wrote the state"; return; }
	assert_eq "calls" "$(calls)" "" || return
	assert_has "said" "$OUT" "would write" || return
	ok
}

# ---- handlers ----------------------------------------------------------------

test_handler_browser() {
	it "setting the browser sets default-web-browser, with \$BROWSER out of the way"
	install firefox
	desktop firefox.desktop
	run set browser firefox
	assert_eq "status" "$STATUS" 0 || return
	assert_has "calls" "$(calls)" "xdg-settings set default-web-browser firefox.desktop" || return
	assert_has "env" "$(calls)" "BROWSER=unset" || return
	ok
}

test_handler_editor() {
	it "setting the editor sets the text/plain handler"
	install nvim
	desktop nvim.desktop
	run set editor nvim
	assert_has "calls" "$(calls)" "xdg-mime default nvim.desktop text/plain" || return
	ok
}

test_handler_file_manager() {
	it "setting the file manager sets the inode/directory handler"
	install thunar
	desktop thunar.desktop
	run set file-manager thunar
	assert_has "calls" "$(calls)" "xdg-mime default thunar.desktop inode/directory" || return
	ok
}

test_handler_terminal() {
	it "setting the terminal writes the list xdg-terminal-exec reads"
	install foot
	desktop foot.desktop
	run set terminal foot
	assert_eq "list" "$(cat "$HOME/.config/xdg-terminals.list")" "foot.desktop" || return
	ok
}

test_handler_second_desktop_id() {
	it "the first .desktop id that exists wins"
	install alacritty
	desktop alacritty.desktop
	run set terminal alacritty
	assert_eq "list" "$(cat "$HOME/.config/xdg-terminals.list")" "alacritty.desktop" || return
	ok
}

test_handler_flatpak_is_its_ref() {
	it "a flatpak default's handler is its ref"
	flatpak org.mozilla.firefox
	run set browser firefox
	assert_has "calls" "$(calls)" "default-web-browser org.mozilla.firefox.desktop" || return
	ok
}

test_handler_left_alone_without_desktop() {
	it "no .desktop file leaves the handler alone and says so"
	install nvim
	run set editor nvim
	assert_eq "status" "$STATUS" 0 || return
	[[ $(calls) == *xdg-mime* ]] && { fail "called xdg-mime anyway: [$(calls)]"; return; }
	assert_has "warning" "$ERR" "handler is left as it was" || return
	ok
}

test_handler_after_unset() {
	it "unset points the handler at the default it falls back to"
	install nvim
	install vim
	desktop nvim.desktop
	state editor vim
	run unset editor
	assert_has "calls" "$(calls)" "xdg-mime default nvim.desktop text/plain" || return
	ok
}

test_reload_in_hyprland() {
	it "a change reloads Hyprland so the binds pick it up"
	install foot
	run set terminal foot
	assert_has "calls" "$(calls)" "hyprctl reload" || return
	ok
}

test_no_reload_outside_hyprland() {
	it "outside a Hyprland session there is nothing to reload"
	install foot
	unset HYPRLAND_INSTANCE_SIGNATURE
	run set terminal foot
	assert_eq "status" "$STATUS" 0 || return
	[[ $(calls) == *hyprctl* ]] && { fail "reloaded anyway"; return; }
	ok
}

# ---- starting ----------------------------------------------------------------

test_exec_kitty_takes_trailing_program() {
	it "kitty gets its app-id and title, and the program with no -e"
	install kitty
	run exec terminal --app-id quickshell.float --title Update -- sudo pacman -Syu
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "argv" "$(calls)" \
		"uwsm-app -- kitty --app-id=quickshell.float --title=Update sh -c sudo pacman -Syu" || return
	ok
}

test_exec_foot_takes_e() {
	it "foot gets -e before the program"
	install foot
	run exec terminal --app-id quickshell.float -- btop
	assert_eq "argv" "$(calls)" "uwsm-app -- foot --app-id=quickshell.float -e sh -c btop" || return
	ok
}

test_exec_ghostty_takes_class() {
	it "ghostty gets its app-id as --class"
	flatpak com.mitchellh.ghostty
	run exec terminal --app-id quickshell.float -- btop
	assert_eq "argv" "$(calls)" \
		"uwsm-app -- flatpak run com.mitchellh.ghostty --class=quickshell.float -e sh -c btop" || return
	ok
}

test_exec_terminal_alone() {
	it "no command just opens the terminal"
	install foot
	run exec terminal
	assert_eq "argv" "$(calls)" "uwsm-app -- foot" || return
	ok
}

test_exec_custom_terminal() {
	it "a custom terminal gets -e and the command, and no flags it may not know"
	no_uwsm
	install myterm
	state terminal "myterm --login"
	run exec terminal --app-id quickshell.float --title Update -- echo "a b"
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "argv" "$(calls)" "myterm --login -e sh -c echo a b" || return
	ok
}

test_exec_webapp_in_app_mode() {
	it "a chromium-family browser opens a page as its own window"
	install chromium
	run exec browser --app https://wiki.archlinux.org/
	assert_eq "argv" "$(calls)" "uwsm-app -- chromium --app=https://wiki.archlinux.org/" || return
	ok
}

test_exec_webapp_without_app_mode() {
	it "firefox has no app mode, so the page goes to xdg-open"
	install firefox
	run exec browser --app https://wiki.archlinux.org/
	assert_eq "argv" "$(calls)" "uwsm-app -- xdg-open https://wiki.archlinux.org/" || return
	ok
}

test_exec_webapp_custom_browser() {
	it "a custom browser is not assumed to have an app mode"
	state browser "brave --incognito"
	run exec browser --app https://example.org/
	assert_eq "argv" "$(calls)" "uwsm-app -- xdg-open https://example.org/" || return
	ok
}

test_exec_other_role() {
	it "any role's default can be started as it is"
	install thunar
	run exec file-manager
	assert_eq "argv" "$(calls)" "uwsm-app -- thunar" || return
	ok
}

test_exec_option_for_wrong_role() {
	it "an option for another role is a usage error, and starts nothing"
	install foot
	run exec terminal --app https://example.org/
	assert_eq "status" "$STATUS" 2 || return
	run exec browser -- echo hi
	assert_eq "status" "$STATUS" 2 || return
	assert_eq "calls" "$(calls)" "" || return
	ok
}

# ---- the interface -----------------------------------------------------------

test_list_json() {
	it "list --json is every role, with its candidates and which are installed"
	install foot
	state browser "brave --incognito"
	run list --json
	assert_eq "status" "$STATUS" 0 || return
	local shape
	shape=$(jq -c '[.[] | {role, source, name}]' <<<"$OUT") || { fail "not JSON: [$OUT]"; return; }
	assert_eq "roles" "$shape" \
		'[{"role":"terminal","source":"fallback","name":"foot"},{"role":"editor","source":"fallback","name":"nvim"},{"role":"browser","source":"custom","name":null},{"role":"file-manager","source":"fallback","name":"nautilus"}]' || return
	assert_eq "installed" "$(jq -c '[.[0].candidates[] | select(.installed) | .name]' <<<"$OUT")" '["foot"]' || return
	assert_eq "default" "$(jq -c '[.[0].candidates[] | select(.default) | .name]' <<<"$OUT")" '["foot"]' || return
	ok
}

test_list_role_shows_candidates() {
	it "list <role> marks the default among the candidates"
	install foot
	flatpak com.mitchellh.ghostty
	state terminal ghostty
	run list terminal
	assert_has "default" "$OUT" "* ghostty" || return
	assert_has "via" "$OUT" "flatpak" || return
	assert_has "missing" "$OUT" "not installed" || return
	ok
}

test_unknown_role() {
	it "an unknown role is a usage error that names the roles"
	run get shell
	assert_eq "status" "$STATUS" 2 || return
	assert_has "message" "$ERR" "terminal, editor, browser, file-manager" || return
	ok
}

test_lua_missing() {
	it "without lua, the command says so and exits 127"
	rm -f "$TMP/sys/lua"
	run get terminal
	assert_eq "status" "$STATUS" 127 || return
	assert_has "message" "$ERR" "lua not found" || return
	ok
}

test_exec_failure_is_a_notification() {
	it "exec that cannot start anything says so as a notification"
	rm -f "$TMP/sys/lua"
	run exec terminal -- btop
	assert_eq "status" "$STATUS" 127 || return
	assert_has "notified" "$(calls)" "Couldn't open the terminal lua not found" || return
	assert_has "urgency" "$(calls)" "urgency y 2" || return
	ok
}

test_other_failures_are_not_notifications() {
	it "only exec notifies; a failing get is just an error"
	rm -f "$TMP/sys/lua"
	run get terminal
	[[ $(calls) == *busctl* ]] && { fail "notified: [$(calls)]"; return; }
	ok
}

test_finds_the_deployed_module() {
	it "with no override, the module is read where rack deploys hypr"
	install foot
	unset RELAY_DEFAULTS_LUA
	run get terminal
	assert_eq "status" "$STATUS" 1 || return
	assert_has "hint" "$ERR" "rack deploy hypr" || return
	mkdir -p "$HOME/.config/hypr/modules"
	ln -s "$HYPR/modules/defaults.lua" "$HOME/.config/hypr/modules/defaults.lua"
	run get terminal
	assert_eq "status" "$STATUS" 0 || return
	assert_eq "command" "$OUT" "uwsm-app -- foot" || return
	ok
}

# The binds are the module's other caller. However the machine looks, they
# must run what `relay default get` says they run.
test_binds_agree_with_get() {
	it "vars.lua gives every role the same command as get"
	install foot
	install thunar
	flatpak com.brave.Browser
	state editor "code --new-window"
	local key role want got
	for key in terminal:terminal editor:editor fileManager:file-manager browser:browser; do
		role=${key#*:}
		run get "$role"
		want=$OUT
		got=$(cd "$HYPR" && PATH=$TEST_PATH lua -e 'package.path = "./?.lua;" .. package.path
			io.write(require("modules.vars")["'"${key%%:*}"'"])') || { fail "vars.lua did not load"; return; }
		assert_eq "$role" "$got" "$want" || return
	done
	ok
}

test_temp_files_are_cleaned_up() {
	it "no temp file outlives a command, exec included"
	install foot
	run list
	run exec terminal -- true
	run set browser nope
	local left
	left=$(ls -A "$TMP/tmp")
	assert_eq "left behind" "$left" "" || return
	ok
}

test_help_lists_every_action() {
	it "help names every action"
	OUT=$(PATH=$TEST_PATH "$RELAY" help default 2>&1)
	local action
	for action in get list set unset exec; do
		assert_has "$action" "$OUT" "relay default $action" || return
	done
	ok
}

# ---- runner ------------------------------------------------------------------

main() {
	[[ -x $RELAY ]] || {
		printf 'relay not found or not executable: %s\n' "$RELAY" >&2
		exit 1
	}
	command -v lua >/dev/null && command -v jq >/dev/null || {
		printf 'these tests need lua and jq on PATH\n' >&2
		exit 1
	}

	local tests t
	mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_' | sort)

	printf 'relay default\n'
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
