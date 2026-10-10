pragma Singleton

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQml
import QtQuick

// Volume, screen brightness, network status, Bluetooth and battery for
// the island's settings panel and notices, the Wi-Fi networks and
// Bluetooth devices for its two list pages, and the power profile for
// its battery page. Volume and
// brightness are 0–1. Same sources as the main bar: the default PipeWire
// sink, the first /sys/class/backlight device (written through
// brightnessctl) and Quickshell.Networking.
Singleton {
    id: root

    // ── Change signal for the OSD face ──
    // `changed(kind, value)` fires when the volume (incl. mute) or the
    // brightness changes, from anywhere, with the new 0–1 value. Quiet for
    // the first 2 seconds, while the first readings arrive. The volume and
    // brightness keys also fire it through the global shortcuts below, so
    // a press at 100% (or 0%), which changes nothing, still answers.
    signal changed(string kind, real value)
    property bool armed: false
    Timer {
        running: true
        interval: 2000
        onTriggered: root.armed = true
    }

    // Fired by hypr/modules/binds/media.lua on every volume or brightness
    // key press, alongside the wpctl/brightnessctl call.
    GlobalShortcut {
        appid: "quickshell"
        name: "island-osd-volume"
        description: "Show the dynamic island's volume face"
        onPressed: root.changed("volume", root.shownVolume)
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "island-osd-brightness"
        description: "Show the dynamic island's brightness face"
        onPressed: root.changed("brightness", root.brightness)
    }

    // ── Main bar visibility ──
    // The island hides and shows with the main bar (SUPER+ALT+SPACE, or any
    // other way the bar is toggled). The main bar's services/Panels.qml calls
    // `qs -c dynamic-island ipc call island setBarVisible <bool>` whenever
    // its barVisible changes; at startup the island asks it once.
    property bool mainBarVisible: true

    IpcHandler {
        target: "island"
        function setBarVisible(visible: bool): void { root.mainBarVisible = visible }
    }

    Process {
        running: true
        command: ["qs", "-c", "main", "ipc", "call", "bar", "state"]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() === "off") root.mainBarVisible = false
        }
    }

    // ── Main bar on screen ──
    // Whether main's bar surface ("quickshell:bar", one per monitor) is
    // mapped. While it is, the bar reserves the top strip and the island
    // sits over its centre; otherwise the island reserves its own (see
    // Island.qml). Counted from Hyprland's openlayer/closelayer events,
    // after one `hyprctl layers` at startup, so nothing is polled.
    property int mainBarLayers: 0
    readonly property bool mainBarUp: mainBarLayers > 0

    Process {
        running: true
        command: ["sh", "-c", "hyprctl layers -j | grep -c '\"namespace\": \"quickshell:bar\"'"]
        stdout: StdioCollector {
            onStreamFinished: root.mainBarLayers = parseInt(text.trim()) || 0
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.data !== "quickshell:bar")
                return
            if (event.name === "openlayer")
                root.mainBarLayers++
            else if (event.name === "closelayer")
                root.mainBarLayers = Math.max(0, root.mainBarLayers - 1)
        }
    }

    // ── Volume ──
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    readonly property real volume: sink && sink.audio ? Math.min(1, sink.audio.volume) : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    // Muted reads as 0, as on the settings slider.
    readonly property real shownVolume: muted ? 0 : volume
    // Speaker: off when muted or at 0, else low / medium / high.
    readonly property string volumeIcon: shownVolume === 0 ? "\u{f0581}"
        : shownVolume < 0.34 ? "\u{f057f}"
        : shownVolume < 0.67 ? "\u{f0580}" : "\u{f057e}"
    onShownVolumeChanged: if (armed) changed("volume", shownVolume)

    function setVolume(v) {
        if (!sink || !sink.audio)
            return
        sink.audio.volume = Math.max(0, Math.min(1, v))
        if (v > 0 && sink.audio.muted)
            sink.audio.muted = false
    }

    function toggleMute() {
        if (sink && sink.audio)
            sink.audio.muted = !sink.audio.muted
    }

    // ── Brightness ──
    property string backlight: ""
    property int maxBrightness: 0
    property real brightness: 0
    readonly property bool hasBacklight: backlight !== "" && maxBrightness > 0
    readonly property string brightnessIcon: "\u{f00e0}"

    Process {
        running: true
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -e \"$d\" ] && { echo \"$d\"; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: root.backlight = text.trim()
        }
    }

    FileView {
        path: root.backlight !== "" ? root.backlight + "/max_brightness" : ""
        onLoaded: root.maxBrightness = parseInt(text().trim()) || 0
    }

    // sysfs doesn't notify reliably, so it is re-read twice a second, and
    // every 50ms for 1.5 seconds after a change so the OSD keeps up with a
    // held brightness key.
    FileView {
        id: brightnessFile
        path: root.backlight !== "" ? root.backlight + "/brightness" : ""
        onLoaded: {
            if (root.maxBrightness <= 0)
                return
            const v = Math.min(1, parseInt(text().trim()) / root.maxBrightness)
            if (Math.abs(v - root.brightness) < 0.001)
                return
            root.brightness = v
            root.pollFast()
            if (root.armed)
                root.changed("brightness", v)
        }
    }

    property bool fastPoll: false
    function pollFast() {
        fastPoll = true
        fastPollEnd.restart()
    }

    Timer {
        id: fastPollEnd
        interval: 1500
        onTriggered: root.fastPoll = false
    }

    Timer {
        interval: root.fastPoll ? 50 : 500
        running: root.backlight !== ""
        repeat: true
        onTriggered: brightnessFile.reload()
    }

    // A slider drag asks for many values a second. Only one brightnessctl
    // runs at a time; the latest value asked for meanwhile goes next.
    property int pendingPercent: -1

    function setBrightness(v) {
        if (!hasBacklight)
            return
        brightness = Math.max(0, Math.min(1, v))
        // Never fully dark: 1% is the floor.
        pendingPercent = Math.max(1, Math.round(brightness * 100))
        if (!brightnessProc.running)
            runPending()
    }

    function runPending() {
        if (pendingPercent < 0)
            return
        brightnessProc.command = ["brightnessctl", "-q", "set", pendingPercent + "%"]
        pendingPercent = -1
        brightnessProc.running = true
    }

    Process {
        id: brightnessProc
        onExited: root.runPending()
    }

    // ── Network ──
    function device(kind) {
        return Networking.devices.values.find(d => d.type === kind) ?? null
    }
    // Wired wins over Wi-Fi when both are up, as in the main bar.
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
    // The main bar's glyphs (services/Network.qml): ethernet, Wi-Fi, off.
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
    // The main bar's glyphs (bar/BluetoothButton.qml): off, on, connected.
    readonly property string bluetoothIcon: !bluetoothOn ? "\u{f00b2}"
        : bluetoothConnected ? "\u{f00b1}" : "\u{f00af}"

    function setBluetooth(on) {
        if (adapter)
            adapter.enabled = on
    }

    // ── Bluetooth page ──
    // Paired devices (the connected ones first), then the others the
    // adapter has heard. `bonded` counts as paired, as in the
    // main bar: a device carried over from another install can report
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
    // pairs. Pairing is the main bar's (services/Bt.qml): trusted first so
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

    // The main bar's battery glyphs (services/Battery.qml): a bolt while
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
    // so `powerprofilesctl get` is asked once, as the main bar does.
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

    // The main bar's marks: a leaf, a balance, a speedometer.
    function profileIcon(p) {
        return p === PowerProfile.PowerSaver ? "\u{f032a}"
            : p === PowerProfile.Performance ? "\u{f04c5}" : "\u{f05d1}"
    }

    function setProfile(p) {
        PowerProfiles.profile = p
    }

    // ── Battery notices ──
    // `batteryNotice(kind)` fires "charging" when the charger is plugged
    // in, and "low" when the battery, on battery power, drops below 20%
    // and again below 10%. Keyed off UPower's onBattery rather than the
    // charging state, which flips back and forth around the charge
    // thresholds. Quiet for the first 2 seconds, like `changed`.
    // ── Network and Bluetooth notices ──
    // `notice(icon, text)` for the island's pill (AGENTS.md, Notices): a
    // network coming up, failing or dropping, a Bluetooth device
    // connecting or disconnecting. Quiet for the first 2 seconds.
    signal notice(string icon, string text)

    // Connected / Wi-Fi lost, from the connected network's name. Losing it
    // waits 3 seconds: switching networks passes through no network, and
    // a wired connection taking over isn't a loss. Turning Wi-Fi off
    // isn't one either.
    property string lastSsid: ""
    onSsidChanged: {
        const before = lastSsid
        lastSsid = ssid
        if (!armed)
            return
        if (ssid !== "") {
            wifiLost.stop()
            notice("\uf1eb", "Connected – " + ssid)
        } else if (before !== "" && wifiOn) {
            wifiLost.restart()
        }
    }

    Timer {
        id: wifiLost
        interval: 3000
        onTriggered: if (root.ssid === "" && root.wifiOn && root.networkType !== "ethernet")
            root.notice("\u{f05aa}", "Wi-Fi lost")
    }

    readonly property bool wiredUp: networkType === "ethernet"
    onWiredUpChanged: if (armed && wiredUp) notice("\u{f0200}", "Connected – Ethernet")

    // A network that fails to connect, whoever asked: NetworkManager on its
    // own, the island's page or the settings window. Not for a missing
    // password, which the island's Wi-Fi page asks for instead.
    Instantiator {
        model: root.wifiDevice ? root.wifiDevice.networks.values : []
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            function onConnectionFailed(reason) {
                if (root.armed && reason !== ConnectionFailReason.NoSecrets)
                    root.notice("\u{f05aa}", "Couldn't connect – " + modelData.name)
            }
        }
    }

    // A Bluetooth device connecting ("Nothing Ear (3) connected – 80%",
    // with the battery when it reports one) or disconnecting. Not while
    // the adapter is off: switching it off disconnects everything at once.
    Instantiator {
        model: Bluetooth.devices.values
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectedChanged() {
                if (!root.armed || !root.bluetoothOn)
                    return
                const d = modelData
                root.notice(root.deviceIcon(d), d.connected
                    ? d.name + " connected" + (d.batteryAvailable ? " – " + Math.round(d.battery * 100) + "%" : "")
                    : d.name + " disconnected")
            }
        }
    }

    // ── Keyboard layout ──
    // `layoutNotice(name)` when a keyboard's layout changes (Alt+Shift, or
    // any other way), with XKB's name for it ("English (US)"). Every
    // keyboard device keeps its own layout, so each is tracked on its own,
    // from Hyprland's activelayout event ("keyboard,layout"): only a change
    // from that same keyboard's last layout counts. Virtual keyboards
    // ("hl-virtual-keyboard…": wtype, when voxtype types) are left out,
    // and so is a keyboard's first report. Comparing against the main
    // keyboard instead flashed whenever voxtype typed or a volume key was
    // pressed: "main" is just the keyboard used last, and those have
    // layouts of their own.
    signal layoutNotice(string name)
    property var keyboardLayouts: ({})

    Process {
        running: true
        command: ["sh", "-c", "hyprctl devices -j | jq -r '.keyboards[] | \"\\(.name),\\(.active_keymap)\"'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const known = Object.assign({}, root.keyboardLayouts)
                for (const line of text.split("\n")) {
                    const i = line.indexOf(",")
                    if (i > 0 && known[line.slice(0, i)] === undefined)
                        known[line.slice(0, i)] = line.slice(i + 1)
                }
                root.keyboardLayouts = known
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout")
                root.layoutEvent(event.data)
        }
    }

    function layoutEvent(data) {
        const i = data.indexOf(",")
        const keyboard = data.slice(0, i)
        const layout = data.slice(i + 1)
        if (i <= 0 || layout === "" || keyboard.startsWith("hl-virtual-keyboard"))
            return
        const before = keyboardLayouts[keyboard]
        if (before === layout)
            return
        const known = Object.assign({}, keyboardLayouts)
        known[keyboard] = layout
        keyboardLayouts = known
        if (before !== undefined && armed)
            layoutNotice(layout)
    }

    signal batteryNotice(string kind)
    readonly property bool onBattery: UPower.onBattery
    readonly property var lowThresholds: [20, 10]
    property real lastPercent: -1

    onOnBatteryChanged: if (armed && !onBattery && batteryPercent >= 0) batteryNotice("charging")

    onBatteryPercentChanged: {
        const before = lastPercent
        lastPercent = batteryPercent
        if (!armed || !onBattery || before < 0)
            return
        if (lowThresholds.some(t => before >= t && batteryPercent < t))
            batteryNotice("low")
    }
}
