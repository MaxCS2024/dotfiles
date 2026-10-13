pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQml
import QtQuick

// The notification daemon (AGENTS.md, Notifications). Each notification
// becomes a transient in the queue: normal and low ones wait for a break
// (up to 45 s), critical ones show at once and then stay, small, until
// dismissed. The hold mode (the research brief's, in place of DND) keeps
// all but critical ones back and shows how many are waiting.
Singleton {
    id: root

    // ── Taking over from dunst ──
    // Only one program can own org.freedesktop.Notifications. dunst holds
    // it as a D-Bus-started user unit, so the island stops that unit
    // first and then registers. When the island quits, the name is free
    // again and the next notification starts dunst on its own.
    property bool serving: false

    Process {
        running: Config.notifications
        command: ["systemctl", "--user", "stop", "dunst.service"]
        onExited: root.serving = true
    }

    Instantiator {
        active: root.serving

        NotificationServer {
            keepOnReload: true
            actionsSupported: true
            bodySupported: true
            bodyMarkupSupported: true
            imageSupported: true
            persistenceSupported: true
            onNotification: n => root.arrived(n)
        }
    }

    // Says who owns the name, a second after registering, in the log: a
    // notification arriving between dunst stopping and the island
    // registering would have started dunst again.
    Timer {
        running: root.serving
        interval: 1000
        onTriggered: owner.running = true
    }
    Process {
        id: owner
        command: ["sh", "-c", "busctl --user status org.freedesktop.Notifications | sed -n 's/^Comm=//p'"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "quickshell" && text.trim() !== "qs")
                    console.warn(`island: org.freedesktop.Notifications is owned by "${text.trim()}", not the island`)
            }
        }
    }

    // ── Arriving ──
    function arrived(n) {
        n.tracked = true
        n.closed.connect(() => root.closed(n))
        // A replacement (an app updating its notification, "Copying… 90%")
        // changes this same object; it isn't announced again.
        n.summaryChanged.connect(() => root.replaced(n))
        n.bodyChanged.connect(() => root.replaced(n))
        if (holding && n.urgency !== NotificationUrgency.Critical) {
            hold(n)
            return
        }
        show(n, false)
    }

    // Critical: shown at once, for `notificationUrgentTimeout`, then kept
    // as a compact activity until dismissed; so is one that asks never to
    // expire (timeout 0), after its usual time. Others: their own timeout
    // (ms) if they give one, else by urgency. Normal and low wait for a
    // break unless `now` (released from hold, on demand).
    function show(n, now) {
        const critical = n.urgency === NotificationUrgency.Critical
        const own = n.expireTimeout > 0 ? Math.round(n.expireTimeout) : 0
        const timeout = critical ? Config.notificationUrgentTimeout
            : own || (n.urgency === NotificationUrgency.Low ? Config.notificationLowTimeout : Config.notificationTimeout)
        const spec = {
            key: key(n),
            transient: true,
            profile: critical ? "urgent" : "notification",
            face: "notification",
            notification: n,
            icon: "\u{f009a}",
            label: n.summary,
            progress: -1,
            timeout,
            onEnd: reason => root.ended(n, reason),
        }
        if (now)
            spec.defer = 0
        ActivityQueue.submit(spec)
    }

    function key(n) {
        return "notification:" + n.id
    }

    // Stays (small) when its time is up: critical, or never to expire.
    function keeps(n) {
        return n.urgency === NotificationUrgency.Critical || n.expireTimeout === 0
    }

    // Updated in place by its app: shown again with the new text, its
    // time started over. One held stays held; one that left stays gone.
    function replaced(n) {
        if (ActivityQueue.find(key(n)))
            show(n, false)
    }

    // The queue ended it: dismissed by the user, or its time ran out. One
    // that keeps stays as a compact activity instead.
    function ended(n, reason) {
        if (reason === "dismissed") {
            n.dismiss()
        } else if (keeps(n)) {
            ActivityQueue.submit({
                key: key(n),
                transient: false,
                profile: n.urgency === NotificationUrgency.Critical ? "urgent" : "notification",
                face: "notification",
                notification: n,
                icon: "\u{f009a}",
                label: n.summary,
                progress: -1,
                timeout: 0,
                onEnd: reason => root.ended(n, reason),
            })
        } else {
            n.expire()
        }
    }

    // Closed by the app, or after the island dismissed or expired it.
    function closed(n) {
        ActivityQueue.remove(key(n))
        if (held.includes(n)) {
            held = held.filter(h => h !== n)
            syncHold()
        }
    }

    // ── Actions ──
    // A click on the notification: its default action if it has one,
    // else it is just dismissed. A button: that action. Either way it
    // leaves, unless it is resident (it stays until the app closes it).
    function invoke(n, action) {
        const a = action ?? Array.from(n.actions).find(x => x.identifier === "default")
        if (a)
            a.invoke()
        if (!n.resident) {
            ActivityQueue.remove(key(n))
            n.dismiss()
        }
    }

    // The buttons: every action but the default (the click does that),
    // at most three.
    function buttons(n) {
        return Array.from(n?.actions ?? []).filter(a => a.identifier !== "default" && a.text !== "").slice(0, 3)
    }

    // The picture: the notification's image, else the app's icon (a path
    // or a theme name), else its desktop entry's icon; "" for none, which
    // draws the bell. A theme name, as an image ("image://icon/name") or
    // an icon, is looked up first: a missing one would draw Quickshell's
    // checkerboard. The lookup needs the icon theme, which the island
    // gets from GTK (QT_QPA_PLATFORMTHEME=gtk3, see Testing).
    function iconSource(n) {
        if (!n)
            return ""
        if (n.image.startsWith("image://icon/")) {
            const found = Quickshell.iconPath(n.image.slice("image://icon/".length), true)
            if (found)
                return found
        } else if (n.image) {
            return n.image
        }
        const icon = n.appIcon
        if (icon.startsWith("/"))
            return "file://" + icon
        if (icon.startsWith("file://") || icon.startsWith("image://"))
            return icon
        return Quickshell.iconPath(icon, true) || Quickshell.iconPath(n.desktopEntry, true) || ""
    }

    // ── Hold mode ──
    // While holding, every notification but a critical one is kept back,
    // unseen; a compact activity shows how many. "Show" releases them
    // now, in order, without waiting for a break; turning hold off does
    // the same. A middle click on the pill or IPC (`toggleHold`, which a
    // Hyprland bind can run) turn it on and off. No GlobalShortcut: the
    // island crashed on quitting while it held one (AGENTS.md, Testing).
    property bool holding: false
    property var held: []

    function hold(n) {
        held = held.filter(h => h !== n).concat([n])
        syncHold()
    }

    function release() {
        const waiting = held
        held = []
        for (const n of waiting)
            show(n, true)
        syncHold()
    }

    function setHolding(on) {
        holding = on
        if (!on)
            release()
        syncHold()
    }

    // The count, while holding: above media when something is waiting,
    // below it when nothing is.
    function syncHold() {
        if (!holding) {
            ActivityQueue.remove("hold")
            return
        }
        ActivityQueue.submit({
            key: "hold",
            transient: false,
            profile: "hold",
            priority: held.length ? Config.profile("hold").priority : 10,
            face: "hold",
            count: held.length,
            icon: "\u{f009b}",
            label: held.length ? `${held.length} held` : "Holding",
            progress: -1,
            timeout: 0,
            revive: true,
            // A right click on the count stops holding (and shows them).
            onEnd: reason => { if (reason === "dismissed") root.setHolding(false) },
        })
    }

    IpcHandler {
        target: "notifications"

        function hold(on: bool): void { root.setHolding(on) }
        function toggleHold(): void { root.setHolding(!root.holding) }
        function release(): void { root.release() }
        // What clicking it ("default") or one of its buttons does, by the
        // notification's id and the action's identifier.
        function act(id: int, identifier: string): void {
            const a = ActivityQueue.find("notification:" + id)
            const n = a?.notification
            if (n)
                root.invoke(n, Array.from(n.actions).find(x => x.identifier === identifier))
        }
        // What the picture resolves an icon name to ("" for none).
        function icon(name: string): string { return Quickshell.iconPath(name, true) }
        function status(): string {
            return `${root.serving ? "serving" : "not serving"}, ${root.holding ? "holding" : "not holding"}, ${root.held.length} held`
        }
    }
}
