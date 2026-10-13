pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// The OSD feature (AGENTS.md, OSD): watches the volume, the microphone's
// mute and the screen brightness, and submits a transient to the queue
// when one of them changes, from anywhere. It never changes them.
Singleton {
    id: root

    // ── Volume ──
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.source].filter(n => n) }

    // The last reading per device. A new device (or one still binding)
    // only sets these, so switching outputs or starting up stays quiet.
    property int sinkId: -1
    property real lastVolume: -1
    property bool lastMuted: false
    property int sourceId: -1
    property bool lastMicMuted: false

    function readSink() {
        if (!sink?.ready || !sink.audio)
            return
        const v = sink.audio.volume
        const m = sink.audio.muted
        const known = sink.id === sinkId
        const changed = Math.abs(v - lastVolume) > 0.001 || m !== lastMuted
        sinkId = sink.id
        lastVolume = v
        lastMuted = m
        if (known && changed)
            showVolume(v, m)
    }

    function readSource() {
        if (!source?.ready || !source.audio)
            return
        const m = source.audio.muted
        const known = source.id === sourceId
        const changed = m !== lastMicMuted
        sourceId = source.id
        lastMicMuted = m
        if (known && changed)
            showMic(m)
    }

    Connections {
        target: root.sink?.audio ?? null
        function onVolumeChanged() { root.readSink() }
        function onMutedChanged() { root.readSink() }
    }
    Connections {
        target: root.sink
        function onReadyChanged() { root.readSink() }
    }
    onSinkChanged: readSink()

    Connections {
        target: root.source?.audio ?? null
        function onMutedChanged() { root.readSource() }
    }
    Connections {
        target: root.source
        function onReadyChanged() { root.readSource() }
    }
    onSourceChanged: readSource()

    // ── Brightness ──
    // The first /sys/class/backlight device. sysfs sends no change events
    // for it, so it is read every 200ms; the first reading only sets
    // the baseline.
    property string backlight: ""
    property real maxBrightness: 0
    property real lastBrightness: -1

    Process {
        running: Config.osd
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -e \"$d\" ] && { echo \"$d\"; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: root.backlight = text.trim()
        }
    }

    FileView {
        path: root.backlight !== "" ? root.backlight + "/max_brightness" : ""
        onLoaded: root.maxBrightness = parseInt(text())
    }

    FileView {
        id: brightnessFile
        path: root.backlight !== "" && root.maxBrightness > 0 ? root.backlight + "/brightness" : ""
        onLoaded: {
            const b = parseInt(text()) / root.maxBrightness
            if (isNaN(b) || Math.abs(b - root.lastBrightness) < 0.001)
                return
            const first = root.lastBrightness < 0
            root.lastBrightness = b
            if (!first)
                root.showBrightness(b)
        }
    }

    Timer {
        running: Config.osd && brightnessFile.path !== ""
        interval: 200
        repeat: true
        onTriggered: brightnessFile.reload()
    }

    // ── Submitting ──
    // One key for all three: the newest change replaces the one on screen.
    // `waits: false`: a level changed while the island is open is stale by
    // the time it closes, so it is dropped instead of queued.
    function submit(spec) {
        if (!Config.osd)
            return
        ActivityQueue.submit(Object.assign({
            key: "osd",
            transient: true,
            waits: false,
            profile: "osd",
            timeout: Config.osdTimeout,
        }, spec))
    }

    // Muted reads 0%, with the muted speaker.
    function showVolume(v, muted) {
        const icon = muted || v <= 0 ? "\u{f075f}"
            : v < 0.34 ? "\u{f057f}"
            : v < 0.67 ? "\u{f0580}"
            : "\u{f057e}"
        submit({ face: "osd", icon, label: "", progress: muted ? 0 : v })
    }

    function showBrightness(b) {
        submit({ face: "osd", icon: "\u{f00e0}", label: "", progress: b })
    }

    function showMic(muted) {
        submit({
            face: "",
            icon: muted ? "\u{f036d}" : "\u{f036c}",
            label: muted ? "Microphone muted" : "Microphone on",
            progress: -1,
        })
    }

    // ── OSD tests ──
    // Shows the OSD for made-up readings, without touching the volume,
    // the microphone or the brightness (AGENTS.md, Testing).
    IpcHandler {
        target: "osd"

        function volume(v: real, muted: bool): void { root.showVolume(v, muted) }
        function brightness(b: real): void { root.showBrightness(b) }
        function mic(muted: bool): void { root.showMic(muted) }
    }
}
