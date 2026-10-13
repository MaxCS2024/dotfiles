pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// Privacy indicators (AGENTS.md, Privacy indicators): which apps are
// using the microphone, the camera or the screen right now. Outside the
// activity queue: the island reads `users` for its dots and
// `announcement` for the moment it names an app, and nothing (DND, the
// expanded state, fullscreen) suppresses either.
Singleton {
    id: root

    readonly property var kinds: ["mic", "camera", "screen"]

    // ── PipeWire ──
    // Every active link from a capture device to an app's stream. The
    // source says what is captured: an Audio/Source is a microphone; a
    // Video/Source with a device.api (v4l2, libcamera) is a camera; any
    // other Video/Source is a screencast (xdg-desktop-portal's streams).
    // A sink's monitor (an Audio/Sink) is playback being captured, not
    // the microphone, and level meters (stream.monitor) don't count.
    // A list type, not a JS array: copied so it has map and filter.
    readonly property var groups: Array.from(Pipewire.linkGroups.values)
    PwObjectTracker {
        // The groups themselves too: a link's state stays unknown (-1)
        // until it is tracked.
        objects: {
            const list = []
            for (const g of root.groups)
                list.push(...[g, g.source, g.target].filter(o => o))
            return list
        }
    }

    function kindOf(node) {
        const cls = node?.properties["media.class"] ?? ""
        if (cls.startsWith("Audio/Source"))
            return "mic"
        if (cls === "Video/Source")
            return node.properties["device.api"] ? "camera" : "screen"
        return ""
    }

    function appName(node) {
        const p = node.properties
        return p["application.name"] || p["application.process.binary"] || node.description || node.name
    }

    readonly property var pipewireUsers: {
        const u = { mic: [], camera: [], screen: [] }
        for (const g of groups) {
            if (g.state !== PwLinkState.Active || !g.target)
                continue
            const kind = kindOf(g.source)
            if (!kind || g.target.properties["stream.monitor"] === "true")
                continue
            const name = appName(g.target)
            if (!u[kind].includes(name))
                u[kind].push(name)
        }
        return u
    }

    // ── Screencopy ──
    // Recorders that use wlr-screencopy (wf-recorder, OBS's capture) never
    // touch PipeWire; Hyprland's screencast event names no app, only that
    // a client started or stopped. A count per start and stop, trusted
    // only after 1.5 seconds, so a screenshot's single frame (grim)
    // doesn't light the dot.
    property int screencasts: 0
    property bool screencastActive: false

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "screencast")
                return
            root.screencasts = Math.max(0, root.screencasts + (event.data.startsWith("1") ? 1 : -1))
            if (root.screencasts > 0)
                screencastDelay.restart()
            else {
                screencastDelay.stop()
                root.screencastActive = false
            }
        }
    }

    Timer {
        id: screencastDelay
        interval: 1500
        onTriggered: root.screencastActive = root.screencasts > 0
    }

    // ── Who's using what ──
    // Made-up users from the test target join the real ones.
    property var simulated: ({ mic: [], camera: [], screen: [] })

    readonly property var users: {
        const u = {}
        for (const k of kinds)
            u[k] = [...new Set([...pipewireUsers[k], ...simulated[k]])]
        // A screencast with no PipeWire stream to name it: "" is an
        // unknown app.
        if (screencastActive && !u.screen.length)
            u.screen.push("")
        return Config.privacy ? u : { mic: [], camera: [], screen: [] }
    }

    // ── Announcements ──
    // A kind going from nothing to in use names its apps for
    // `Config.privacyAnnounceTimeout`. One that was off for less than 2
    // seconds (a stream renegotiating) comes back without a word.
    // Several at once take turns.
    property var announcement: null
    property var pending: []
    property var lastSeen: ({})

    onUsersChanged: {
        const now = Date.now()
        for (const k of kinds) {
            const active = users[k].length > 0
            const was = lastSeen[k]
            if (active && (!was || (!was.active && now - was.since >= 2000)))
                announce(k, Config.privacyAnnounceTimeout)
            if (!was || was.active !== active)
                lastSeen[k] = { active, since: now }
        }
    }

    function announce(kind, ms) {
        pending = pending.filter(a => a.kind !== kind).concat([{ kind, ms }])
        if (!announcement)
            next()
    }

    function next() {
        const a = pending[0]
        pending = pending.slice(1)
        // Gone again while waiting: nothing to say.
        if (a && !users[a.kind].length)
            return next()
        announcement = a ? { kind: a.kind, text: sentence(a.kind), serial: Date.now() } : null
        if (a) {
            announceTimer.interval = a.ms
            announceTimer.restart()
        }
    }

    Timer {
        id: announceTimer
        onTriggered: root.next()
    }

    // A right click on the announcement: on to the next. The dot stays.
    function dismiss() {
        announceTimer.stop()
        next()
    }

    // Clicking a dot: every app on that device, for a little longer.
    function list(kind) {
        if (users[kind].length) {
            pending = pending.filter(a => a.kind !== kind)
            pending.unshift({ kind, ms: Config.privacyListTimeout })
            announceTimer.stop()
            next()
        }
    }

    // One app: "Firefox is using the microphone", "OBS is sharing the
    // screen". Several, which wouldn't fit as a sentence: "Microphone –
    // Firefox, Discord". None known (a screencopy recorder): "Something is
    // recording the screen".
    function sentence(kind) {
        const apps = users[kind].filter(a => a !== "")
        if (!apps.length)
            return kind === "screen" ? "Something is recording the screen"
                : `Something is using the ${noun(kind)}`
        if (apps.length > 1)
            return `${title(kind)} – ${apps.join(", ")}`
        return kind === "screen" ? `${apps[0]} is sharing the screen`
            : `${apps[0]} is using the ${noun(kind)}`
    }

    function title(kind) {
        return kind === "mic" ? "Microphone" : kind === "camera" ? "Camera" : "Screen sharing"
    }

    function glyph(kind) {
        return kind === "mic" ? "\u{f036c}" : kind === "camera" ? "\u{f0100}" : "\u{f0379}"
    }

    function noun(kind) {
        return kind === "mic" ? "microphone" : kind
    }

    // ── Privacy tests ──
    // Made-up users, without PipeWire (AGENTS.md, Testing).
    // fake-capture.sh makes real PipeWire ones without a real device.
    IpcHandler {
        target: "privacy"

        function add(kind: string, app: string): void {
            const s = Object.assign({}, root.simulated)
            s[kind] = [...s[kind].filter(a => a !== app), app]
            root.simulated = s
        }
        function drop(kind: string, app: string): void {
            const s = Object.assign({}, root.simulated)
            s[kind] = s[kind].filter(a => a !== app)
            root.simulated = s
        }
        // What clicking that kind's dot does.
        function list(kind: string): void {
            root.list(kind)
        }
        function clear(): void {
            root.simulated = { mic: [], camera: [], screen: [] }
        }
        // Every link group as Quickshell sees it, for when a dot is
        // missing or wrong.
        function links(): string {
            return root.groups.map(g =>
                `${g.source?.name} [${g.source?.properties["media.class"]}] -> ${g.target?.name} `
                + `[${g.target?.properties["media.class"]}] state ${g.state} kind ${root.kindOf(g.source)}`).join("\n")
        }
        function users(): string {
            return root.kinds.map(k => `${k}: ${root.users[k].map(a => a || "?").join(", ")}`).join("\n")
        }
    }
}
