pragma Singleton
import Quickshell
import Quickshell.Io
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
//
// `hold` is what keeps the shell alive on a `read` after the command
// exits — a terminal that vanishes the instant pacman finishes takes the
// summary, and any error, with it. Turn it off for anything you'd quit
// yourself.
Singleton {
    id: root

    // One Process, reused. The spawn returns as soon as the launcher has
    // handed the terminal to the session (uwsm-app runs it as its own
    // unit), so a second call never kills the first window.
    readonly property Process proc: Process {}

    readonly property string holdTail:
        '; printf "\\n\\033[2m— finished (exit %s) · press Enter to close —\\033[0m\\n" "$?"'
        + '; read -r _'

    function run(cmd, opts) {
        const o = opts || ({})
        const hold = o.hold !== false
        const floating = o.floating !== false
        const appId = o.appId || Theme.floatAppId

        let argv = [Theme.appLauncherPrefix, "--", Theme.terminal]
        if (floating) argv.push(Theme.terminalAppIdArg + appId)
        if (o.title) argv.push("--title=" + o.title)
        argv = argv.concat(["-e", "sh", "-c", cmd + (hold ? root.holdTail : "")])

        root.proc.command = argv
        root.proc.running = false
        root.proc.running = true
    }

    // ~/.local/bin is exported from .zshrc, which only interactive shells
    // read, so whether quickshell inherits it depends on how the session
    // was started. Prepending it here costs nothing and removes that
    // dependency — hypr/modules/env.lua does the same for keybinds.
    function rack(sub, opts) {
        root.run('PATH="$HOME/.local/bin:$PATH" rack ' + sub, opts)
    }
}
