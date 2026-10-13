pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// "Is Caps Lock currently on." Hyprland has no rawEvent for this —
// confirmed live the same way Keyboard.qml confirmed "activelayout":
// listened on the raw event socket (.socket2.sock) while physically
// toggling Caps Lock on and off, twice, with a plain window-title
// spinner as the only other traffic on the socket — nothing capslock-
// related ever arrived, unlike "activelayout" which fires reliably on
// a layout switch. So this polls `hyprctl devices -j` instead, the
// same escape hatch Keyboard.qml already uses for layout count/initial
// state, and reads the main keyboard's own `capsLock` field.
Singleton {
    id: root

    property bool active: false

    function _poll() {
        pollProc.running = false
        pollProc.running = true
    }

    Process {
        id: pollProc
        command: ["sh", "-c", "hyprctl devices -j 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    const kbs = parsed.keyboards || []
                    const kb = kbs.find(k => k.main) || kbs[0]
                    if (kb) root.active = !!kb.capsLock
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: root._poll()

    // 200ms keeps the OSD feeling immediate without spawning hyprctl
    // often enough to matter — devices -j is a tiny local IPC call.
    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: root._poll()
    }
}
