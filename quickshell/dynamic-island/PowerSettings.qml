pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The settings window's Power section (AGENTS.md, Settings window ›
// Power): the idle timers (hypridle, through LocalConfig.savePower) and
// the battery charge limit. The limit is written straight to every
// battery's charge_control_end_threshold, which the "Battery charge
// limit" patch (udev/92-battery-charge-limit.rules) makes writable for
// wheel. It is saved too and written again at startup if the battery
// has forgotten it.
Singleton {
    id: root

    // hypridle.conf's own values, for timers not saved here.
    readonly property var defaults: ({ lockAfter: 300, screenOffAfter: 330, suspendAfter: 0 })
    readonly property var saved: LocalConfig.settings.power || ({})

    // Every battery with a charge limit: [{ path, limit, writable }].
    property var batteries: []
    readonly property bool hasLimit: batteries.length > 0
    readonly property bool writable: hasLimit && batteries.every(b => b.writable)
    readonly property int chargeLimit: hasLimit ? batteries[0].limit : 100

    // Main's "Stay awake" (an idle inhibitor on its bar) pauses every
    // timer; the page says so. Read from main's `awake` IPC target, so it
    // is false when main isn't running.
    property bool stayAwake: false

    Process {
        id: awake
        command: ["qs", "-c", "main", "ipc", "call", "awake", "state"]
        stdout: StdioCollector {
            onStreamFinished: root.stayAwake = text.trim() === "on"
        }
    }

    function turnOffStayAwake() {
        Quickshell.execDetached(["qs", "-c", "main", "ipc", "call", "awake", "disable"])
        rereadSoon.restart()
    }

    function value(key) {
        return saved[key] !== undefined ? saved[key] : defaults[key]
    }

    function setTimer(key, seconds) {
        const next = Object.assign({}, saved)
        next[key] = seconds
        LocalConfig.savePower(next)
    }

    function setChargeLimit(percent) {
        if (!writable)
            return
        Quickshell.execDetached(["sh", "-c", 'for f in /sys/class/power_supply/BAT*/charge_control_end_threshold; do printf "%s" "$1" > "$f"; done', "sh", String(percent)])
        LocalConfig.settings = Object.assign({}, LocalConfig.settings,
            { power: Object.assign({}, saved, { chargeLimit: percent }) })
        LocalConfig.saveJson()
        rereadSoon.restart()
    }

    Timer {
        id: rereadSoon
        interval: 300
        onTriggered: root.refresh()
    }

    // "path limit w|r" per battery.
    Process {
        id: query
        command: ["sh", "-c", 'for f in /sys/class/power_supply/BAT*/charge_control_end_threshold; do [ -f "$f" ] || continue; echo "$f $(cat "$f") $([ -w "$f" ] && echo w || echo r)"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                root.batteries = text.trim().split("\n").filter(l => l !== "").map(l => {
                    const [path, limit, mode] = l.split(" ")
                    return { path: path, limit: parseInt(limit) || 100, writable: mode === "w" }
                })
                root.restore()
            }
        }
    }

    function refresh() {
        query.running = true
        awake.running = true
    }

    // Once, after the first reading: the saved limit, if a battery lost it.
    property bool restored: false
    function restore() {
        if (restored || !LocalConfig.loaded)
            return
        restored = true
        const want = saved.chargeLimit
        if (want !== undefined && writable && batteries.some(b => b.limit !== want))
            setChargeLimit(want)
    }

    Connections {
        target: LocalConfig
        function onLoadedChanged() {
            root.restore()
        }
    }

    // The patch installed in a terminal (sudo), then read again.
    Process {
        id: installer
        // relay joins everything after -- into one shell command line,
        // so it is passed as one word (as separate sh -c words, only
        // `rack` ran).
        command: ["relay", "default", "exec", "terminal", "--title", "Charge limit patch", "--",
            'rack patches install battery-charge-limit; echo; printf "Press Enter to close. "; read _']
        onExited: root.refresh()
    }

    function installPatch() {
        installer.running = true
    }

    Component.onCompleted: refresh()
}
