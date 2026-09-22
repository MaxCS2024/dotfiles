pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Wraps `rfkill` to block/unblock every wireless radio (Wi-Fi,
// Bluetooth, etc.) at once — unlike Bt.qml's Bluetooth module or
// Network's NetworkManager D-Bus binding, Quickshell has no native
// binding for this, so this shells out same as Network.qml does for
// nmcli-only operations.
Singleton {
    id: root

    property bool enabled: false

    function refresh() {
        refreshProc.running = false
        refreshProc.running = true
    }

    Component.onCompleted: root.refresh()

    Process {
        id: refreshProc
        command: ["rfkill", "--output", "SOFT", "--noheadings"]
        stdout: StdioCollector {
            onStreamFinished: {
                // "on" only when every listed radio is soft-blocked —
                // one radio left on (e.g. Wi-Fi flipped back on by
                // hand) means airplane mode isn't really in effect.
                const lines = text.split("\n").map(l => l.trim()).filter(l => l !== "")
                root.enabled = lines.length > 0 && lines.every(l => l === "blocked")
            }
        }
    }

    Process {
        id: toggleProc
        onExited: root.refresh()
    }

    function setEnabled(on) {
        toggleProc.command = ["rfkill", on ? "block" : "unblock", "all"]
        toggleProc.running = false
        toggleProc.running = true
    }

    function toggle() { root.setEnabled(!root.enabled) }
}
