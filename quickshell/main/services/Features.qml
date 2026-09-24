pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Which optional features this machine has turned on — dictation, the
// weather module — as chosen with `rack features` (rack/lib/features.sh,
// what each one is made of is rack/features.json). Everything that belongs
// to a feature asks `Features.on("<name>")` before it is built: shell.qml
// for the dictation pill, bar/Bar.qml for bar modules (via
// bar/Modules.qml's `feature` map).
//
// The file is ~/.config/rack/features.conf, one "name on|off" per line;
// Hyprland reads the same one for its binds (hypr/modules/features.lua).
// A feature with no line, or no file at all, is on, so a machine that has
// never run the picker loses nothing.
//
// rack writes the file by replacing it, and a watch on a path that did not
// exist when it was set up never fires, so after every change rack also
// calls the `features` IPC target below rather than trusting the watch.
// The watch stays for a hand edit.
Singleton {
    id: root

    // name -> "on" | "off", as the file says.
    property var _states: ({})

    function on(name) { return root._states[name] !== "off" }

    function _parse(text) {
        const states = {}
        for (const line of text.split("\n")) {
            const m = line.match(/^(\S+)\s+(\S+)/)
            if (m && m[1][0] !== "#") states[m[1]] = m[2]
        }
        root._states = states
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/rack/features.conf"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._parse(text())
        onLoadFailed: root._states = ({})
    }

    IpcHandler {
        target: "features"
        function reload(): string { file.reload(); return "ok" }
    }
}
