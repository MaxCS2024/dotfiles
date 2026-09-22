pragma Singleton
import Quickshell
import Quickshell.Bluetooth
import QtQuick

// Named "Bt" rather than "Bluetooth" on purpose — Quickshell.Bluetooth
// itself exposes a singleton also called Bluetooth, and both would
// otherwise fight over the same identifier in any file that imports
// this module.
Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: root.adapter !== null && root.adapter !== undefined
    readonly property bool powered: root.available ? root.adapter.enabled : false

    // All devices known to the default adapter (paired and/or currently
    // visible), not just ones presently connected — each device carries
    // its own connected/paired state for the UI to read directly.
    readonly property var devices: root.available ? root.adapter.devices.values : []

    readonly property var connectedDevices: root.devices.filter(d => d.connected)
    readonly property bool anyConnected: root.connectedDevices.length > 0

    function setPowered(on) {
        if (root.available) root.adapter.enabled = on
    }

    function togglePowered() {
        root.setPowered(!root.powered)
    }

    function toggleConnected(device) {
        device.connected = !device.connected
    }

    function forget(device) {
        device.forget()
    }
}
