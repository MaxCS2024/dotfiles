pragma Singleton
import Quickshell
import QtQuick
import "../config"

// Runs a command in a terminal window, for the jobs that belong in one
// rather than behind a spinner in a panel: a package upgrade that wants a
// sudo password and a y/n per PKGBUILD, a dependency check whose whole
// output is the point, anything long enough that you want a scrollback.
//
// The window floats in the middle of the screen instead of being tiled
// into whatever you were working in. That is not done here — it is one
// window rule, "float-task-window" in hypr/modules/windowrules.lua,
// matching the app-id this passes (Theme.floatAppId). Keeping the policy
// in the compositor's own config means the size and position are tunable
// without touching QML, and anything else that can name its own app-id
// gets the same treatment without going through this file at all.
//
// Everything about the call is optional except the command:
//
//   Terminal.run("sudo pacman -Syu")                  // float, hold open
//   Terminal.run("btop", { hold: false })             // no "press Enter"
//   Terminal.run("make", { floating: false })         // tile it normally
//   Terminal.run(cmd, { appId: "my-thing" })          // its own rule
//   Terminal.run(cmd, { title: "Update" })            // window title
//   Terminal.run(Terminal.quote(argv))                 // an argv, not a line
//
// `hold` is what keeps the shell alive on a `read` after the command
// exits — a terminal that vanishes the instant pacman finishes takes the
// summary, and any error, with it. Turn it off for anything you'd quit
// yourself.
Singleton {
    id: root

    readonly property string holdTail:
        '; printf "\\n\\033[2m— finished (exit %s) · press Enter to close —\\033[0m\\n" "$?"'
        + '; read -r _'

    // Which terminal, asked at spawn time of hypr/modules/vars.lua, the
    // file SUPER+RETURN is bound from — through its deployed path under
    // ~/.config/hypr, so it doesn't matter where the repo was cloned. It resolves the state file that
    // Setup › Defaults writes against its own fallbacks, so the window
    // this opens is the one that key opens. Run rather than parsed, as
    // MenuActions' varsCur is and for the same reason. Theme.terminal is
    // only the answer when that can't be had (no lua, no checkout).
    //
    // The line that comes back is a whole command
    // ("uwsm-app -- flatpak run com.mitchellh.ghostty"), deliberately
    // word-split into argv, launcher and all.
    //
    // The flags differ per terminal, and getting them wrong is not
    // cosmetic:
    //   * kitty rejects -e ("Unknown flag"), so it gets the program as
    //     plain trailing arguments — which foot and alacritty take too,
    //     but ghostty doesn't, so -e stays the default.
    //   * ghostty and alacritty take the app-id as --class; foot and
    //     kitty as --app-id. ghostty also drops an id that isn't a valid
    //     GTK application id, which is why Theme.floatAppId is dotted.
    // Everything outside the table goes through positional parameters,
    // so the command needs no second round of quoting.
    readonly property string launchScript: [
        't=$(lua -e \'io.write(dofile(os.getenv("HOME").."/.config/hypr/modules/vars.lua").terminal or "")\' 2>/dev/null)',
        '[ -n "$t" ] || t="$4"',
        'id=$1 title=$2 cmd=$3',
        'case "$t" in',
        '  *ghostty*|*alacritty*) idf=--class= ;;',
        '  *) idf=--app-id= ;;',
        'esac',
        'set -- $t',
        '[ -n "$id" ] && set -- "$@" "$idf$id"',
        '[ -n "$title" ] && set -- "$@" "--title=$title"',
        'case "$t" in *kitty*) ;; *) set -- "$@" -e ;; esac',
        'exec "$@" sh -c "$cmd"'
    ].join("\n")

    function run(cmd, opts) {
        const o = opts || ({})
        const hold = o.hold !== false
        const floating = o.floating !== false
        const appId = floating ? (o.appId || Theme.floatAppId) : ""

        // Detached, not a Process of ours: uwsm-app doesn't hand the
        // terminal off and return, it stays until the window closes
        // (`uwsm-app -- sleep 3` takes 3s). A reused Process would kill
        // the last window on every new call — the btop you opened from the
        // launcher, the moment you ran an update.
        Quickshell.execDetached(["sh", "-c", root.launchScript, "sh",
            appId, o.title || "", cmd + (hold ? root.holdTail : ""),
            Theme.appLauncherPrefix + " -- " + Theme.terminal])
    }

    // An argv as one sh command line, each word single-quoted, for a
    // caller holding a list rather than a line — a desktop entry's
    // `command`, say — so a space or quote in it stays inside its word.
    function quote(argv) {
        return argv.map(a => "'" + String(a).split("'").join("'\\''") + "'").join(" ")
    }

    // ~/.local/bin is exported from .zshrc, which only interactive shells
    // read, so whether quickshell inherits it depends on how the session
    // was started. Prepending it here costs nothing and removes that
    // dependency — hypr/modules/env.lua does the same for keybinds.
    function rack(sub, opts) {
        root.run('PATH="$HOME/.local/bin:$PATH" rack ' + sub, opts)
    }
}
