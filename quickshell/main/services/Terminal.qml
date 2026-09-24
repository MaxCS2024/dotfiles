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

    // Which terminal is whichever one the terminal role resolves to — the
    // one SUPER+RETURN opens — and how to hand it an app-id, a title and a
    // command is that terminal's business, not this file's: kitty takes
    // no -e, ghostty wants --class. `relay default exec terminal` knows
    // both (hypr/modules/defaults.lua), and says so as a notification when
    // it can't open anything, since nobody reads a detached process's
    // stderr.
    function run(cmd, opts) {
        const o = opts || ({})
        const hold = o.hold !== false
        const floating = o.floating !== false
        const args = ["default", "exec", "terminal"]
        if (floating) args.push("--app-id", o.appId || Theme.floatAppId)
        if (o.title) args.push("--title", o.title)
        args.push("--", cmd + (hold ? root.holdTail : ""))

        // Detached, not a Process of ours: uwsm-app doesn't hand the
        // terminal off and return, it stays until the window closes
        // (`uwsm-app -- sleep 3` takes 3s). A reused Process would kill
        // the last window on every new call — the btop you opened from the
        // launcher, the moment you ran an update.
        Quickshell.execDetached(Defaults.relay(args))
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
