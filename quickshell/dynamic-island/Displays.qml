pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// The settings window's Displays section (AGENTS.md, Settings window ›
// Displays): the screens as Hyprland reports them (`live`), the copy
// the page edits (`staged`), and Apply with its keep-or-revert
// countdown. A singleton, so a countdown outlives the window closing.
// It also spots a screen being plugged in, for the island's "Display
// connected" flash.
//
// A screen: { name, key, desc, label, laptop, modes: { "WxH": ["60.01", …] },
// res: "WxH", rate: "60.01", scale, transform, x, y, enabled, mirror }
// where `key` is how local.lua names it ("desc:…", or the port if the
// screen has no description) and `mirror` is the mirrored screen's port
// name, or "".
Singleton {
    id: root

    property var live: []
    property var staged: []
    property bool liveDock: false
    property bool stagedDock: false
    property string selected: ""

    readonly property bool hasLaptop: live.some(m => m.laptop)
    readonly property bool dirty: JSON.stringify(staged) !== JSON.stringify(live)
        || stagedDock !== liveDock

    // The countdown after an Apply that could leave a screen dark.
    property bool confirming: false
    property int secondsLeft: 0

    // Asked by the island, to flash "Display connected".
    signal connected(string label)
    // No flash for the screens an Apply or revert brings back.
    property real quietUntil: 0

    readonly property var scales: [1, 1.25, 1.5, 1.75, 2]

    // ── Reading ──

    Process {
        id: query
        // Set after the first reading, which only sets the baseline.
        property bool seen: false
        // Hyprland's screens, then after a line of "@@" each DRM
        // connector the kernel knows ("HDMI-A-2 connected"): Hyprland can
        // keep an unplugged screen in `monitors all`, disabled.
        command: ["sh", "-c", 'hyprctl monitors all -j; echo @@; for f in /sys/class/drm/card*-*/status; do b=${f%/status}; b=${b##*/}; echo "${b#card*-} $(cat "$f")"; done']
        stdout: StdioCollector {
            onStreamFinished: root.read(text)
        }
    }

    function refresh() {
        query.running = true
    }

    Timer {
        id: refreshSoon
        interval: 300
        onTriggered: root.refresh()
    }

    // Hyprland's events, and Qt's own list of screens as a second
    // witness: an unplugged screen once stayed listed, and both are cheap.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"].indexOf(event.name) !== -1)
                refreshSoon.restart()
        }
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            refreshSoon.restart()
        }
    }

    Connections {
        target: LocalConfig
        function onLoadedChanged() {
            root.liveDock = root.dockSetting()
            root.stagedDock = root.liveDock
        }
    }

    Component.onCompleted: refresh()

    function dockSetting() {
        const d = LocalConfig.settings.displays
        return !!(d && d.laptopOffDocked)
    }

    function isLaptop(name) {
        return /^(eDP|LVDS|DSI)/.test(name)
    }

    function labelOf(m) {
        if (isLaptop(m.name))
            return "Built-in display"
        if (m.model && !/^0x/i.test(m.model))
            return m.model
        return m.description || m.name
    }

    function read(text) {
        const [json, drm] = text.split("\n@@\n")
        let list
        try {
            list = JSON.parse(json)
        } catch (e) {
            return
        }
        const unplugged = {}
        for (const line of (drm || "").split("\n")) {
            const [name, status] = line.trim().split(" ")
            if (status === "disconnected")
                unplugged[name] = true
        }
        list = list.filter(m => !unplugged[m.name])
        const byId = {}
        for (const m of list)
            byId[m.id] = m.name
        const next = list.map(m => {
            const modes = {}
            for (const s of m.availableModes || []) {
                const r = /^(\d+x\d+)@([\d.]+)Hz$/.exec(s)
                if (!r)
                    continue
                const rates = modes[r[1]] || (modes[r[1]] = [])
                if (rates.indexOf(r[2]) === -1)
                    rates.push(r[2])
            }
            for (const k in modes)
                modes[k].sort((a, b) => parseFloat(b) - parseFloat(a))
            let res = m.width + "x" + m.height
            if (!modes[res])
                res = resolutions(modes)[0] || res
            const rates = modes[res] || []
            const rate = rates.length === 0 ? m.refreshRate.toFixed(2)
                : rates.reduce((a, b) => Math.abs(parseFloat(b) - m.refreshRate) < Math.abs(parseFloat(a) - m.refreshRate) ? b : a)
            const mirrorOf = String(m.mirrorOf)
            return {
                name: m.name,
                key: m.description ? "desc:" + m.description : m.name,
                desc: m.description || "",
                label: labelOf(m),
                laptop: isLaptop(m.name),
                modes: modes,
                res: res,
                rate: rate,
                scale: Math.round(m.scale * 100) / 100,
                transform: m.transform,
                x: m.x,
                y: m.y,
                enabled: !m.disabled,
                mirror: mirrorOf === "none" || mirrorOf === "" ? ""
                    : (byId[mirrorOf] !== undefined ? byId[mirrorOf] : mirrorOf),
            }
        })

        // A new external screen, after the first reading: flash it.
        if (query.seen && Date.now() > quietUntil) {
            for (const m of next)
                if (!m.laptop && !root.live.some(o => o.name === m.name))
                    root.connected(m.label)
        }
        query.seen = true

        live = next
        staged = JSON.parse(JSON.stringify(next))
        liveDock = dockSetting()
        stagedDock = liveDock
        if (!live.some(m => m.name === selected))
            selected = (live.find(m => m.enabled && !m.mirror) || live[0] || { name: "" }).name
    }

    // ── Geometry, in Hyprland's layout (logical) pixels ──

    function resolutions(modes) {
        return Object.keys(modes).sort((a, b) => {
            const [aw, ah] = a.split("x").map(Number)
            const [bw, bh] = b.split("x").map(Number)
            return bw * bh - aw * ah || bw - aw
        })
    }

    function size(m) {
        const [w, h] = m.res.split("x").map(Number)
        const sw = Math.round(w / m.scale), sh = Math.round(h / m.scale)
        return m.transform % 2 === 1 ? { w: sh, h: sw } : { w: sw, h: sh }
    }

    // Screens with a place in the layout: on, and not mirroring another.
    function placed(list) {
        return (list || staged).filter(m => m.enabled && !m.mirror)
    }

    function overlaps(a, b) {
        return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
    }

    // The nearest place to (px, py) where `name` touches another screen
    // edge to edge without overlapping any. Along the shared edge it
    // snaps to the other screen's start, centre or end when close.
    function snap(name, px, py) {
        const me = staged.find(m => m.name === name)
        const s = size(me)
        const others = placed().filter(m => m.name !== name).map(m => Object.assign({ x: m.x, y: m.y }, size(m)))
        if (others.length === 0)
            return { x: 0, y: 0 }
        let best = null
        const consider = (x, y) => {
            const r = { x: Math.round(x), y: Math.round(y), w: s.w, h: s.h }
            if (others.some(o => overlaps(r, o)))
                return
            const d = Math.hypot(r.x - px, r.y - py)
            if (!best || d < best.d)
                best = { x: r.x, y: r.y, d: d }
        }
        const along = (p, start, len, mine) => {
            const lo = start - mine + 1, hi = start + len - 1
            const v = Math.max(lo, Math.min(hi, p))
            const near = Math.min(len, mine) * 0.15
            for (const t of [start, start + len - mine, start + (len - mine) / 2])
                if (Math.abs(v - t) < near)
                    return t
            return v
        }
        for (const o of others) {
            const y = along(py, o.y, o.h, s.h)
            const x = along(px, o.x, o.w, s.w)
            consider(o.x - s.w, y)
            consider(o.x + o.w, y)
            consider(x, o.y - s.h)
            consider(x, o.y + o.h)
        }
        return best || { x: me.x, y: me.y }
    }

    // Moves the layout so its top-left corner is at 0x0.
    function normalised(list) {
        const p = placed(list)
        if (p.length === 0)
            return list
        const minX = Math.min(...p.map(m => m.x)), minY = Math.min(...p.map(m => m.y))
        return list.map(m => p.indexOf(m) === -1 ? m : Object.assign({}, m, { x: m.x - minX, y: m.y - minY }))
    }

    // ── Editing ──

    function screen(name) {
        return staged.find(m => m.name === name) || null
    }

    function liveScreen(name) {
        return live.find(m => m.name === name) || null
    }

    // Whether `name` is the only screen left in the layout, which can't
    // be turned off or made a mirror.
    function isLast(name) {
        const p = placed()
        return p.length === 1 && p[0].name === name
    }

    function set(name, key, value) {
        const before = screen(name)
        if (!before)
            return
        const changes = {}
        changes[key] = value
        if (key === "res") {
            const rates = before.modes[value] || []
            changes.rate = rates[0] || before.rate
        }
        let next = staged.map(m => m.name === name ? Object.assign({}, m, changes) : m)
        const after = next.find(m => m.name === name)

        if (key === "enabled" && value || key === "mirror" && !value) {
            // Back into the layout: to the right of the others.
            const p = placed(next).filter(m => m.name !== name)
            const right = p.length ? Math.max(...p.map(m => m.x + size(m).w)) : 0
            next = next.map(m => m.name === name ? Object.assign({}, m, { x: right, y: 0 }) : m)
        } else if (["res", "scale", "transform"].indexOf(key) !== -1 && after.enabled && !after.mirror) {
            // Its size changed: screens past its right or bottom edge
            // move with that edge, so they stay touching.
            const a = size(before), b = size(after)
            next = next.map(m => {
                if (m.name === name || !m.enabled || m.mirror)
                    return m
                return Object.assign({}, m, {
                    x: m.x >= before.x + a.w ? m.x + b.w - a.w : m.x,
                    y: m.y >= before.y + a.h && m.x < before.x + a.w ? m.y + b.h - a.h : m.y,
                })
            })
        }
        staged = normalised(next)
    }

    function move(name, px, py) {
        const p = snap(name, px, py)
        staged = normalised(staged.map(m => m.name === name ? Object.assign({}, m, { x: p.x, y: p.y }) : m))
    }

    function reset() {
        staged = JSON.parse(JSON.stringify(live))
        stagedDock = liveDock
    }

    // ── Applying ──

    // The settings with every connected screen as staged. Screens not
    // connected now keep their saved entries.
    function settingsFromStaged() {
        const s = JSON.parse(JSON.stringify(LocalConfig.settings))
        const d = s.displays || (s.displays = {})
        const monitors = d.monitors || (d.monitors = {})
        for (const m of staged) {
            const target = m.mirror ? staged.find(o => o.name === m.mirror) : null
            monitors[m.key] = {
                name: m.name,
                laptop: m.laptop,
                mode: m.res + "@" + m.rate,
                position: m.x + "x" + m.y,
                scale: m.scale,
                transform: m.transform,
                disabled: !m.enabled,
                mirror: target ? target.key : "",
            }
        }
        d.laptopOffDocked = stagedDock
        return s
    }

    // Whether the change could leave a screen dark or unreadable:
    // anything but moving screens around.
    function risky() {
        if (stagedDock !== liveDock)
            return true
        return staged.some(m => {
            const l = liveScreen(m.name)
            return !l || ["res", "rate", "scale", "transform", "enabled", "mirror"].some(k => l[k] !== m[k])
        })
    }

    function apply() {
        if (!dirty || confirming)
            return
        const next = settingsFromStaged()
        quietUntil = Date.now() + 5000
        if (risky()) {
            LocalConfig.trial(next)
            secondsLeft = 15
            confirming = true
            countdown.restart()
        } else {
            LocalConfig.save(next)
        }
    }

    function keep() {
        countdown.stop()
        confirming = false
        LocalConfig.keep()
    }

    function revert() {
        countdown.stop()
        confirming = false
        quietUntil = Date.now() + 5000
        LocalConfig.revert()
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root.secondsLeft--
            if (root.secondsLeft <= 0)
                root.revert()
        }
    }
}
