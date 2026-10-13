pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The settings window's Network section (AGENTS.md, Settings window ›
// Network), the part Quickshell.Networking doesn't cover, through
// nmcli: VPNs, joining a hidden network, and the wired device's address. NetworkManager lets the user change these
// without a password (settings.modify.system: yes). Operations go by
// UUID, since names can hold spaces and colons.
Singleton {
    id: root

    // [{ name, uuid, type, autoconnect, active, device }]
    property var connections: []
    // { "<device>": { type, state, connection, addresses: [], gateway, dns: [] } }
    property var devices: ({})
    // The last failed action's message, shown at the foot of the page.
    property string message: ""

    readonly property var vpns: connections.filter(c => c.type === "vpn" || c.type === "wireguard")

    // While the page is open, NetworkManager's changes refresh it.
    property bool watching: false

    // nmcli -t: fields split on ':', with "\:" and "\\" escaped.
    function fields(line) {
        const out = []
        let cur = ""
        for (let i = 0; i < line.length; i++) {
            const c = line[i]
            if (c === "\\" && i + 1 < line.length)
                cur += line[++i]
            else if (c === ":") {
                out.push(cur)
                cur = ""
            } else
                cur += c
        }
        out.push(cur)
        return out
    }

    Process {
        id: query
        command: ["sh", "-c", "nmcli -t -f NAME,UUID,TYPE,AUTOCONNECT,ACTIVE,DEVICE con show; echo @@; nmcli -t -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS dev show"]
        stdout: StdioCollector {
            onStreamFinished: root.read(text)
        }
    }

    function refresh() {
        if (query.running)
            refreshSoon.restart()
        else
            query.running = true
    }

    Timer {
        id: refreshSoon
        interval: 400
        onTriggered: root.refresh()
    }

    function read(text) {
        const [cons, devs] = text.split("\n@@\n")
        connections = (cons || "").split("\n").filter(l => l !== "").map(l => {
            const f = fields(l)
            return { name: f[0], uuid: f[1], type: f[2], autoconnect: f[3] === "yes", active: f[4] === "yes", device: f[5] || "" }
        })
        const d = {}
        let cur = null
        for (const line of (devs || "").split("\n")) {
            const i = line.indexOf(":")
            if (i < 0)
                continue
            const key = line.slice(0, i).replace(/\[\d+\]$/, "")
            const value = line.slice(i + 1).replace(/\\:/g, ":")
            if (key === "GENERAL.DEVICE") {
                cur = d[value] = { type: "", state: "", connection: "", addresses: [], gateway: "", dns: [] }
                continue
            }
            if (!cur)
                continue
            if (key === "GENERAL.TYPE") cur.type = value
            else if (key === "GENERAL.STATE") cur.state = value.replace(/^\d+ /, "").replace(/^\(|\)$/g, "")
            else if (key === "GENERAL.CONNECTION") cur.connection = value
            else if (key === "IP4.ADDRESS") cur.addresses.push(value)
            else if (key === "IP4.GATEWAY") cur.gateway = value
            else if (key === "IP4.DNS") cur.dns.push(value)
        }
        devices = d
    }

    // NetworkManager's own change feed, while the page is open.
    Process {
        running: root.watching
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: refreshSoon.restart()
        }
    }

    onWatchingChanged: if (watching) refresh()

    // ── Actions ──
    // One at a time; a failure leaves nmcli's message in `message`.
    Process {
        id: action
        property string what: ""
        stderr: StdioCollector {
            id: actionErr
        }
        onExited: code => {
            root.message = code === 0 ? "" : "Couldn't " + what + ": " + actionErr.text.trim().replace(/^Error: /, "")
            root.refresh()
        }
    }

    function run(what, command) {
        if (action.running)
            return
        message = ""
        action.what = what
        action.command = command
        action.running = true
    }

    function up(c) {
        run("connect to " + c.name, ["nmcli", "connection", "up", "uuid", c.uuid])
    }

    function down(c) {
        run("disconnect " + c.name, ["nmcli", "connection", "down", "uuid", c.uuid])
    }

    function joinHidden(ssid, password) {
        const cmd = ["nmcli", "device", "wifi", "connect", ssid, "hidden", "yes"]
        run("join " + ssid, password ? cmd.concat(["password", password]) : cmd)
    }
}
