pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Resolved once at startup: the backlight device's sysfs path, e.g.
    // /sys/class/backlight/intel_backlight. Reads go straight through
    // FileView against that path (no subprocess per read); writes go
    // through brightnessctl itself, since sysfs brightness is not
    // directly writable without root — brightnessctl relies on udev
    // rules (typically the `video` group) to get write access safely.
    property string devicePath: ""
    property int maxBrightness: 0
    property real percent: 0        // 0-100
    readonly property bool available: devicePath !== ""

    Component.onCompleted: detectProc.running = true

    // -c backlight filters out unrelated brightness-capable devices
    // (e.g. keyboard backlight LEDs) that brightnessctl -l also lists.
    Process {
        id: detectProc
        command: ["sh", "-c",
            "brightnessctl -l -c backlight 2>/dev/null | " +
            "awk -F\"'\" '/Device/ {print $2; exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim()
                if (name === "") { root.devicePath = ""; return }
                root.devicePath = "/sys/class/backlight/" + name
                maxFile.reload()
                curFile.reload()
            }
        }
    }

    FileView {
        id: maxFile
        printErrors: false
        path: root.devicePath !== "" ? root.devicePath + "/max_brightness" : ""
        onLoaded: {
            const v = parseInt(text().trim())
            if (!isNaN(v)) root.maxBrightness = v
        }
    }

    // sysfs attribute files aren't regular page-cache-backed files, and
    // inotify support for them (which watchChanges relies on) is
    // inconsistent — the backlight driver does call sysfs_notify() on a
    // change, but whether that reliably reaches us depends on kernel/
    // driver specifics, and in practice it was arriving late or batched
    // rather than promptly. watchChanges is kept as a free "instant
    // when it happens to fire" path, but a fast poll below is what
    // actually guarantees a bounded, low-latency update — the same
    // fix that ended up being needed for the volume singleton, whose
    // purely reactive notify chain had the same reliability problem.
    FileView {
        id: curFile
        printErrors: false
        watchChanges: true
        path: root.devicePath !== "" ? root.devicePath + "/brightness" : ""
        onFileChanged: reload()
        onLoaded: {
            const v = parseInt(text().trim())
            if (!isNaN(v) && root.maxBrightness > 0) {
                const p = Math.min(100, (v / root.maxBrightness) * 100)
                if (p !== root.percent) root._burst()
                root.percent = p
            }
        }
    }

    // The Hyprland keybinds call brightnessctl directly (see
    // hypr/modules/binds/media.lua), not through setPercent()/adjustBy()
    // below, so this shell can't assume it always knows a change is
    // coming. Instead, burst fast polling whenever a reload — from
    // inotify or from the slow poll itself — actually reveals a changed
    // value, and again right when this shell issues its own write. That
    // keeps a single key press to at worst one slow-poll interval (down
    // from unconditional 30ms, but bounded), while a burst of repeated
    // presses or a dragged slider stays snappy throughout, and idle time
    // (the overwhelming common case) polls slowly. FileView.reload() on
    // a sysfs file is a cheap direct read, no subprocess spawn, so the
    // fast phase costs nothing meaningful even though it's frequent —
    // it just isn't run forever.
    property bool _fastPoll: false

    Timer {
        id: fastPollEnd
        interval: 1000
        onTriggered: root._fastPoll = false
    }

    function _burst() {
        root._fastPoll = true
        fastPollEnd.restart()
    }

    Timer {
        interval: root._fastPoll ? 30 : 400
        running: root.devicePath !== ""
        repeat: true
        onTriggered: curFile.reload()
    }

    // ── Writes (everything goes through brightnessctl) ───
    Process { id: setProc }

    // No -e (exponent) — see prior note: brightnessctl's -e applies a
    // perceptual curve that doesn't match the plain linear (raw/max)
    // percentage read above, causing uneven step sizes. -n2 is kept as
    // a floor so brightness never drops to a fully black/unreadable
    // screen.
    function setPercent(p) {
        if (!root.available) return
        p = Math.max(0, Math.min(100, Math.round(p)))
        setProc.command = ["brightnessctl", "-n2", "set", p + "%"]
        setProc.running = false
        setProc.running = true
        root._burst()
    }

    function adjustBy(deltaPercent) {
        if (!root.available) return
        const mag = Math.abs(Math.round(deltaPercent))
        const dir = deltaPercent >= 0 ? "+" : "-"
        setProc.command = ["brightnessctl", "-n2", "set", mag + "%" + dir]
        setProc.running = false
        setProc.running = true
        root._burst()
    }
}
