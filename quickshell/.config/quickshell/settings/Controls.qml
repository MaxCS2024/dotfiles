pragma Singleton

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower
import QtQml
import QtQuick

// Network, Wi-Fi, Bluetooth, the battery and the power profile for the
// settings window's pages: the dynamic-island's Controls.qml, cut down
// to what the window uses when it was split out (2026-10-13). The
// island's notices, OSD, shortcuts and IPC targets stayed behind.
Singleton {
    id: root

    // ── Network ──
    function device(kind) {
        return Networking.devices.values.find(d => d.type === kind) ?? null
    }
    // Wired wins over Wi-Fi when both are up.
    readonly property var activeDevice: {
        const wired = device(DeviceType.Wired)
        const wifi = device(DeviceType.Wifi)
        return wired && wired.connected ? wired : wifi && wifi.connected ? wifi : null
    }
    readonly property string networkType: !activeDevice ? "none"
        : activeDevice.type === DeviceType.Wired ? "ethernet" : "wifi"
    readonly property string ssid: {
        const wifi = device(DeviceType.Wifi)
        const net = wifi ? wifi.networks.values.find(n => n.connected) : null
        return net ? net.name : ""
    }
    // Glyphs: ethernet, Wi-Fi, off.
    readonly property string networkIcon: networkType === "ethernet" ? "\u{f0200}"
        : networkType === "wifi" ? "\uf1eb" : "\u{f05a9}"

    // ── Wi-Fi page ──
    // The networks in range for the island's Wi-Fi page, as
    // Quickshell.Networking objects: the connected one first, then saved
    // ones, then by signal. Hidden SSIDs (no name) are left out.
    readonly property var wifiDevice: device(DeviceType.Wifi)
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property var wifiNetworks: wifiDevice
        ? [...wifiDevice.networks.values]
            .filter(n => n.name !== "")
            .sort((a, b) => a.connected !== b.connected ? (a.connected ? -1 : 1)
                : a.known !== b.known ? (a.known ? -1 : 1)
                : wifiLevel(b) - wifiLevel(a))
        : []

    // Signal in four steps, as the row icon shows it. Sorted on the step,
    // not the raw strength, so the rows don't reshuffle on every scan.
    function wifiLevel(net) {
        return Math.max(1, Math.min(4, Math.ceil(net.signalStrength * 4)))
    }

    function setWifi(on) {
        Networking.wifiEnabled = on
    }

    // Set by the island while the Wi-Fi page is open. The scanner only
    // fills `networks` while it is on, and is turned back off after.
    property bool wifiScan: false
    // The same for the settings window's Network section, kept apart so
    // closing one doesn't stop the other's scan.
    property bool windowWifiScan: false
    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: true
        when: root.wifiDevice !== null && (root.wifiScan || root.windowWifiScan)
    }

    // Whether a network has to be given a password before connecting:
    // secured and never joined. Open, OWE and unknown ones are just tried.
    function needsPassword(net) {
        return !net.known && net.security !== WifiSecurityType.Open
            && net.security !== WifiSecurityType.Owe
            && net.security !== WifiSecurityType.Unknown
    }

    // A connect is tried as is; NetworkManager answering NoSecrets (a
    // saved network whose password changed) asks the page for one through
    // `wifiPasswordNeeded`. Any other failure marks the row "Failed".
    property var pendingNetwork: null
    property var failedNetwork: null
    signal wifiPasswordNeeded(var net)

    function joinWifi(net, psk) {
        failedNetwork = null
        pendingNetwork = net
        if (psk === undefined)
            net.connect()
        else
            net.connectWithPsk(psk)
    }

    Connections {
        target: root.pendingNetwork
        ignoreUnknownSignals: true

        function onConnectionFailed(reason) {
            const net = root.pendingNetwork
            root.pendingNetwork = null
            if (reason === ConnectionFailReason.NoSecrets)
                root.wifiPasswordNeeded(net)
            else
                root.failedNetwork = net
        }

        function onConnectedChanged() {
            if (root.pendingNetwork && root.pendingNetwork.connected)
                root.pendingNetwork = null
        }
    }

    // md-wifi_strength_1–4, with a lock when the network is secured.
    function wifiIcon(net) {
        const level = wifiLevel(net)
        const open = net.security === WifiSecurityType.Open || net.security === WifiSecurityType.Owe
        const glyphs = open ? ["\u{f091f}", "\u{f0922}", "\u{f0925}", "\u{f0928}"]
            : ["\u{f0921}", "\u{f0924}", "\u{f0927}", "\u{f092a}"]
        return glyphs[level - 1]
    }

    // ── Bluetooth ──
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool bluetoothOn: adapter ? adapter.enabled : false
    readonly property bool bluetoothConnected: bluetoothOn
        && Bluetooth.devices.values.some(d => d.connected)
    // Glyphs: off, on, connected.
    readonly property string bluetoothIcon: !bluetoothOn ? "\u{f00b2}"
        : bluetoothConnected ? "\u{f00b1}" : "\u{f00af}"

    function setBluetooth(on) {
        if (adapter)
            adapter.enabled = on
    }

    // ── Bluetooth page ──
    // Paired devices (the connected ones first), then the others the
    // adapter has heard. `bonded` counts as paired: a device carried
    // over from another install can report
    // bonded without paired. Nameless BLE advertisers are left out; a MAC
    // address is nothing to pick from.
    readonly property var bluetoothDevices: adapter
        ? [...adapter.devices.values]
            .filter(d => d.paired || d.bonded || d.deviceName !== "")
            .sort((a, b) => a.connected !== b.connected ? (a.connected ? -1 : 1)
                : isPaired(a) !== isPaired(b) ? (isPaired(a) ? -1 : 1) : 0)
        : []

    function isPaired(d) {
        return d.paired || d.bonded
    }

    // Set by the island while the Bluetooth page is open. Discovery shares
    // the radio with whatever is streaming (A2DP stutters under it), so it
    // runs only then, and never for more than 30 seconds.
    property bool bluetoothScan: false
    // The same for the settings window's Bluetooth section.
    property bool windowBluetoothScan: false
    readonly property bool anyBluetoothScan: bluetoothScan || windowBluetoothScan
    onAnyBluetoothScanChanged: setDiscovering(anyBluetoothScan)
    onBluetoothOnChanged: if (bluetoothOn && anyBluetoothScan) setDiscovering(true)

    function setDiscovering(on) {
        if (!adapter || !adapter.enabled)
            return
        if (on)
            discoveryTimeout.restart()
        else
            discoveryTimeout.stop()
        if (adapter.discovering !== on)
            adapter.discovering = on
    }

    Timer {
        id: discoveryTimeout
        interval: 30000
        onTriggered: root.setDiscovering(false)
    }

    // A click on a device: a paired one connects or disconnects, a new one
    // pairs. Pairing: trusted first so
    // it can reconnect on its own, discovery off since BlueZ pairs more
    // reliably without it, and connected once the bond lands, because
    // Pair() alone leaves headphones paired but silent. The island runs no
    // pairing agent; the settings window runs one (bt-agent.py) while its
    // Bluetooth section is open, so devices that need a code pair there.
    property var pairingDevice: null
    property var failedDevice: null

    function useDevice(d) {
        failedDevice = null
        if (isPaired(d)) {
            d.connected = !d.connected
            return
        }
        setDiscovering(false)
        pairingDevice = d
        d.trusted = true
        d.pair()
    }

    Connections {
        target: root.pairingDevice
        ignoreUnknownSignals: true

        function onPairedChanged() {
            if (!root.pairingDevice.paired)
                return
            if (!root.pairingDevice.connected)
                root.pairingDevice.connect()
            root.pairingDevice = null
        }

        // Checked a turn later: pairing can drop a moment before paired
        // rises, as two separate D-Bus changes.
        function onPairingChanged() {
            Qt.callLater(root.settlePairing)
        }
    }

    function settlePairing() {
        const d = pairingDevice
        if (d && !d.pairing && !d.paired) {
            failedDevice = d
            pairingDevice = null
        }
    }

    // A glyph per BlueZ device icon name; anything else gets the rune.
    function deviceIcon(d) {
        const icons = {
            "audio-headset": "\u{f02cb}",
            "audio-headphones": "\u{f02cb}",
            "audio-card": "\u{f04c3}",
            "input-keyboard": "\u{f030c}",
            "input-mouse": "\u{f037d}",
            "input-gaming": "\u{f0297}",
            "phone": "\u{f011c}",
            "computer": "\u{f0322}",
            "video-display": "\u{f0379}"
        }
        return icons[d.icon] ?? "\u{f00af}"
    }

    // ── Battery ──
    // UPower's combined device, so both of the T480's packs count as one.
    readonly property var battery: UPower.displayDevice
    readonly property real batteryPercent: battery && battery.isPresent ? battery.percentage * 100 : -1
    readonly property bool charging: battery ? battery.state === UPowerDeviceState.Charging : false

    // Battery glyphs: a bolt while
    // charging, otherwise one step per 10%.
    readonly property string batteryIcon: {
        if (charging)
            return "\u{f0084}"
        const steps = ["\u{f008e}", "\u{f007a}", "\u{f007b}", "\u{f007c}", "\u{f007d}",
            "\u{f007e}", "\u{f007f}", "\u{f0080}", "\u{f0081}", "\u{f0082}", "\u{f0079}"]
        return steps[Math.max(0, Math.min(10, Math.floor(batteryPercent / 10)))]
    }

    // ── Power profile ──
    // power-profiles-daemon through UPower's PowerProfiles, least power to
    // most; Performance only where the hardware has it. PowerProfiles has
    // no "not running" state (it reads a default and setting goes nowhere),
    // so `powerprofilesctl get` is asked once.
    readonly property var profiles: PowerProfiles.hasPerformanceProfile
        ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
        : [PowerProfile.PowerSaver, PowerProfile.Balanced]
    property bool profilesAvailable: false

    Process {
        running: true
        command: ["powerprofilesctl", "get"]
        onExited: code => root.profilesAvailable = code === 0
    }

    function profileLabel(p) {
        return p === PowerProfile.PowerSaver ? "Power saver"
            : p === PowerProfile.Performance ? "Performance" : "Balanced"
    }

    // Marks: a leaf, a balance, a speedometer.
    function profileIcon(p) {
        return p === PowerProfile.PowerSaver ? "\u{f032a}"
            : p === PowerProfile.Performance ? "\u{f04c5}" : "\u{f05d1}"
    }

    function setProfile(p) {
        PowerProfiles.profile = p
    }
}
