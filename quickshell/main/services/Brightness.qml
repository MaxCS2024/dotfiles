pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Resolved once at startup: the backlight device, e.g.
    // intel_backlight. Reads go straight through FileView against its
    // sysfs files (no subprocess per read). Writes go through
    // systemd-logind's Session.SetBrightness over busctl: the sysfs
    // brightness file is root's, and logind is what lets the user at the
    // seat write it without being in the `video` group. It is also what
    // brightnessctl called on this machine before this file stopped
    // needing it — the same write, one package fewer.
    property string device: ""
    readonly property string devicePath: device !== "" ? "/sys/class/backlight/" + device : ""
    property int maxBrightness: 0
    property int raw: 0
    property real percent: 0        // 0-100
    readonly property bool available: device !== ""

    // Never below 1%: a screen at zero is a screen you cannot see to fix,
    // and the key that got you there is invisible too. The same floor as
    // `relay brightness`.
    readonly property int floorPercent: 1

    Component.onCompleted: detectProc.running = true

    // The first device under /sys/class/backlight — what `brightnessctl
    // -l -c backlight` listed first. Keyboard LEDs live under
    // /sys/class/leds, so they were never candidates here.
    Process {
        id: detectProc
        command: ["sh", "-c",
            "for d in /sys/class/backlight/*; do [ -e \"$d\" ] && { basename \"$d\"; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.device = text.trim()
                if (root.device === "") return
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
                root.raw = v
                const p = Math.min(100, (v / root.maxBrightness) * 100)
                if (p !== root.percent) root._burst()
                root.percent = p
            }
        }
    }

    // Not every change comes through this file: `relay brightness` writes
    // through logind on its own, so this shell can't assume it always
    // knows a change is coming. Instead, burst fast polling whenever a
    // reload — from inotify or from the slow poll itself — actually
    // reveals a changed value, and again right when this shell issues its
    // own write. That keeps an outside change to at worst one slow-poll
    // interval, while a held key or a dragged slider stays snappy
    // throughout, and idle time (the overwhelming common case) polls
    // slowly. FileView.reload() on a sysfs file is a cheap direct read, no
    // subprocess spawn, so the fast phase costs nothing meaningful even
    // though it's frequent — it just isn't run forever.
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

    // ── Writes (everything goes through logind) ─────────
    // The last value asked for. A relative step counts from here rather
    // than from `raw` while `wantFresh` runs: during a held key the sysfs
    // read trails the writes by a poll or two, and stepping from it would
    // repeat a step instead of taking the next one.
    property int _wantRaw: -1
    property bool _writePending: false

    Timer {
        id: wantFresh
        interval: 500
    }

    // One busctl at a time. A request that arrives while one is still
    // running only moves _wantRaw, and the run that follows sends
    // whatever it is by then, so a fast ramp can never queue up behind a
    // slow write.
    Process {
        id: setProc
        onExited: {
            if (!root._writePending) return
            root._writePending = false
            root._send()
        }
    }

    function _send() {
        setProc.command = ["busctl", "call", "org.freedesktop.login1",
            "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session",
            "SetBrightness", "ssu", "backlight", root.device, String(root._wantRaw)]
        setProc.running = true
    }

    function _write(rawValue) {
        if (!root.available || root.maxBrightness <= 0) return
        const floor = Math.ceil(root.maxBrightness * root.floorPercent / 100)
        root._wantRaw = Math.max(floor, Math.min(root.maxBrightness, Math.round(rawValue)))
        wantFresh.restart()
        root._burst()
        if (setProc.running) root._writePending = true
        else root._send()
    }

    // Linear in the raw value, the same scale `percent` reads back in.
    function setPercent(p) {
        root._write(root.maxBrightness * Math.max(0, Math.min(100, p)) / 100)
    }

    function adjustBy(deltaPercent) {
        const base = wantFresh.running && root._wantRaw >= 0 ? root._wantRaw : root.raw
        root._write(base + root.maxBrightness * deltaPercent / 100)
    }

    // ── Brightness keys ─────────────────────────────────
    // XF86MonBrightnessUp/Down (hypr/modules/binds/media.lua) are `global`
    // binds, and Hyprland sends a global shortcut both its press and its
    // release; shell.qml passes them on here with a direction, 1 or -1. A
    // press steps 10% at once; holding on ramps 2% every 35ms until
    // release — an evenly paced fade on a timer of our own rather than the
    // keyboard's repeat rate, which a process per repeat tick couldn't keep
    // up with. The ramp used to be a timer in the Lua bind spawning
    // brightnessctl per tick; here each tick is only a request to _write()
    // above.
    property int _rampStep: 0

    function pressKey(dir) {
        root.adjustBy(10 * dir)
        root._rampStep = 2 * dir
    }

    // Only the key that started the ramp ends it: letting go of Up while
    // Down is held leaves Down's ramp running.
    function releaseKey(dir) {
        if (Math.sign(root._rampStep) === dir) root._rampStep = 0
    }

    Timer {
        interval: 35
        repeat: true
        running: root._rampStep !== 0
        onTriggered: root.adjustBy(root._rampStep)
    }
}
