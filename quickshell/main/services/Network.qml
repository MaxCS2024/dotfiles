pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

// Rebuilt on Quickshell.Networking (native NetworkManager
// D-Bus binding) instead of shelling out to nmcli for every piece of
// state. Two things this API genuinely doesn't expose, confirmed live
// against the real adapter before assuming otherwise, rather than
// trusted from the qmltypes signatures alone:
//   - An IP address. `NetworkDevice.address` is the device's MAC
//     ("00:1A:2B:3C:4D:5E"), not its IP — easy to misread from the name
//     alone. Kept a small, targeted `ip addr show` subprocess for this.
//   - DNS management, which was expected to stay on nmcli from the
//     start. Kept on `nmcli connection modify` verbatim.
// Everything else — connection state, the wifi scan list, signal
// strength, connect/disconnect, PSK prompting on the real failure
// reason instead of a stderr guess — is native D-Bus, no subprocess.
Singleton {
    id: root

    signal notify(string title, string message, bool isError)

    // NetworkTab.qml listens for this and shows common/PasswordPrompt.qml.
    signal pskRequired(string ssid)

    // Every notify() above also becomes a real notification. The quick
    // settings panel
    // used to be the only listener, and its toast lives and dies with the
    // panel: connect to an AP, close the panel, and the result — including
    // "Connection Failed" — was never seen. Posting from the service
    // instead of from a view means the outcome shows up whether or not the
    // panel that started it is still open, or was ever open (DNS changes
    // are driven from the settings window too).
    //
    // Notifications.post() applies the same DND and idle gates a D-Bus
    // notification gets, and takes root.icon so the card shows the wifi or
    // ethernet glyph rather than the generic bell.
    //
    // A "Network" title would be printed twice on the card — as the
    // headline, and again as the sender at its foot — so those hand their
    // message up into the headline and leave the body empty.
    onNotify: (title, message, isError) => {
        const named = title !== "" && title !== "Network"
        Notifications.post(named ? title : message,
                           named ? message : "",
                           isError ? "critical" : "normal",
                           "Network", root.icon)
    }

    // ── Device resolution ────────────────────────────────
    function _findDevice(kind) {
        for (const d of Networking.devices.values) {
            if (d.type === kind) return d
        }
        return null
    }
    readonly property var _wifiDevice: root._findDevice(DeviceType.Wifi)
    readonly property var _wiredDevice: root._findDevice(DeviceType.Wired)
    // Ethernet takes priority over wifi when both are up, matching the
    // old nmcli-based priority.
    readonly property var _activeDevice:
        (root._wiredDevice && root._wiredDevice.connected) ? root._wiredDevice
        : ((root._wifiDevice && root._wifiDevice.connected) ? root._wifiDevice : null)

    readonly property var _activeWifiNetwork: {
        if (!root._wifiDevice) return null
        for (const n of root._wifiDevice.networks.values) {
            if (n.connected) return n
        }
        return null
    }

    // Scanning stays on continuously once a wifi adapter exists — the
    // only way this API keeps `networks` populated at all, verified
    // live: `networks` started at just the one already-connected AP
    // and grew from 1 to 5 entries over a few seconds once
    // `scannerEnabled` was set true, matching a side-by-side `nmcli
    // device wifi list` scan. There's no "scan once, tell me when
    // done" call — see scan() below for how the old Rescan button's
    // transient state is reproduced without one.
    //
    // A `Binding` here, not an `on<X>Changed:` handler — QML's
    // auto-generated handler name for an underscore-prefixed property
    // like `_wifiDevice` is `on_WifiDeviceChanged` (the capitalization
    // rule only touches the first *letter*, and `_` isn't one), not the
    // `onWifiDeviceChanged` that looks obviously correct at a glance.
    // Caught immediately at startup — `qs log` refused to load the
    // whole shell over it ("Cannot assign to non-existent property
    // onWifiDeviceChanged") — rather than silently never firing.
    Binding {
        target: root._wifiDevice
        property: "scannerEnabled"
        value: true
        when: root._wifiDevice !== null
    }

    // ── Public state — same names/shapes the three existing consumers
    // (bar/NetworkButton.qml, quicksettings/NetworkTab.qml,
    // systemsettings/SettingsNetworkTab.qml) already read. One
    // property dropped: `band` (2.4/5/6 GHz) has no equivalent
    // anywhere in this API — not on WifiNetwork, not on NMSettings
    // (which isn't even exported to QML) — so it's gone, not silently
    // blank; NetworkButton.qml's "Band" row was removed with it. ──
    readonly property string type: root._activeDevice
        ? (root._activeDevice.type === DeviceType.Wired ? "ethernet" : "wifi") : "none"
    readonly property string iface: root._activeDevice ? root._activeDevice.name : ""
    readonly property string ssid: root._activeWifiNetwork ? root._activeWifiNetwork.name : ""
    // signalStrength is 0.0-1.0 (verified live: 0.65 for a real AP at
    // normal range), the old nmcli-sourced field was already 0-100 —
    // every consumer displays this as "NN%".
    readonly property int strength: root._activeWifiNetwork
        ? Math.round(root._activeWifiNetwork.signalStrength * 100) : 0
    property string ip: ""

    readonly property var networks: root._wifiDevice
        ? [...root._wifiDevice.networks.values]
            .map(n => ({ ssid: n.name, signal: Math.round(n.signalStrength * 100), active: n.connected }))
            .sort((a, b) => a.active !== b.active ? (a.active ? -1 : 1) : b.signal - a.signal)
        : []

    readonly property int availableCount: root.networks.length
    readonly property bool connected: root.type !== "none"

    // \uf796 (ethernet) and \uf6ff (wifi-off) were Nerd Font *v2*
    // codepoints: the installed JetBrainsMono Nerd Font is v3, which
    // moved the whole Material range to six-digit codepoints, and an
    // unmapped codepoint renders as nothing rather than as tofu. Both
    // states drew a blank glyph in the bar and in every panel that
    // shows this — confirmed against the font's cmap, where f796 and
    // f6ff are absent and the two below are present. The wifi glyph is
    // Font Awesome, whose range v3 left alone, so it was never
    // affected. Written as surrogate pairs to stay consistent with the
    // \u escapes used for glyphs everywhere else in this shell.
    readonly property string icon: root.type === "ethernet" ? "\udb80\ude00"
                                 : root.type === "wifi"     ? "\uf1eb"
                                 : "\udb81\udda9"

    readonly property string displayName: root.type === "ethernet" ? "Ethernet"
                                        : (root.ssid || "Disconnected")

    function fmtRate(bytesPerSec) {
        const kb = bytesPerSec / 1024
        if (kb < 1024) return kb.toFixed(1) + " KB/s"
        return (kb / 1024).toFixed(1) + " MB/s"
    }

    // Powers of 1024, like fmtRate above — the two are read in the same
    // column of network/NetworkPanel.qml's stat grid, and one of them
    // counting in thousands would make the pair disagree about what a
    // megabyte is. Loses the decimal below a megabyte, where the figure
    // changes too fast for a tenth to be readable, and gains one at a
    // gigabyte, where it stops changing fast enough to see.
    function fmtBytes(bytes) {
        const kb = bytes / 1024
        if (kb < 1024) return kb.toFixed(0) + " KB"
        const mb = kb / 1024
        if (mb < 1024) return mb.toFixed(1) + " MB"
        return (mb / 1024).toFixed(2) + " GB"
    }

    // ── Scan ─────────────────────────────────────────────
    // A synthetic pulse, not a real "scan in progress" backend signal
    // — see the scannerEnabled comment above for why one doesn't exist
    // here. This just gives NetworkTab.qml's existing Rescan button
    // the transient "Scanning…" state it was already built to show,
    // without that file needing to change.
    property bool scanning: false
    function scan() {
        if (root._wifiDevice) root._wifiDevice.scannerEnabled = true
        root.scanning = true
        scanPulse.restart()
    }
    Timer { id: scanPulse; interval: 1500; onTriggered: root.scanning = false }

    // ── Connect ──────────────────────────────────────────
    // Try a plain connect first; only prompt for a password on the
    // specific failure that means one is needed
    // (ConnectionFailReason.NoSecrets) rather than guessing upfront
    // from `known` — an open network with no saved profile isn't
    // "known" either, and doesn't need a prompt.
    property var _pendingNetwork: null

    function _findNetwork(ssid) {
        if (!root._wifiDevice) return null
        for (const n of root._wifiDevice.networks.values) {
            if (n.name === ssid) return n
        }
        return null
    }

    function connectTo(ssid) {
        const net = root._findNetwork(ssid)
        if (!net) { root.notify("Network", "Network no longer available", true); return }
        root._pendingNetwork = net
        root.notify("Network", "Connecting to " + ssid + "…", false)
        net.connect()
    }

    function connectWithPsk(ssid, psk) {
        const net = root._findNetwork(ssid)
        if (!net) return
        root._pendingNetwork = net
        net.connectWithPsk(psk)
    }

    Connections {
        target: root._pendingNetwork
        function onConnectionFailed(reason) {
            const net = root._pendingNetwork
            if (!net) return
            if (reason === ConnectionFailReason.NoSecrets) {
                root.pskRequired(net.name)
                return
            }
            root.notify("Connection Failed", ConnectionFailReason.toString(reason), true)
            root._pendingNetwork = null
        }
        function onConnectedChanged() {
            const net = root._pendingNetwork
            if (net && net.connected) {
                root.notify("Network", "Connected to " + net.name, false)
                root._pendingNetwork = null
            }
        }
    }

    // ── Known networks ───────────────────────────────────
    // What this machine has a profile for AND can hear right now — the
    // networks it can join this second without being asked for anything.
    // The profiles themselves are not that list: a machine keeps them for
    // years, and most of them are a few hundred kilometres away.
    //
    // Those get read anyway (`knownNames` below is every wifi profile on
    // the machine) and then dropped by `knownNetworks`, at the user's
    // request 2026-09-17: a rail you open to see where you can connect
    // has nothing to say about a hotel from last spring. The read stays
    // whole because the cost is one nmcli either way, and because the
    // list that gets filtered out is the one a Forget row would need.
    //
    // Quickshell.Networking does carry `known` — but on a Network, and a
    // Network only exists for an AP the adapter is hearing right now, so
    // it answers "is this one in front of me saved" and never "what is
    // saved". The profiles themselves hang off NMSettings, which the
    // qmltypes list and the module does not export to QML. So this is
    // nmcli, for exactly the reason the IP and DNS readers below are.
    //
    // What comes back is the profile's *name*. For anything this shell,
    // nm-applet or nmcli ever created that is the SSID; a profile renamed
    // by hand would show here as permanently out of range, which is a
    // wrong word in a place nobody will be surprised by rather than a
    // wrong network to connect to.
    property var knownNames: []

    // Joined to the scan list rather than kept apart from it: a saved
    // network you are standing next to should say how strong it is, and
    // the one you are on should say so before it says anything else.
    //
    // The connected one is pulled to the front rather than left to
    // last-used order to arrive there on its own (user request
    // 2026-09-17). It nearly always would — connecting is what sets the
    // timestamp — but nearly always is not a rule, and a profile touched
    // by `nmcli connection modify` afterwards outranks it. Partitioned
    // instead of sorted with a comparator, because the rest of the list
    // has an order already and QV4's sort makes no stability promise to
    // keep it in.
    //
    // `|| r.active` and not `seen !== undefined` alone: the network you
    // are standing on is in this list by a stronger right than the scan's
    // say-so, and dropping out of it for the one frame a rescan takes to
    // re-list an AP would be the header's own SSID blinking out of the
    // list under it.
    readonly property var knownNetworks: {
        const rows = root.knownNames.map(name => {
            const seen = root.networks.find(n => n.ssid === name)
            return {
                ssid: name,
                signal: seen ? seen.signal : 0,
                active: name === root.ssid,
                inRange: seen !== undefined
            }
        }).filter(r => r.inRange || r.active)
        return rows.filter(r => r.active).concat(rows.filter(r => !r.active))
    }
    readonly property int knownCount: root.knownNetworks.length

    // The other half of the scan: in range, and not already up in the
    // known list — the rail shows the two one above the other and a
    // network in both of them is the same row printed twice (user
    // request 2026-09-17).
    //
    // Subtracted from `knownNetworks` and not from `knownNames`, so what
    // is hidden here is exactly what is shown there: change the rule for
    // one list (the in-range filter above did) and the other follows
    // without being told.
    //
    // `networks` and `availableCount` are untouched — bar/NetworkButton
    // counts what is in range, and quicksettings/NetworkTab is one list
    // with no known section to subtract.
    readonly property var unsavedNetworks: root.networks.filter(
        n => !root.knownNetworks.some(k => k.ssid === n.ssid))
    readonly property int unsavedCount: root.unsavedNetworks.length

    function refreshKnown() {
        knownProc.running = false
        knownProc.running = true
    }

    // NAME goes last in -f so that a colon inside an SSID stays inside
    // the field that owns it: TYPE and TIMESTAMP can't contain one, so
    // the first two separators are unambiguous and everything after them
    // is the name. nmcli still escapes a literal : or \ on the way out,
    // which is what the replace undoes.
    Process {
        id: knownProc
        command: ["nmcli", "-t", "-f", "TYPE,TIMESTAMP,NAME", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = []
                for (const line of text.split("\n")) {
                    const typeEnd = line.indexOf(":")
                    if (typeEnd === -1) continue
                    if (line.slice(0, typeEnd) !== "802-11-wireless") continue
                    const stampEnd = line.indexOf(":", typeEnd + 1)
                    if (stampEnd === -1) continue
                    const name = line.slice(stampEnd + 1).replace(/\\(.)/g, "$1")
                    if (name === "") continue
                    // Two profiles can carry the same name; the list is of
                    // networks, not of profiles, so the first one wins.
                    if (found.some(f => f.name === name)) continue
                    found.push({ name: name,
                                 stamp: parseInt(line.slice(typeEnd + 1, stampEnd), 10) || 0 })
                }
                // Last used first — the order NetworkManager itself
                // prefers them in, and the one that puts the network you
                // are on at the top and a hotel from last spring at the
                // bottom. nmcli's own order is alphabetical, which is the
                // order of nothing anyone is looking for.
                found.sort((a, b) => b.stamp - a.stamp)
                root.knownNames = found.map(f => f.name)
            }
        }
    }

    // Connecting to a network this machine had never seen writes a new
    // profile, so the list is re-read whenever the SSID changes rather
    // than only when the panel opens (network/NetworkPanel.qml asks on
    // every open as well — a profile can also arrive from nmcli or from
    // another shell entirely).
    onSsidChanged: root.refreshKnown()
    Component.onCompleted: root.refreshKnown()

    onIfaceChanged: {
        root._refreshIp()
        root._refreshGateway()
        root._refreshDns()
        root._prevRx = -1; root._prevTx = -1
        root.rxRate = 0; root.txRate = 0
        // The totals are the new interface's, not the old one's plus it.
        root.rxBytes = -1; root.txBytes = -1
        root._pingSamples = []
        root.pingLatency = -1
        root.pingLoss = -1
    }

    // ── IP address — no Quickshell.Networking equivalent (see the
    // file-level comment). Small, targeted subprocess keyed off
    // `iface`, refreshed on interface change and a slow safety-net
    // timer (DHCP renewal changes the address without an iface
    // change). ──
    Process {
        id: ipProc
        stdout: StdioCollector { onStreamFinished: root.ip = text.trim() }
    }
    function _refreshIp() {
        if (root.iface === "") { root.ip = ""; return }
        ipProc.command = ["sh", "-c",
            "ip -4 addr show " + root.iface + " | grep inet | awk '{print $2}' | cut -d/ -f1"]
        ipProc.running = false
        ipProc.running = true
    }
    // ── Default gateway — the same story as the IP above: nothing in
    // Quickshell.Networking carries a route, so it is one more targeted
    // `ip` call keyed off `iface`. Shares the IP's refresh points rather
    // than taking a timer of its own, because the two change together:
    // a DHCP renewal that moves one has every chance of moving the
    // other, and an interface change certainly moves both. ──
    property string gateway: ""
    Process {
        id: gwProc
        stdout: StdioCollector { onStreamFinished: root.gateway = text.trim() }
    }
    function _refreshGateway() {
        if (root.iface === "") { root.gateway = ""; return }
        // `head -1` because a machine with two default routes on one
        // interface (a VPN coming up, usually) prints both, and the grid
        // has room for one.
        gwProc.command = ["sh", "-c",
            "ip -4 route show default dev " + root.iface + " | awk '{print $3}' | head -1"]
        gwProc.running = false
        gwProc.running = true
    }

    Timer {
        interval: 10000
        running: root.iface !== ""
        repeat: true
        onTriggered: { root._refreshIp(); root._refreshGateway() }
    }

    // ── DNS — no Quickshell.Networking equivalent (confirmed:
    // nothing in this API surfaces or sets DNS servers). Kept on
    // nmcli exactly as before. ──
    property string activeConnection: ""
    property string currentDns: "Automatic"

    // True from the moment a provider is applied until `nmcli connection
    // up` has finished. Applying one takes the interface down and back
    // up, and a device that is mid-reconnect reports no nameservers at
    // all — which is indistinguishable, to the two readers below, from a
    // connection that has none configured. Both used to answer that with
    // "Automatic", so switching TO Cloudflare briefly claimed you were on
    // Automatic, which is both wrong and the opposite of what was asked
    // for. While this is set they leave the status alone and it reads
    // "Connecting…" instead.
    property bool dnsApplying: false
    property string dnsProvider: "default"

    function dnsProviderLabel(provider) {
        if (provider === "google") return "Google DNS (8.8.8.8)"
        if (provider === "cloudflare") return "Cloudflare DNS (1.1.1.1)"
        if (provider === "custom") return "Custom DNS"
        return "Automatic DNS"
    }

    function _refreshDns() {
        if (root.iface === "") {
            root.activeConnection = ""
            if (!root.dnsApplying) root.currentDns = "Automatic"
            return
        }
        connNameProc.command = ["nmcli", "-t", "-f", "GENERAL.CONNECTION", "device", "show", root.iface]
        connNameProc.running = false
        connNameProc.running = true
    }

    Process {
        id: connNameProc
        stdout: StdioCollector {
            onStreamFinished: {
                const idx = text.indexOf(":")
                root.activeConnection = idx !== -1 ? text.slice(idx + 1).trim() : ""
                if (root.activeConnection !== "") {
                    dnsQueryProc.command = ["nmcli", "-t", "-f", "IP4.DNS",
                                            "device", "show", root.iface]
                    dnsQueryProc.running = false
                    dnsQueryProc.running = true

                    dnsConfProc.command = ["nmcli", "-t", "-f", "ipv4.dns",
                                           "connection", "show", root.activeConnection]
                    dnsConfProc.running = false
                    dnsConfProc.running = true
                }
            }
        }
    }

    Process {
        id: dnsQueryProc
        property var found: []
        onRunningChanged: if (running) found = []
        stdout: SplitParser {
            onRead: (line) => {
                const idx = line.indexOf(":")
                if (idx === -1) return
                if (line.slice(0, idx).startsWith("IP4.DNS"))
                    dnsQueryProc.found.push(line.slice(idx + 1))
            }
        }
        // `currentDns` only — this is the DNS actually in effect, which is
        // the useful thing to display and is NOT the same question as
        // which provider is configured. See dnsConfProc below.
        onExited: {
            // An empty result while applying is the reconnect, not an
            // answer; keep "Connecting…" until the change has landed.
            if (root.dnsApplying && dnsQueryProc.found.length === 0) return
            root.currentDns = dnsQueryProc.found.length > 0
                ? dnsQueryProc.found.join(", ") : "Automatic"
        }
    }

    // Which provider is *set*, read from the connection's own ipv4.dns
    // rather than from the addresses currently in use.
    //
    // Deriving it from the active list (which is what this did until
    // 2026-09-16) is wrong for anyone whose router hands out DNS: on
    // Automatic the active list is the router's address, which matches
    // none of the known sets and isn't empty, so it came back "custom".
    // In the old settings pane that was a wrong highlight on a rarely
    // opened tab; the rail puts these four buttons in front of you, and
    // "Custom" lit up on a machine where nothing custom was ever set.
    // Configured-empty is what Automatic actually means, and that is a
    // property of the connection, not of the lease.
    Process {
        id: dnsConfProc
        stdout: StdioCollector {
            onStreamFinished: {
                const idx = text.indexOf(":")
                const raw = idx === -1 ? "" : text.slice(idx + 1).trim()
                const set = raw.split(",").map(v => v.trim()).filter(v => v !== "")
                const joined = [...set].sort().join(" ")
                if (set.length === 0) root.dnsProvider = "default"
                else if (joined === "8.8.4.4 8.8.8.8") root.dnsProvider = "google"
                else if (joined === "1.0.0.1 1.1.1.1") root.dnsProvider = "cloudflare"
                else root.dnsProvider = "custom"
            }
        }
    }

    function applyDns(provider, customValue) {
        if (root.activeConnection === "") {
            root.notify("DNS Update Failed", "No active connection found", true)
            return
        }
        root.dnsProvider = provider
        root.dnsApplying = true
        root.currentDns = "Connecting\u2026"

        let dnsValue = ""
        let ignoreAuto = "yes"

        if (provider === "google") dnsValue = "8.8.8.8 8.8.4.4"
        else if (provider === "cloudflare") dnsValue = "1.1.1.1 1.0.0.1"
        else if (provider === "custom") dnsValue = (customValue || "").trim()
        else { dnsValue = ""; ignoreAuto = "no" }

        dnsModifyProc.command = ["nmcli", "connection", "modify", root.activeConnection,
                                 "ipv4.dns", dnsValue, "ipv4.ignore-auto-dns", ignoreAuto]
        dnsModifyProc.running = false
        dnsModifyProc.running = true
    }

    Process {
        id: dnsModifyProc
        // The exit code used to be read off the Process object here,
        // which has no such property (services/PrivilegedExec.qml says so
        // in as many words) — it evaluated to undefined, `undefined !== 0`
        // is true, so this branch was taken on every run. The effect was
        // that `nmcli connection up` below never fired at all: applying a
        // DNS provider modified the saved connection, never reactivated
        // it, and always reported "DNS Update Failed" whether or not the
        // modify had worked. Found 2026-09-16 when the same mistake in a
        // new handler in this file produced an error over a result that
        // had plainly succeeded.
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.dnsApplying = false
                root.notify("DNS Update Failed",
                            "Could not modify " + root.activeConnection, true)
                root._refreshDns()
                return
            }
            dnsUpProc.command = ["nmcli", "connection", "up", root.activeConnection]
            dnsUpProc.running = false
            dnsUpProc.running = true
        }
    }

    Process {
        id: dnsUpProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root.notify("DNS Updated", root.dnsProviderLabel(root.dnsProvider), false)
            else
                root.notify("DNS Update Failed",
                            "Could not reactivate " + root.activeConnection, true)
            // Cleared BEFORE the refresh, or the guards above would make
            // that refresh a no-op and the status would stick.
            root.dnsApplying = false
            root._refreshDns()
        }
    }

    // ── Speed test (fast.com) ────────────────────────────
    // What the link actually does, as opposed to what it is doing right
    // now — the throughput tiles in the rail read /sys counters and can
    // only report the traffic that happens to exist.
    //
    // fast.com is Netflix's own speed test and it has no CLI on this
    // machine, so this is the same three steps its web page takes, in
    // curl: scrape the app bundle for the API token, ask api.fast.com for
    // a handful of CDN targets, then pull a fixed 25MB range from each
    // and add up what the transfers managed. The token has been the same
    // string for years and every third-party client hardcodes it; reading
    // it out of the bundle each run costs one request and means a rotation
    // doesn't silently break this.
    //
    // Three targets at once, not one: a single stream measured 71 Mbit/s
    // on the link where three in parallel measured 606, which is the
    // difference between testing the connection and testing one TCP
    // stream's window. fast.com's own page opens several for the same
    // reason. The whole run takes about two and a half seconds.
    //
    // Latency is the cheapest true number in the same transfer —
    // time_connect minus time_namelookup, the best of the three, so it is
    // a TCP handshake to the nearest CDN node and not a DNS lookup or a
    // TLS negotiation.
    //
    // Never automatic. It is 75MB down the link every time it runs, which
    // is not something a panel should do because it was opened; the
    // button in network/NetworkPanel.qml's header runs it on a click and
    // holds the last answer until the next one.
    property bool speedTesting: false
    property real speedDown: 0      // Mbit/s, 0 until a run has finished
    property real speedLatency: 0   // ms
    property string speedError: ""

    // The rail shows a finished result in the caption line under the
    // SSID, which is otherwise the signal strength, so it needs a way to
    // hand that line back — it calls this on open(). A run in flight is
    // left alone: nothing here can stop the curl, and blanking the state
    // under it would only lose the answer when it lands.
    function clearSpeedTest() {
        if (root.speedTesting) return
        root.speedDown = 0
        root.speedLatency = 0
        root.speedError = ""
    }

    function runSpeedTest() {
        if (root.speedTesting) return
        root.speedError = ""
        root.speedTesting = true
        speedProc.lastExit = -1
        speedProc.lastText = ""
        speedProc.sawExit = false
        speedProc.sawText = false
        speedProc.running = false
        speedProc.running = true
    }

    // Both halves of a finished run land here and the second one to
    // arrive is the one that decides. Which half that is was the whole
    // bug: reading `lastExit` from inside onStreamFinished — the way
    // recProc above does, where the process outlives its first output —
    // found it still -1 here, so a run that had just reported 475 Mbit/s
    // displayed "Test failed". Nothing promises an order; this stops
    // needing one.
    function _speedSettle() {
        if (!speedProc.sawExit || !speedProc.sawText) return
        root.speedTesting = false

        const parts = speedProc.lastText.trim().split(/\s+/)
        const down = parseFloat(parts[0])
        const lat = parseFloat(parts[1])
        if (speedProc.lastExit === 0 && parts.length === 2
                && isFinite(down) && isFinite(lat)) {
            root.speedDown = down
            root.speedLatency = lat
            return
        }

        root.speedError = speedProc.lastExit === 2 ? "fast.com unreachable"
                        : speedProc.lastExit === 3 ? "No test servers"
                        : speedProc.lastExit === 4 ? "Nothing transferred"
                        : "Test failed"
    }

    // Exit codes are the script's own, so a failure can say which of the
    // three steps did not answer rather than "failed".
    readonly property string _speedScript: [
        'd=$(mktemp -d) || exit 1',
        'trap \'rm -rf "$d"\' EXIT',
        // \\. and not \., which JS would eat on the way into the string
        // and hand grep a dot that matches anything.
        'js=$(curl -sf --max-time 8 https://fast.com/ | grep -o \'app-[a-z0-9]*\\.js\' | head -1)',
        '[ -n "$js" ] || exit 2',
        'tok=$(curl -sf --max-time 8 "https://fast.com/$js" | grep -o \'token:"[^"]*"\' | head -1 | cut -d\'"\' -f2)',
        '[ -n "$tok" ] || exit 2',
        'api=$(curl -sf --max-time 8 "https://api.fast.com/netflix/speedtest/v2?https=true&token=$tok&urlCount=3")',
        // Both "name" and "url" carry the target URL; the grep names one
        // of them so the count stays three.
        'urls=$(printf \'%s\' "$api" | grep -o \'"url":"[^"]*"\' | cut -d\'"\' -f4 | head -3)',
        '[ -n "$urls" ] || exit 3',
        'i=0',
        'for u in $urls; do',
        '  i=$((i+1))',
        // The range goes in the path, which is how fast.com's own client
        // asks for a bounded transfer; without it the target streams until
        // something stops it. One shell line per array entry, because
        // join("\n") would turn a continuation into three broken commands.
        '  r=$(printf \'%s\' "$u" | sed \'s|/speedtest?|/speedtest/range/0-26214400?|\')',
        '  curl -s -o /dev/null --max-time 12 -w \'%{speed_download} %{time_namelookup} %{time_connect}\\n\' "$r" > "$d/$i" &',
        'done',
        'wait',
        'awk \'{ bytes += $1; if (lat == 0 || ($3-$2) < lat) lat = $3 - $2 }',
        '     END { if (bytes == 0) exit 4; printf "%.1f %.0f\\n", bytes * 8 / 1000000, lat * 1000 }\' "$d"/*'
    ].join("\n")

    readonly property Process speedProc: Process {
        property int lastExit: -1
        property string lastText: ""
        property bool sawExit: false
        property bool sawText: false

        command: ["sh", "-c", root._speedScript]
        onExited: (exitCode, exitStatus) => {
            speedProc.lastExit = exitCode
            speedProc.sawExit = true
            root._speedSettle()
        }
        stdout: StdioCollector {
            id: speedOut
            onStreamFinished: {
                speedProc.lastText = speedOut.text
                speedProc.sawText = true
                root._speedSettle()
            }
        }
    }

    // ── Share credentials (QR) ───────────────────────────
    // `nmcli device wifi show-password` hands back the active AP's SSID,
    // security type and PSK in three lines, and — unlike `connection show
    // --show-secrets` — does it without a polkit prompt for this user, so
    // no PrivilegedExec round trip is needed.
    //
    // Fetched on demand and cleared again by the caller, never held as
    // ambient state: this is the one value in this service that is a
    // secret, and the QR sheet in network/NetworkPanel.qml drops it the
    // moment it closes rather than keeping a live password in memory for
    // the rest of the shell run. It is deliberately not persisted, not
    // logged, and not part of any IPC surface.
    property string shareSsid: ""
    property string shareSecurity: ""
    property string sharePassword: ""
    property bool shareLoading: false
    property string shareError: ""

    function loadShare() {
        if (root.type !== "wifi") {
            root.shareError = "Not on a Wi-Fi network"
            return
        }
        root.shareError = ""
        root.shareLoading = true
        shareProc.running = false
        shareProc.running = true
    }

    function clearShare() {
        root.shareSsid = ""
        root.shareSecurity = ""
        root.sharePassword = ""
        root.shareError = ""
        root.shareLoading = false
    }

    Process {
        id: shareProc
        command: ["nmcli", "device", "wifi", "show-password"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                for (const line of lines) {
                    const idx = line.indexOf(":")
                    if (idx === -1) continue
                    const key = line.slice(0, idx).trim()
                    // Exactly one leading space is the separator nmcli
                    // prints; trimming further would eat a password that
                    // genuinely starts or ends with whitespace.
                    const value = line.slice(idx + 1).replace(/^ /, "")
                    if (key === "SSID") root.shareSsid = value
                    else if (key === "Security") root.shareSecurity = value
                    else if (key === "Password") root.sharePassword = value
                }
                root.shareLoading = false
                if (root.shareSsid === "")
                    root.shareError = "No saved credentials for this network"
            }
        }
        // exitCode is a parameter of this signal, not a property on
        // Process — see the same note in services/PrivilegedExec.qml.
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.shareLoading = false
                root.shareError = "Could not read the network password"
            }
        }
    }

    // ── Throughput (FileView, unchanged — no subprocess, and no
    // equivalent in Quickshell.Networking either). ──
    property real rxRate: 0
    property real txRate: 0
    // The same two numbers the rates are differenced from, published
    // rather than thrown away: the grid in network/NetworkPanel.qml
    // wants both the speed and the odometer, and reading /sys twice for
    // one value each would be two reads of the same file. -1 is "no
    // sample yet", which is not 0 — a link that has genuinely carried
    // nothing reads 0 KB and should say so.
    //
    // Kernel counters, so the span is since the interface came up: a
    // week for a machine left on, and back to zero the moment it is
    // brought down. Not a session or a monthly figure, and this is the
    // only place that could be mistaken for one.
    property real rxBytes: -1
    property real txBytes: -1
    property real _prevRx: -1
    property real _prevRxT: 0
    property real _prevTx: -1
    property real _prevTxT: 0

    FileView {
        id: rxFile
        printErrors: false
        path: root.iface !== "" ? "/sys/class/net/" + root.iface + "/statistics/rx_bytes" : ""
        onLoaded: {
            const v = parseFloat(text())
            const now = Date.now()
            if (!isNaN(v)) {
                if (root._prevRx >= 0 && now > root._prevRxT)
                    root.rxRate = Math.max(0, (v - root._prevRx) / ((now - root._prevRxT) / 1000))
                root.rxBytes = v
                root._prevRx = v
                root._prevRxT = now
            }
        }
    }

    FileView {
        id: txFile
        printErrors: false
        path: root.iface !== "" ? "/sys/class/net/" + root.iface + "/statistics/tx_bytes" : ""
        onLoaded: {
            const v = parseFloat(text())
            const now = Date.now()
            if (!isNaN(v)) {
                if (root._prevTx >= 0 && now > root._prevTxT)
                    root.txRate = Math.max(0, (v - root._prevTx) / ((now - root._prevTxT) / 1000))
                root.txBytes = v
                root._prevTx = v
                root._prevTxT = now
            }
        }
    }

    Timer {
        interval: 1000
        running: root.iface !== ""
        repeat: true
        onTriggered: { rxFile.reload(); txFile.reload() }
    }

    // ── Reachability ─────────────────────────────────────
    // Everything else on this card describes the link: whether it is up,
    // what address it holds, how much has crossed it. None of that says
    // the internet is on the other end, which is the thing you actually
    // opened the rail to find out on a network that has stopped working.
    // Three echoes every five seconds is what answers it.
    //
    // An IP literal, so this is a test of the network and not of DNS —
    // the DNS row two lines up is where a resolver failure belongs, and
    // a hostname here would blame the link for it. 1.1.1.1 regardless of
    // which provider the DNS pills have selected: it is being used as an
    // echo responder, not as a resolver.
    //
    // Bound to `iface` with -I so a machine holding both a wifi and a
    // wired route measures the one the rest of the card is describing.
    property string pingTarget: "1.1.1.1"
    property real pingLatency: -1   // ms, mean of the last few runs; -1 = no answer
    property int pingLoss: -1       // percent of the last run; -1 = never run
    property var _pingSamples: []
    // Five runs, as many as omarchy's panel averages. One run is three
    // echoes about a second apart, so this is a mean over the last
    // twenty-odd seconds — long enough that a single late packet doesn't
    // redraw the number, short enough to follow a link going bad.
    readonly property int _pingWindow: 5

    // Only while something is looking. This is the one poll in this file
    // that puts packets on the wire, and a rail that is closed has no
    // reader for the answer. network/NetworkPanel.qml binds this to its
    // own `shown`.
    property bool pingActive: false

    Process {
        id: pingProc
        stdout: StdioCollector { onStreamFinished: root._readPing(text) }
    }

    function _pingNow() {
        if (root.iface === "") return
        pingProc.command = ["ping", "-n", "-q", "-c", "3", "-W", "1",
                            "-I", root.iface, root.pingTarget]
        pingProc.running = false
        pingProc.running = true
    }

    function _readPing(out) {
        // The statistics line is printed even when every echo is lost,
        // so loss is readable in exactly the case that matters most.
        const loss = out.match(/([\d.]+)% packet loss/)
        root.pingLoss = loss ? Math.round(parseFloat(loss[1])) : 100

        // The rtt line is not: a run that heard nothing back omits it
        // entirely. Drop the window with it rather than averaging a
        // stale figure into a link that is currently answering nothing.
        const rtt = out.match(/=\s*[\d.]+\/([\d.]+)\//)
        if (!rtt) {
            root._pingSamples = []
            root.pingLatency = -1
            return
        }

        // Reassigned rather than pushed into: a var property holding a
        // JS array doesn't notify on mutation, so a push() alone would
        // update the average and never tell the grid about it.
        const next = root._pingSamples.slice(-(root._pingWindow - 1))
        next.push(parseFloat(rtt[1]))
        root._pingSamples = next
        root.pingLatency = next.reduce((a, b) => a + b, 0) / next.length
    }

    Timer {
        interval: 5000
        running: root.pingActive && root.iface !== ""
        repeat: true
        // The rail is open and the row says "--"; waiting five seconds
        // for the first answer is the whole of the user's first
        // impression of it.
        triggeredOnStart: true
        onTriggered: root._pingNow()
    }
}
