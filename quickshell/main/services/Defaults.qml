pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The default apps — which terminal, editor, browser and file manager
// each role resolves to — as `relay default` reports them. The answers
// are not this file's: the candidates, the order they resolve in and how
// each app is launched live in hypr/modules/defaults.lua, which Hyprland
// reads for the binds and relay reads for everyone else (see
// docs/adr/0001). This asks relay, and nothing here knows any app by name.
Singleton {
    id: root

    // Every role by name, as `relay default list --json` gives it:
    //
    //   { role, source, name, label, command, installed,
    //     candidates: [{ name, label, installed, via, default }] }
    //
    // `source` is "set" (a candidate the user picked), "custom" (a command
    // they wrote, with no name or label) or "fallback" (nothing set; the
    // first candidate installed here).
    //
    // null until relay has answered once. A menu that drew an empty level
    // before then would read as "you have no terminals installed".
    property var roles: null

    // Why the last ask failed, or "" — lua missing, relay not installed.
    // Set once the ask is over, so `roles` stays null and this is the
    // answer instead.
    property string error: ""

    // Asked per call, not once per shell run: a default can be changed by
    // anything on the machine, and apps come and go with `pacman -S`.
    function refresh() {
        listProc.running = false
        listProc.running = true
    }

    // Make a candidate the role's default. relay also points the XDG
    // handler at it and reloads Hyprland, so SUPER+RETURN follows — which
    // costs zen mode its saved chrome (hypr/modules/binds/zen.lua drops
    // the snapshot on config.reloaded), the one visible side effect.
    function set(role, candidate) {
        setProc.role = role
        setProc.candidate = candidate
        setProc.command = root.relay(["default", "set", role, candidate])
        setProc.running = false
        setProc.running = true
    }

    // A page as a window of its own, in the default browser when it can do
    // that and in an ordinary tab when it can't. Detached, for the reason
    // services/Terminal.qml gives: uwsm-app stays until the browser exits,
    // and a reused Process would take the first window with it.
    function openWebApp(url) {
        Quickshell.execDetached(root.relay(["default", "exec", "browser", "--app", url]))
    }

    // An argv that runs relay with these arguments. ~/.local/bin is
    // exported from .zshrc, which only interactive shells read, so whether
    // quickshell inherits it depends on how the session was started;
    // prepending it costs nothing and removes that dependency, as
    // hypr/modules/env.lua does for keybinds.
    function relay(args) {
        return ["sh", "-c", 'PATH="$HOME/.local/bin:$PATH" exec relay "$@"', "sh"].concat(args)
    }

    readonly property Process listProc: Process {
        command: root.relay(["default", "list", "--json"])
        stdout: StdioCollector {
            id: listOut
            onStreamFinished: root._publish(listOut.text)
        }
        stderr: StdioCollector {
            id: listErr
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) root.error = root._reason(listErr.text, exitCode)
        }
    }

    // Only a genuinely different answer is published. The Conf menu
    // builds its whole tree from this, and a fresh object on every open
    // would tear down and rebuild every visible row a few ms into the open
    // animation, for an answer that is almost always last time's.
    function _publish(text) {
        let list
        try {
            list = JSON.parse(text)
        } catch (e) {
            return
        }

        const byRole = ({})
        for (const role of list) byRole[role.role] = role
        root.error = ""
        if (JSON.stringify(byRole) !== JSON.stringify(root.roles)) root.roles = byRole
    }

    // relay's last complaint, without rig's level column in front of it.
    function _reason(stderr, exitCode) {
        const lines = stderr.trim().split("\n").filter(l => l !== "")
        if (lines.length === 0) return "relay default exited " + exitCode
        return lines[lines.length - 1].replace(/^(error|warn|fatal)\s+/, "")
    }

    readonly property Process setProc: Process {
        property string role: ""
        property string candidate: ""
        stderr: StdioCollector {
            id: setErr
        }
        onExited: (exitCode, exitStatus) => {
            const role = setProc.role.replace("-", " ")
            if (exitCode === 0) {
                root.refresh()
                const found = root._candidate(setProc.role, setProc.candidate)
                Notifications.post((found ? found.label : setProc.candidate)
                    + " is now the default " + role, "", "normal", "Conf", "")
            } else {
                Notifications.post("Couldn't set the default " + role,
                    root._reason(setErr.text, exitCode), "critical", "Conf", "")
            }
        }
    }

    function _candidate(role, name) {
        const found = root.roles ? root.roles[role] : null
        if (!found) return null
        return found.candidates.find(c => c.name === name) || null
    }
}
