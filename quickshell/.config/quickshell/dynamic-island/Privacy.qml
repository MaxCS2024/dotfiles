pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// The privacy indicators (AGENTS.md, Privacy indicators), brought over
// from ../island at the user's request: which apps are using the
// microphone, the camera or the screen. The island draws a coloured dot
// per device in use beside the pill (`users`), and announces a device
// starting to be used, and the apps on a clicked dot, as a notice.
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
            // Quickshell's own level meters (the dictation waveform, the
            // settings window's input level) read the microphone without
            // recording it.
            if (kind === "mic" && ["quickshell", "qs"].includes(String(name).toLowerCase()))
                continue
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
        return u
    }

    // ── Announcements ──
    // A kind going from nothing to in use is announced as a notice ("Firefox
    // is using the microphone"). One that was off for less than 2 seconds
    // (a stream renegotiating) comes back without a word. Several at once
    // take turns, 3 seconds each, the notice's own length.
    property var pending: []
    property var lastSeen: ({})

    onUsersChanged: {
        const now = Date.now()
        for (const k of kinds) {
            const active = users[k].length > 0
            const was = lastSeen[k]
            if (active && (!was || (!was.active && now - was.since >= 2000)))
                announce(k)
            if (!was || was.active !== active)
                lastSeen[k] = { active, since: now }
        }
    }

    // The microphone isn't announced while dictating: the dictation face
    // already shows it listening, and the notice would cover the waveform
    // as the user starts speaking. The orange dot still shows.
    function announce(kind) {
        if (kind === "mic" && Dictation.busy)
            return
        pending = pending.filter(k => k !== kind).concat([kind])
        if (!turn.running)
            next()
    }

    function next() {
        while (pending.length) {
            const kind = pending[0]
            pending = pending.slice(1)
            if (users[kind].length) {
                say(kind)
                turn.restart()
                return
            }
        }
    }

    Timer {
        id: turn
        interval: 3000
        onTriggered: root.next()
    }

    Connections {
        target: Dictation
        function onBusyChanged() {
            if (Dictation.busy)
                root.pending = root.pending.filter(k => k !== "mic")
        }
    }

    // One app: "Firefox is using the microphone", "OBS is sharing the
    // screen". Several: "Microphone – Firefox, Discord". None known (a
    // screencopy recorder): "Something is recording the screen". The
    // apps are the notice's name, the part cut with "…" when long.
    function say(kind) {
        const apps = users[kind].filter(a => a !== "")
        const glyph = kind === "mic" ? "\u{f036c}" : kind === "camera" ? "\u{f0100}" : "\u{f0379}"
        if (!apps.length)
            Controls.notice(glyph, kind === "screen" ? "Something is recording the screen"
                : `Something is using the ${noun(kind)}`, "", "")
        else if (apps.length > 1)
            Controls.notice(glyph, `${title(kind)} – `, apps.join(", "), "")
        else
            Controls.notice(glyph, "", apps[0], kind === "screen" ? " is sharing the screen" : ` is using the ${noun(kind)}`)
    }

    // A click on a dot: who is using that device, now.
    function list(kind) {
        if (users[kind].length) {
            turn.stop()
            pending = pending.filter(k => k !== kind)
            say(kind)
            turn.restart()
        }
    }

    function noun(kind) {
        return kind === "mic" ? "microphone" : kind
    }

    function title(kind) {
        return kind === "mic" ? "Microphone" : kind === "camera" ? "Camera" : "Screen sharing"
    }

    // The dots' colours: orange, green, red.
    function color(kind) {
        return kind === "mic" ? "#ff9f0a" : kind === "camera" ? "#30d158" : "#ff453a"
    }

    // ── Privacy tests ──
    // Made-up users, without PipeWire (AGENTS.md, Privacy indicators).
    // ../island/fake-capture.sh makes real PipeWire ones without a real
    // device.
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
        function clear(): void {
            root.simulated = { mic: [], camera: [], screen: [] }
        }
        // What clicking that kind's dot does.
        function list(kind: string): void {
            root.list(kind)
        }
        function users(): string {
            return root.kinds.map(k => `${k}: ${root.users[k].map(a => a || "?").join(", ")}`).join("\n")
        }
    }
}
