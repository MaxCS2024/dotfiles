pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

Singleton {
    id: root

    // Do Not Disturb lives in Settings.dnd (services/Settings.qml) so it
    // persists across a restart — referenced below as Settings.dnd.

    // ── Live popups (plain data, never live QObjects) ────
    // Every row in `popups` is a plain-data snapshot, not a Notification.
    // Two reasons, and both bite in practice:
    //
    //   * A Notification is owned by the server and destroyed the moment it
    //     closes. Anything still holding it — a delegate mid-render, a
    //     binding that has not re-evaluated yet — is reading freed memory.
    //   * Snapshots are the only thing that can be written to disk, which is
    //     what lets a popup survive a shell restart (see popupsStore below).
    //
    // The live objects live in _liveRefs instead, keyed by the server's own
    // notification id, and are only ever reached through actionsFor() and
    // dismiss(). A row whose id is missing from that map is simply one whose
    // sender is gone — which is exactly the state of every restored row.
    property var popups: []
    property var _liveRefs: ({})

    // ── Popup lifetime ───────────────────────────────────
    // Floors, not fixed durations: a sender asking for longer gets it, up to
    // the cap. Critical never expires on its own, and neither does an
    // explicit expire_timeout of 0 — the freedesktop spec defines that as
    // "until dismissed", and the card's close button plus
    // `relay notif dismiss all` are the way out.
    readonly property int lowDuration: 5000
    readonly property int normalDuration: 8000
    readonly property int maxDuration: 30000

    // How long a written-out popup stays worth restoring. A shell restart
    // takes seconds, so anything older than this is a machine that was off
    // or a crash nobody is still waiting on — replaying yesterday's toasts
    // at login would be noise, not recovery.
    readonly property int restoreWindowMs: 60 * 60 * 1000

    // expireTimeout arrives as the raw freedesktop `expire_timeout`, which
    // the spec defines in MILLISECONDS. Quickshell's own docstring says
    // "seconds", but it assigns the D-Bus value through untouched
    // (notification.cpp: `this->bExpireTimeout = expireTimeout`), so the
    // docstring is wrong and no conversion belongs here. Treating it as
    // seconds turned a client's 5000ms request into 83 minutes on screen.
    function durationFor(urgency, expireTimeout) {
        if (urgency === "critical") return 0

        const requested = Number(expireTimeout || 0)
        // -1 is "sender has no opinion, use the default". 0 is "until
        // dismissed" and is honoured as such.
        if (requested === 0) return 0
        const floor = urgency === "low" ? root.lowDuration : root.normalDuration
        if (!isFinite(requested) || requested < 0) return floor
        return Math.min(root.maxDuration, Math.max(floor, Math.round(requested)))
    }

    function _addPopup(row) {
        root.popups = [...root.popups, row]
        root._savePopups()
    }

    // Called by the popup UI once it is done displaying a notification
    // (countdown elapsed, or the user dismissed it). Setting tracked=false is
    // documented as equivalent to calling dismiss().
    function dismiss(row) {
        root.popups = root.popups.filter(r => r.id !== row.id)
        root._savePopups()

        const ref = root._refFor(row)
        if (!ref) return
        delete root._liveRefs[row.originalId]
        try {
            if (ref.tracked) ref.tracked = false
        } catch (e) {
            // Already torn down by the server — nothing left to release.
        }
    }

    function dismissAll() {
        const rows = root.popups
        for (var i = 0; i < rows.length; i++) root.dismiss(rows[i])
    }

    // "Last" is the newest, which is the end of the array — the popup column
    // appends, so the newest card is the bottom one.
    function dismissLast() {
        if (root.popups.length > 0) root.dismiss(root.popups[root.popups.length - 1])
    }

    // A restored row deliberately carries originalId -1 (see _restorePopups),
    // so it can never collide with a fresh notification that happens to have
    // been handed the same id by the new server generation.
    function _refFor(row) {
        if (!row || row.originalId < 0) return null
        return root._liveRefs[row.originalId] || null
    }

    // Live libnotify actions for a row, or [] when the sender is gone. The
    // card renders buttons from this rather than from the row itself, which
    // keeps QObjects out of the persisted data.
    function actionsFor(row) {
        const ref = root._refFor(row)
        if (!ref) return []
        try {
            return ref.actions || []
        } catch (e) {
            return []
        }
    }

    function invokeAction(row, action) {
        try {
            action.invoke()
        } catch (e) {
            // Sender died between the click and the invoke.
        }
        root.dismiss(row)
    }

    // Whether clicking the card body does anything — a relay --exec vector,
    // or a sender-registered "default" action.
    function isActivatable(row) {
        if (root._parseExecArgv(row) !== null) return true
        return root.actionsFor(row).some(a => a && a.identifier === "default")
    }

    function _parseExecArgv(row) {
        if (!row || !row.execArgv) return null
        try {
            const argv = JSON.parse(row.execArgv)
            if (Array.isArray(argv) && argv.length > 0 && String(argv[0]).length > 0)
                return argv.map(String)
        } catch (e) {
            // Not our hint, or malformed — treat the card as inert.
        }
        return null
    }

    // Click action for the card body. The relay-exec-argv hint is a real argv
    // vector, run with execDetached and no shell anywhere in the path, so an
    // argument can never become a command — and because it is plain data it
    // survives to disk, which means a RESTORED popup is still clickable. A
    // third-party client's "default" action only works while its sender is
    // alive, which is the difference that makes the hint worth having.
    function activate(row) {
        const argv = root._parseExecArgv(row)
        if (argv) {
            Quickshell.execDetached(argv)
            root.dismiss(row)
            return
        }

        const actions = root.actionsFor(row)
        for (var i = 0; i < actions.length; i++) {
            if (actions[i] && actions[i].identifier === "default") {
                root.invokeAction(row, actions[i])
                return
            }
        }
        root.dismiss(row)
    }

    // ── History (persisted, plain data) ──────────────────
    // Same shape as a popup row, plus `seen`. History rows outlive both the
    // notification object and the popup, so they can't invoke live actions —
    // but an execArgv row stays runnable, since that is just data.
    property var history: []
    readonly property int unreadCount: root.history.filter(e => !e.seen).length
    readonly property int maxHistory: 100
    property int _nextId: 1

    function _urgencyName(u) {
        if (u === NotificationUrgency.Critical) return "critical"
        if (u === NotificationUrgency.Low) return "low"
        return "normal"
    }

    // Arbitrary hints come through as a plain JS object. Reading one can
    // throw if the object was torn down mid-signal, so every read is guarded.
    function _hint(notif, key) {
        try {
            const v = notif.hints ? notif.hints[key] : undefined
            return v === undefined || v === null ? "" : String(v)
        } catch (e) {
            return ""
        }
    }

    // A hint this desktop's own CLI sets. The prefix is the sender's name, so
    // an application cannot reach these by accident — relay/lib/notif.sh is
    // the only thing that writes them.
    function _toolHint(notif, name) {
        return root._hint(notif, "relay-" + name)
    }

    // Sent by this desktop's own CLI rather than by an application.
    function _isOwnTool(appName) {
        return appName === "relay"
    }

    function _snapshot(notif) {
        return {
            id: root._nextId++,
            originalId: notif.id,
            appName: notif.appName || "Unknown",
            appIcon: notif.appIcon || "",
            summary: notif.summary || "",
            body: notif.body || "",
            image: notif.image || "",
            // relay notif send --glyph: a Nerd Font glyph shown in the icon
            // slot when the sender has no real icon, so the desktop's own
            // toasts get an identity without smuggling a glyph into the
            // summary.
            glyph: root._toolHint(notif, "glyph"),
            execArgv: root._toolHint(notif, "exec-argv"),
            urgency: root._urgencyName(notif.urgency),
            expireTimeout: notif.expireTimeout,
            time: Date.now(),
            restored: false,
            seen: false
        }
    }

    // Fields a client can change in place. Anything else on the row (id,
    // originalId, time) identifies it and must not move.
    readonly property var _mutableFields: ["appName", "appIcon", "summary", "body", "image", "glyph", "execArgv", "urgency", "expireTimeout"]

    // A client updating a notification through replaces_id does NOT produce a
    // second onNotification — quickshell writes the new content onto the
    // object we are already holding and returns (server.cpp only emits for a
    // notification it just created). So nothing reaches the screen unless we
    // watch the property signals and re-copy. Without this, `relay notif send
    // -r <id>` silently did nothing.
    function _watchForUpdates(notif, rowId) {
        const signals = ["summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged", "imageChanged", "urgencyChanged", "expireTimeoutChanged", "hintsChanged"]
        const refresh = () => root._refreshRow(notif, rowId)
        for (var i = 0; i < signals.length; i++) {
            const sig = notif[signals[i]]
            if (sig && typeof sig.connect === "function") sig.connect(refresh)
        }
    }

    function _refreshRow(notif, rowId) {
        var updated
        try {
            updated = {
                appName: notif.appName || "Unknown",
                appIcon: notif.appIcon || "",
                summary: notif.summary || "",
                body: notif.body || "",
                image: notif.image || "",
                glyph: root._toolHint(notif, "glyph"),
                execArgv: root._toolHint(notif, "exec-argv"),
                urgency: root._urgencyName(notif.urgency),
                expireTimeout: notif.expireTimeout
            }
        } catch (e) {
            // Torn down by the server while the signal was in flight.
            return
        }

        const merge = rows => {
            var changed = false
            const next = rows.map(r => {
                if (r.id !== rowId) return r
                if (root._mutableFields.every(f => r[f] === updated[f])) return r
                changed = true
                return Object.assign({}, r, updated)
            })
            return changed ? next : null
        }

        const nextPopups = merge(root.popups)
        if (nextPopups) {
            root.popups = nextPopups
            root._savePopups()
        }
        const nextHistory = merge(root.history)
        if (nextHistory) root.history = nextHistory
    }

    // Rows for notifications this shell generates itself (network status,
    // DNS changes, package install results, screenshots) rather than ones
    // received over D-Bus. They never pass through
    // NotificationServer.onNotification below, so they need their own way
    // in. `urgency` accepts the same "low"/"normal"/"critical" strings as
    // _urgencyName(); originalId -1 marks a row no sender owns, which is
    // what keeps actionsFor() and the live-ref map away from it.
    function _manualRow(title, message, urgency, appName, glyph) {
        return {
            id: root._nextId++,
            originalId: -1,
            appName: appName || "Quickshell",
            appIcon: "",
            summary: title || "",
            body: message || "",
            image: "",
            glyph: glyph || "",
            execArgv: "",
            urgency: urgency || "normal",
            expireTimeout: -1,
            time: Date.now(),
            restored: false,
            seen: false
        }
    }

    // History only. For callers that already put something on screen
    // themselves — the settings panel's own toast, the screenshot popup —
    // and just need the event to survive being looked back at.
    function addManual(title, message, urgency, appName) {
        root.history = [root._manualRow(title, message, urgency, appName),
            ...root.history].slice(0, root.maxHistory)
    }

    // History *and* the toast stack, for a shell-generated event that has
    // no UI of its own. Deliberately runs the same two gates a D-Bus
    // notification passes through (see onNotification): DND silences it to
    // history, and an idle screen keeps it off the stack rather than
    // stacking toasts nobody is there to read. Anything that reaches this
    // is worth a history row either way, so the write happens first.
    function post(title, message, urgency, appName, glyph) {
        const row = root._manualRow(title, message, urgency, appName, glyph)
        root.history = [row, ...root.history].slice(0, root.maxHistory)

        if (Settings.dnd && !root._bypassesDnd(row)) return
        if (Idle.isIdle) return
        root._addPopup(row)
    }

    function markAllSeen() {
        root.history = root.history.map(e => Object.assign({}, e, { seen: true }))
    }

    function removeHistoryEntry(id) {
        root.history = root.history.filter(e => e.id !== id)
    }

    function clearHistory() {
        root.history = []
    }

    // ── Do Not Disturb ───────────────────────────────────
    // The bypass list is deliberately short: DND is worth nothing if
    // everything can opt out of it.
    //
    //   * appName "relay" — a confirmation for something the user JUST did
    //     ("Theme updated", "Dotfiles synced"). They asked for it a second
    //     ago, so it shows.
    //   * critical AND a bare-CLI sender — emergency alerts from system
    //     scripts. Deliberately NOT "critical" alone: chat clients set
    //     urgency=critical routinely to force visibility, and they identify
    //     themselves by brand (Discord, Vesktop, Slack), so they fall outside
    //     this rule while `notify-send -u critical` from a script does not.
    function _bypassesDnd(row) {
        if (root._isOwnTool(row.appName)) return true
        return row.urgency === "critical" && (row.appName === "notify-send" || row.appName === "Unknown")
    }

    // A notification nobody looks back at: the sender set the freedesktop
    // `transient` hint, or it is one of the desktop's own confirmations.
    // Only decides whether a DND-silenced one is worth recording — anything
    // that actually reached the screen lands in history either way.
    // `transient` is a reserved word to QML's parser, so the local can't be
    // named after the hint it reads.
    function _isEphemeral(notif, row) {
        var isTransient = false
        try {
            isTransient = !!notif["transient"]
        } catch (e) {
            isTransient = false
        }
        return isTransient || root._isOwnTool(row.appName)
    }

    function setDnd(value) { Settings.dnd = !!value }
    function toggleDnd() { Settings.dnd = !Settings.dnd }

    // ── Receiving notifications ──────────────────────────
    NotificationServer {
        id: server

        bodySupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        bodyImagesSupported: true
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: false
        persistenceSupported: true
        inlineReplySupported: false
        // Persistence is handled ourselves via the plain-data history and
        // popup files below, so there's no need to have the server re-emit
        // prior-generation notifications on reload.
        keepOnReload: false

        onNotification: notif => {
            // Without tracked=true the object is destroyed as soon as this
            // handler returns, taking the live actions with it.
            notif.tracked = true

            const row = root._snapshot(notif)
            root._liveRefs[row.originalId] = notif
            root._watchForUpdates(notif, row.id)

            // Connected before anything can untrack this notification below.
            // Untracking is documented as equivalent to dismissing, and the
            // server destroys the object when it closes — so wiring the
            // handler up afterwards would be reaching into freed memory.
            // Covers the sender cancelling a notification itself while it is
            // still on screen. Guarded because a later notification may have
            // reused this id and taken over the map slot.
            notif.closed.connect(() => {
                if (root._liveRefs[row.originalId] === notif) delete root._liveRefs[row.originalId]
                root.popups = root.popups.filter(r => r.id !== row.id)
                root._savePopups()
            })

            const silenced = Settings.dnd && !root._bypassesDnd(row)

            // A silenced notification never reaches the screen, so history is
            // the only record it can leave — and "what did I miss" is exactly
            // what history is for. Skipped only when there'd be nothing worth
            // looking back at.
            if (!silenced || !root._isEphemeral(notif, row))
                root.history = [row, ...root.history].slice(0, root.maxHistory)

            // Idle suppression only skips the on-screen popup; the history
            // write above already happened, so nothing is lost while away.
            if (!silenced && !Idle.isIdle && !notif.lastGeneration) {
                root._addPopup(row)
            } else {
                delete root._liveRefs[row.originalId]
                try {
                    notif.tracked = false
                } catch (e) {
                    // Already gone.
                }
            }
        }
    }

    // ── Disk persistence ─────────────────────────────────
    //
    // Two files, because they answer different questions:
    //   notifications.json        — what has arrived (history)
    //   notification-popups.json  — what is on screen RIGHT NOW
    //
    // The second is what makes a shell restart non-destructive: restart with
    // three toasts up and they come back, still clickable if they carry an
    // exec vector. Without it, restarting the shell to pick up a QML edit
    // silently threw away whatever was on screen.
    readonly property string _historyPath: Quickshell.dataPath("notifications.json")
    readonly property string _popupsPath: Quickshell.dataPath("notification-popups.json")

    // Two files, two stores. The probe, the guarded first write, the
    // corrupt-file fallback and the debounce are services/JsonStore.qml's;
    // its header has the hazards they answer.
    JsonStore {
        id: historyStore
        path: root._historyPath
        snapshot: () => root.history
        onRestored: (data) => {
            if (!Array.isArray(data)) return
            root.history = data
            root._nextId = data.reduce((m, e) => Math.max(m, e.id || 0), 0) + 1
        }
    }

    // A shorter debounce than history's: this file only earns its keep if
    // the write lands before the restart it is meant to survive.
    //
    // The store flips `loaded` before it hands the data over, which this
    // one depends on: _restorePopups() saves as it restores, to leave the
    // file describing what is actually on screen rather than what the
    // previous generation left behind, and that write would otherwise be
    // swallowed by the not-loaded-yet guard.
    JsonStore {
        id: popupsStore
        path: root._popupsPath
        debounce: 150
        snapshot: () => root.popups
        onRestored: (data) => {
            if (Array.isArray(data)) root._restorePopups(data)
        }
    }

    // Rows written by the previous shell generation. Their senders consider
    // them delivered and the new server hands out ids from 1 again, so
    // originalId is cleared: a live id match would otherwise dismiss or
    // re-render an unrelated fresh notification. That makes a restored row
    // pure data — no live actions, but its exec vector still runs.
    function _restorePopups(rows) {
        const cutoff = Date.now() - root.restoreWindowMs
        const restored = rows
            .filter(r => r && typeof r.time === "number" && r.time >= cutoff)
            .map(r => Object.assign({}, r, { originalId: -1, restored: true }))
        if (restored.length === 0) return

        root.popups = [...restored, ...root.popups]
        root._nextId = Math.max(root._nextId, restored.reduce((m, e) => Math.max(m, e.id || 0), 0) + 1)
        root._savePopups()
    }

    function _savePopups() { popupsStore.save() }

    onHistoryChanged: historyStore.save()

    // ── IPC (relay notif ...) ───────────────────────────
    // The control surface relay/lib/notif.sh drives. Sending goes over D-Bus
    // like any other client; everything here is shell state that D-Bus has no
    // concept of — what is on screen, what has been seen, whether DND is on.
    IpcHandler {
        target: "notifications"

        function ping(): string { return "ok" }
        function dndState(): string { return Settings.dnd ? "on" : "off" }
        function isDnd(): string { return Settings.dnd ? "true" : "false" }

        function setDnd(value: string): string {
            root.setDnd(value === "true" || value === "on" || value === "1")
            return Settings.dnd ? "on" : "off"
        }

        function toggleDnd(): string {
            root.toggleDnd()
            return Settings.dnd ? "on" : "off"
        }

        function dismissLast(): string {
            root.dismissLast()
            return "ok"
        }

        function dismissAll(): string {
            root.dismissAll()
            return "ok"
        }

        function invokeLast(): string {
            if (root.popups.length === 0) return "none"
            root.activate(root.popups[root.popups.length - 1])
            return "ok"
        }

        function history(): string { return JSON.stringify(root.history) }

        // What is on screen right now, oldest first — the same rows the
        // toast stack is drawing, including any restored from the last
        // generation.
        function popups(): string { return JSON.stringify(root.popups) }

        function clearHistory(): string {
            root.clearHistory()
            return "ok"
        }
    }
}
