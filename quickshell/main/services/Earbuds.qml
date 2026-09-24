pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The battery of Nothing earbuds, part by part: left, right and the case.
// UPower already knows the earbuds, but as one number (the Bluetooth
// headset profile's, which is whichever bud it picks); the three come from
// Nothing's own protocol, which `relay earbuds watch` (relay/lib/earbuds.py)
// speaks. It prints the whole state as one JSON line on every change, so
// this keeps the last line and nothing else.
//
// Each of left/right/case is null until the earbuds have reported it, or
// { level, charging, stale }. The case only reports while a bud sits in it
// with the lid open; `stale` is a reading it gave earlier and has not
// repeated since.
//
// An optional feature (services/Features.qml): the watcher runs only while
// it is on, for the same reason Voxtype.qml's follower does — a singleton
// outlives whatever built it. Exit 127 (python-dbus or python-gobject
// missing, or relay itself) and 3 (another watcher has the earbuds) are the
// end of it; anything else (bluetoothd restarting) is retried.
Singleton {
    id: root

    readonly property bool wanted: Features.on("earbuds")
    onWantedChanged: {
        watch.running = root.wanted
        if (!root.wanted) root._apply({ connected: false })
    }

    property bool connected: false
    property string name: ""
    property var left: null
    property var right: null
    property var caseBattery: null

    // Something to draw: connected, and at least one reading in.
    readonly property bool ready: root.connected
                                  && (root.left !== null || root.right !== null || root.caseBattery !== null)

    // The bud that runs out first, which is the one number the bar shows.
    readonly property var lowestBud: {
        const buds = [root.left, root.right].filter(b => b !== null)
        if (buds.length === 0) return null
        return buds.reduce((a, b) => b.level < a.level ? b : a)
    }

    // The Bluetooth address, for services/Battery.qml to drop UPower's
    // single-number row for the same earbuds while these three are shown.
    property string address: ""

    function _apply(state) {
        root.connected = !!state.connected
        root.name = state.name || ""
        root.address = state.address || ""
        root.left = state.left || null
        root.right = state.right || null
        root.caseBattery = state["case"] || null
    }

    Process {
        id: watch
        running: root.wanted
        command: ["sh", "-c", "command -v relay >/dev/null || exit 127; exec relay earbuds watch"]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    root._apply(JSON.parse(line))
                } catch (e) {
                    console.warn("Earbuds: unreadable line from relay earbuds watch:", line)
                }
            }
        }
        onExited: (exitCode) => {
            root._apply({ connected: false })
            if (exitCode !== 127 && exitCode !== 3 && root.wanted) retry.start()
        }
    }

    Timer {
        id: retry
        interval: 5000
        onTriggered: watch.running = root.wanted
    }
}
