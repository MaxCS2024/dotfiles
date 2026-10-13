pragma Singleton

import Quickshell
import Quickshell.Hyprland
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
    //   profile    its interruption profile (Config.profiles), which sets
    //              its priority and how the pill moves for it
    //   priority   higher wins; the profile's unless given
    //   timeout    ms. A transient shows this long, counted only while it
    //              is on screen; a persistent one lives this long (0: until
    //              removed)
    //   icon, label, progress (0–1, or -1 for none)
    //   face       the face that draws it ("osd", or "" for the generic one)
    //   waits      for a transient: false drops it, instead of queueing it,
    //              while the island is held open (a level is stale by then)
    //   revive     brings back a key the user dismissed; without it, a
    //              dismissed persistent activity stays away (see dismiss)
    //   defer      for a transient: ms it may wait for a break before it
    //              shows; the profile's unless given (see Deferral)
    //   onEnd      optional function(reason), called when the queue ends
    //              it: "expired" (its time ran out) or "dismissed" (the
    //              user). Not when its feature removes or replaces it.
    // Objects are replaced, never changed in place, so bindings see updates.
    property var activities: []

    // Set by the island while it is expanded: transients wait, their
    // timers stopped, until it closes.
    property bool holdTransients: false

    // Set by the island while the pointer is on a transient: its time
    // stops, and starts over when the pointer leaves.
    property bool paused: false
    onPausedChanged: {
        if (paused)
            transientTimer.stop()
        else if (shownTransient)
            transientTimer.restart()
    }

    onHoldTransientsChanged: {
        if (holdTransients)
            activities = activities.filter(a => !a.transient || a.waits)
    }

    readonly property var transients: activities.filter(a => a.transient && !a.deferredUntil)
    readonly property var persistents: activities.filter(a => !a.transient)
    readonly property var shownTransient: holdTransients ? null : (transients[0] ?? null)
    readonly property var topPersistent: persistents[0] ?? null

    property int nextSince: 0

    // Keys of persistent activities the user dismissed. Their feature's
    // updates are ignored until one comes with `revive` (media: the
    // player starting or pausing again, not a new track).
    property var dismissed: ({})

    // Adds the activity, or updates the one with the same key. Fields
    // left out keep their old value (or the default, for a new one).
    function submit(spec) {
        if (dismissed[spec.key]) {
            if (!spec.revive)
                return
            delete dismissed[spec.key]
        }
        const old = find(spec.key)
        const a = Object.assign({
            transient: false,
            profile: "",
            timeout: 0,
            icon: "",
            label: "",
            progress: -1,
            face: "",
            waits: true,
        }, old ?? {}, spec)
        // Given, else the profile's when the submit names one (a critical
        // battery notice replacing a low one), else as before.
        a.priority = spec.priority
            ?? (spec.profile !== undefined || !old ? Config.profile(a.profile).priority : old.priority)
        a.defer = spec.defer
            ?? (spec.profile !== undefined || !old ? Config.profile(a.profile).defer ?? 0 : old.defer)
        // A new deferrable transient waits. An update to one of the same
        // profile keeps its state (still waiting, or already up); another
        // kind under the same key (low battery after "Charger connected")
        // is new.
        const update = old && old.profile === a.profile
        const waiting = update ? old.deferredUntil : (a.transient && a.defer > 0 ? Date.now() + a.defer : 0)
        a.deferredUntil = a.transient && a.defer > 0 ? waiting : 0
        delete a.revive
        if (a.transient && !a.waits && holdTransients) {
            remove(a.key)
            return
        }
        if (a.transient && a.timeout <= 0)
            a.timeout = Config.transientTimeout
        a.since = old ? old.since : nextSince++
        // Bumped on every submit, so a transient shown again restarts its timer.
        a.revision = old ? old.revision + 1 : 0
        a.expiresAt = !a.transient && a.timeout > 0 ? Date.now() + a.timeout : 0
        activities = activities.filter(x => x.key !== a.key).concat([a]).sort(compare)
        scheduleExpiry()
        scheduleRelease()
    }

    // A feature taking its activity away also forgets a dismissal: the
    // next one is new.
    function remove(key) {
        delete dismissed[key]
        if (!find(key))
            return
        activities = activities.filter(a => a.key !== key)
        scheduleExpiry()
    }

    // The user's dismissal (right click): the activity leaves now. A
    // transient is simply gone; a persistent one stays away until its
    // feature revives it or removes it.
    function dismiss(key) {
        const a = find(key)
        if (!a)
            return
        remove(key)
        if (!a.transient)
            dismissed[key] = true
        a.onEnd?.("dismissed")
    }

    // The queue ending one itself: its time ran out.
    function expire(key) {
        const a = find(key)
        if (!a)
            return
        remove(key)
        a.onEnd?.("expired")
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
        if (!paused)
            transientTimer.restart()
    }

    Timer {
        id: transientTimer
        onTriggered: root.expire(root.timedKey)
    }

    // ── Deferral ──
    // From the research brief: a deferrable transient (low battery; later
    // normal notifications and IPC activities) waits for a break, a moment
    // the user is between things: switching workspace, moving focus, or
    // closing a window. It shows then, or when its `defer` runs out,
    // whichever comes first, in its order of arrival.
    // activewindowv2 also comes again, same address, whenever the focused
    // window's title changes (a terminal's spinner does it several times
    // a second), so only a new address counts as moving focus.
    property string focusedAddress: ""

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activewindowv2") {
                if (event.data === root.focusedAddress)
                    return
                root.focusedAddress = event.data
                root.release()
            } else if (event.name === "workspace" || event.name === "closewindow")
                root.release()
        }
    }

    function release() {
        if (!activities.some(a => a.deferredUntil))
            return
        activities = activities.map(a => a.deferredUntil ? Object.assign({}, a, { deferredUntil: 0 }) : a)
        scheduleRelease()
    }

    function scheduleRelease() {
        const ends = activities.filter(a => a.deferredUntil).map(a => a.deferredUntil)
        if (!ends.length) {
            releaseTimer.stop()
            return
        }
        releaseTimer.interval = Math.max(0, Math.min(...ends) - Date.now())
        releaseTimer.restart()
    }

    Timer {
        id: releaseTimer
        onTriggered: {
            const now = Date.now()
            root.activities = root.activities.map(a =>
                a.deferredUntil && a.deferredUntil <= now ? Object.assign({}, a, { deferredUntil: 0 }) : a)
            root.scheduleRelease()
        }
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
            for (const a of root.activities.filter(a => a.expiresAt && a.expiresAt <= now))
                root.expire(a.key)
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
        // What a break (workspace switch, focus change, window closing) does.
        function release(): void {
            root.release()
        }
        // What a right click on the pill does to that activity.
        function dismiss(key: string): void {
            root.dismiss(key)
        }
        function clear(): void {
            root.activities = []
            root.scheduleExpiry()
        }
        function list(): string {
            return root.activities.map(a =>
                `${a.deferredUntil ? `deferred ${Math.round((a.deferredUntil - Date.now()) / 1000)}s ` : ""}`
            + `${a.transient ? "transient " : "persistent"} ${a.priority} ${a.key} – ${a.label}`).join("\n")
                + Object.keys(root.dismissed).map(k => `\ndismissed ${k}`).join("")
        }
    }
}
