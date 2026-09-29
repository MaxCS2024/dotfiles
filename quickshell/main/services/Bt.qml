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

    // The two halves network/BluetoothTab.qml lists. `bonded` counts as
    // paired: a device paired from another OS install and carried over in
    // /var/lib/bluetooth can report bonded without paired.
    readonly property var pairedDevices: root.devices.filter(d => d.paired || d.bonded)

    // Everything else the adapter has heard, minus devices with no name.
    // `deviceName` is BlueZ's Name, empty until the device says what it is;
    // `name` is the Alias, which falls back to the MAC address. A scan in a
    // flat block turns up dozens of nameless BLE advertisers (TVs, trackers,
    // other people's phones), and a list of MAC addresses is not something
    // you can pick from.
    readonly property var nearbyDevices: root.devices.filter(d => !d.paired && !d.bonded && d.deviceName !== "")

    // ── Discovery ────────────────────────────────────────
    // Only while asked for, and never for long: an inquiry scan shares the
    // radio with whatever is streaming, and A2DP audio stutters under it.
    // Timed out here rather than left to the caller, so a panel that goes
    // away without saying so can't leave the adapter scanning.
    readonly property bool discovering: root.available && root.adapter.discovering

    function setDiscovering(on) {
        if (!root.available || !root.powered) return
        if (on) discoveryTimeout.restart()
        else discoveryTimeout.stop()
        if (root.adapter.discovering !== on) root.adapter.discovering = on
    }

    function toggleDiscovering() {
        root.setDiscovering(!root.discovering)
    }

    Timer {
        id: discoveryTimeout
        interval: 30000
        onTriggered: root.setDiscovering(false)
    }

    // ── Pairing ──────────────────────────────────────────
    // Any code the pairing needs — a passkey to type on a keyboard, six
    // digits to compare with a phone — is asked for by the agent
    // (services/BtAgent.qml) in network/BluetoothPrompt.qml, not here.
    // Without the agent BlueZ pairs "Just Works" devices only.
    //
    // Trusted first so the device may reconnect on its own later, discovery
    // off because BlueZ pairs more reliably without an inquiry running
    // alongside, and connected once the bond lands, because Pair() on its
    // own leaves an audio device paired but silent.
    property var pairingDevice: null

    function pair(device) {
        root.setDiscovering(false)
        root.failedDevice = null
        root.pairingDevice = device
        device.trusted = true
        device.pair()
    }

    Connections {
        target: root.pairingDevice
        ignoreUnknownSignals: true

        function onPairedChanged() {
            if (!root.pairingDevice.paired) return
            root.pairingDevice.connect()
            root.pairingDevice = null
        }

        // Pairing ended without a bond: refused, timed out, or cancelled.
        // Checked a turn later: the two properties arrive as separate
        // D-Bus changes, and pairing can drop a moment before paired rises.
        function onPairingChanged() {
            Qt.callLater(root._settlePairing)
        }
    }

    // The last device that failed to pair, so its row can say so instead
    // of quietly going back to "Pair". Cleared on the next attempt.
    property var failedDevice: null

    function _settlePairing() {
        const d = root.pairingDevice
        if (d && !d.pairing && !d.paired) {
            root.failedDevice = d
            root.pairingDevice = null
        }
    }

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
