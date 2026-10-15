pragma Singleton

import Quickshell
import Quickshell.Hyprland
import QtQuick

// The window drag, as hypr/modules/snap.lua reports it on socket2:
// `custom>>snap drag X Y` while it lasts (global logical coordinates) and
// `custom>>snap drop ADDRESS` on release.
Singleton {
    id: root

    property bool active: false
    property real x: 0
    property real y: 0

    signal moved()
    signal dropped(string address)

    // Puts a window into a zone (fractions of the screen's tiling area).
    function place(address, monitor, zone) {
        Quickshell.execDetached(["hyprctl", "eval",
            `snap_place("${address}", "${monitor}", ${zone[0]}, ${zone[1]}, ${zone[2]}, ${zone[3]})`])
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "custom")
                return
            const parts = event.data.split(" ")
            if (parts[0] !== "snap")
                return
            if (parts[1] === "drag") {
                root.x = Number(parts[2])
                root.y = Number(parts[3])
                root.active = true
                root.moved()
            } else if (parts[1] === "drop") {
                root.active = false
                root.dropped(parts[2])
            }
        }
    }
}
