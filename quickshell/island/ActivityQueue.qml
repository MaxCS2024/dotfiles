pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The one queue every feature submits to; features never touch the
// island itself (AGENTS.md, Activity queue). The island reads
// `shownTransient` and `topPersistent` and decides what to draw.
Singleton {
    id: root

    // Every live activity, best first. Each is a plain object:
    //   key        unique; submitting the same key again updates it
    //   transient  true: takes the island over, then gives it back
    //   priority   higher wins (AGENTS.md, Priorities)
    //   timeout    ms. A transient shows this long, counted only while it
    //              is on screen; a persistent one lives this long (0: until
    //              removed)
    //   icon, label, progress (0–1, or -1 for none)
    //   face       the face that draws it; "" for the generic one
    // Objects are replaced, never changed in place, so bindings see updates.
    property var activities: []

    // Set by the island while it is expanded: transients wait, their
    // timers stopped, until it closes.
    property bool holdTransients: false

    readonly property var transients: activities.filter(a => a.transient)
    readonly property var persistents: activities.filter(a => !a.transient)
    readonly property var shownTransient: holdTransients ? null : (transients[0] ?? null)
    readonly property var topPersistent: persistents[0] ?? null

    property int nextSince: 0

    // Adds the activity, or updates the one with the same key. Fields
    // left out keep their old value (or the default, for a new one).
    function submit(spec) {
        const old = find(spec.key)
        const a = Object.assign({
            transient: false,
            priority: 0,
            timeout: 0,
            icon: "",
            label: "",
            progress: -1,
            face: "",
        }, old ?? {}, spec)
        if (a.transient && a.timeout <= 0)
            a.timeout = Config.transientTimeout
        a.since = old ? old.since : nextSince++
        // Bumped on every submit, so a transient shown again restarts its timer.
        a.revision = old ? old.revision + 1 : 0
        a.expiresAt = !a.transient && a.timeout > 0 ? Date.now() + a.timeout : 0
        activities = activities.filter(x => x.key !== a.key).concat([a]).sort(compare)
        scheduleExpiry()
    }

    function remove(key) {
        if (!find(key))
            return
        activities = activities.filter(a => a.key !== key)
        scheduleExpiry()
    }

    function find(key) {
        return activities.find(a => a.key === key) ?? null
    }

    // Higher priority first. Ties: transients first come, first shown;
    // persistents newest first.
    function compare(a, b) {
        if (a.priority !== b.priority)
            return b.priority - a.priority
        return a.transient ? a.since - b.since : b.since - a.since
    }

    // ── Transient timer ──
    // Runs only for the transient on screen. Restarts when a different one
    // comes up or the same one is submitted again, not when anything else
    // in the queue changes.
    property string timedKey: ""
    property int timedRevision: -1

    onShownTransientChanged: {
        const t = shownTransient
        if (!t) {
            transientTimer.stop()
            timedKey = ""
            return
        }
        if (t.key === timedKey && t.revision === timedRevision && transientTimer.running)
            return
        timedKey = t.key
        timedRevision = t.revision
        transientTimer.interval = t.timeout
        transientTimer.restart()
    }

    Timer {
        id: transientTimer
        onTriggered: root.remove(root.timedKey)
    }

    // ── Persistent lifetimes ──
    // One timer, set for whichever persistent activity runs out first.
    function scheduleExpiry() {
        const ends = persistents.filter(a => a.expiresAt > 0).map(a => a.expiresAt)
        if (!ends.length) {
            expiryTimer.stop()
            return
        }
        expiryTimer.interval = Math.max(0, Math.min(...ends) - Date.now())
        expiryTimer.restart()
    }

    Timer {
        id: expiryTimer
        onTriggered: {
            const now = Date.now()
            root.activities = root.activities.filter(a => !a.expiresAt || a.expiresAt > now)
            root.scheduleExpiry()
        }
    }

    // ── Queue tests ──
    // Puts made-up activities in the queue, for test-queue.sh (AGENTS.md,
    // Testing). Not the live-activities API, which is build step 7.
    IpcHandler {
        target: "queue"

        // ms 0: until dropped. progress -1: no bar.
        function persist(key: string, icon: string, label: string, progress: real, priority: int, ms: int): void {
            root.submit({ key, icon, label, progress, priority, timeout: ms, transient: false })
        }
        // ms 0: the default timeout.
        function flash(key: string, icon: string, label: string, progress: real, priority: int, ms: int): void {
            root.submit({ key, icon, label, progress, priority, timeout: ms, transient: true })
        }
        function drop(key: string): void {
            root.remove(key)
        }
        function clear(): void {
            root.activities = []
            root.scheduleExpiry()
        }
        function list(): string {
            return root.activities.map(a =>
                `${a.transient ? "transient " : "persistent"} ${a.priority} ${a.key} – ${a.label}`).join("\n")
        }
    }
}
