pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The live-activities API (AGENTS.md, Live activities): any script can
// put an activity in the island and take it away, through
// `qs -c island ipc call island <function> ...` or the island-activity
// script beside this file. Timers, downloads and builds are scripts, not
// features of the island.
//
// From the research brief: every activity ends, by the script or by
// time; the user can dismiss any of them; a script sets how much it
// interrupts, at most "medium".
Singleton {
    id: root

    function key(id) {
        return "ipc:" + id
    }

    // "medium" (above media) or "low" (below it). Nothing higher: a
    // script can't interrupt like a critical notification.
    function profile(level) {
        return level === "low" ? "ipcLow" : "ipc"
    }

    function check(id, label) {
        if (!Config.liveActivities)
            return "live activities are off (Config.liveActivities)"
        if (!id)
            return "an id is needed"
        if (!label)
            return "a label is needed"
        return ""
    }

    // A live activity: stays in the island, compact, until the script
    // removes it or its time is up. Without a timeout it lives
    // `Config.liveActivityIdleTimeout` from its last push or update, so
    // a forgotten one goes away. Pushing the same id again updates it.
    function push(id, icon, label, progress, timeout, level) {
        const error = check(id, label)
        if (error)
            return error
        ActivityQueue.submit({
            key: key(id),
            transient: false,
            profile: profile(level),
            face: "",
            icon: icon || "\u{f0ad1}",
            label,
            progress: progress >= 0 ? Math.min(1, progress) : -1,
            timeout: timeout > 0 ? timeout : Config.liveActivityIdleTimeout,
            ipcTimeout: timeout,
        })
        return ""
    }

    // A one-off notice ("Build finished"): takes the island over briefly,
    // waiting for a break first (up to 45 s), like a normal notification.
    function flash(id, icon, label, progress, timeout, level) {
        const error = check(id, label)
        if (error)
            return error
        ActivityQueue.submit({
            key: key(id),
            transient: true,
            profile: profile(level),
            face: "",
            icon: icon || "\u{f0ad1}",
            label,
            progress: progress >= 0 ? Math.min(1, progress) : -1,
            timeout: timeout > 0 ? timeout : Config.transientTimeout,
        })
        return ""
    }

    // Updates that leave the rest alone; each one restarts an idle
    // lifetime. One the user dismissed is updated where it waits, unseen,
    // so it comes back current if they bring it back; it doesn't come
    // back on its own.
    function update(id, fields) {
        const a = ActivityQueue.find(key(id)) ?? ActivityQueue.dismissed[key(id)]
        if (!a)
            return `no activity "${id}"`
        ActivityQueue.submit(Object.assign({
            key: a.key,
            timeout: a.transient ? a.timeout : (a.ipcTimeout > 0 ? a.ipcTimeout : Config.liveActivityIdleTimeout),
        }, fields))
        return ""
    }

    IpcHandler {
        target: "island"

        // icon: a Nerd Font glyph, "" for the default. progress: 0–1, or
        // -1 for none. timeout: ms, 0 for the default. Each returns "" or
        // what was wrong.
        function push(id: string, icon: string, label: string, progress: real, timeout: int): string {
            return root.push(id, icon, label, progress, timeout, "medium")
        }
        function pushLow(id: string, icon: string, label: string, progress: real, timeout: int): string {
            return root.push(id, icon, label, progress, timeout, "low")
        }
        function flash(id: string, icon: string, label: string, progress: real, timeout: int): string {
            return root.flash(id, icon, label, progress, timeout, "medium")
        }
        function flashLow(id: string, icon: string, label: string, progress: real, timeout: int): string {
            return root.flash(id, icon, label, progress, timeout, "low")
        }
        function progress(id: string, value: real): string {
            return root.update(id, { progress: value >= 0 ? Math.min(1, value) : -1 })
        }
        function label(id: string, text: string): string {
            return text ? root.update(id, { label: text }) : "a label is needed"
        }
        function remove(id: string): string {
            if (!ActivityQueue.find(root.key(id)) && !ActivityQueue.dismissed[root.key(id)])
                return `no activity "${id}"`
            ActivityQueue.remove(root.key(id))
            return ""
        }
        // One per line: id, then its label.
        function list(): string {
            return ActivityQueue.activities.filter(a => a.key.startsWith("ipc:"))
                .map(a => `${a.key.slice(4)}\t${a.label}`).join("\n")
        }
    }
}
