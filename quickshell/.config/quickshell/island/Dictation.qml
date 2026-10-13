pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// Dictation (AGENTS.md, Dictation), the dynamic-island's, brought over:
// what voxtype is doing ("idle", "recording", "transcribing", or
// "stopped" while the daemon isn't running), and, while it records or
// transcribes, a sticky activity in the queue that the dictation face
// (DictationFace.qml) draws. SUPER+V (hypr/modules/binds/apps.lua)
// starts and stops a recording.
//
// `voxtype status --follow` prints one state per line whenever it
// changes, and outlives the daemon (stopping the unit prints "stopped",
// starting it "idle"), so one process covers everything. Exit 127 means
// voxtype isn't installed, and it isn't retried; any other exit is,
// every 5 seconds. Main's services/Voxtype.qml does the same.
//
// While recording it also turns the default microphone's peak into the
// waveform's bar heights (0–1).
Singleton {
    id: root

    property string state: "stopped"
    // Set through the `dictation` test target, so the face can be looked
    // at without recording; empty follows voxtype. A test makes up its
    // levels and never reads the microphone.
    property string testState: ""
    readonly property string shownState: testState !== "" ? testState : state
    readonly property bool recording: shownState === "recording"
    readonly property bool transcribing: shownState === "transcribing"
    readonly property bool busy: recording || transcribing

    // ── The activity ──
    // Sticky: it stays until dictation ends instead of timing out, shows
    // over everything but a privacy announcement (the expanded state
    // included), and other transients wait behind it. The pill is the
    // dynamic-island's 144 × 32 throughout.
    onBusyChanged: sync()
    Component.onCompleted: sync()

    function sync() {
        if (!Config.dictation || !busy) {
            ActivityQueue.remove("dictation")
            return
        }
        ActivityQueue.submit({
            key: "dictation",
            transient: true,
            sticky: true,
            profile: "dictation",
            face: "dictation",
            icon: "\u{f036c}",
            label: "Dictation",
            progress: -1,
            pillWidth: 144,
            pillHeight: 32,
            revive: true,
        })
    }

    // Stop types what was heard, the same as SUPER+V; cancel drops it.
    function stop() { Quickshell.execDetached(["voxtype", "record", "toggle"]) }
    function cancel() { Quickshell.execDetached(["voxtype", "record", "cancel"]) }

    Process {
        id: follow
        running: true
        command: ["sh", "-c", "command -v voxtype >/dev/null || exit 127; exec voxtype status --follow"]
        stdout: SplitParser {
            onRead: line => root.state = line.trim()
        }
        onExited: exitCode => {
            root.state = "stopped"
            if (exitCode !== 127)
                retry.start()
        }
    }

    Timer {
        id: retry
        interval: 5000
        onTriggered: follow.running = true
    }

    // ── The waveform ──
    readonly property int barCount: 16

    // Heavier in the middle, so the loudest bars are the centre ones.
    readonly property var envelope: {
        const out = []
        for (let i = 0; i < barCount; i++) {
            const t = (i - (barCount - 1) / 2) / (barCount / 2)
            out.push(Math.exp(-2.2 * t * t))
        }
        return out
    }

    property var levels: new Array(barCount).fill(0)
    property real level: 0

    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: root.source ? [root.source] : [] }

    PwNodePeakMonitor {
        id: peak
        node: root.source
        enabled: root.recording && root.testState === ""
    }

    // Every recording starts from silence, and the floor starts high so
    // the first readings pull it down to the room.
    onRecordingChanged: if (recording) {
        noiseFloor = 0
        level = 0
        levels = new Array(barCount).fill(0)
    }

    // Peak → 0..1 above the room's own noise floor, not a fixed level:
    // this mic idles around -25 dB, where a quiet one sits at -60. The
    // floor follows the quietest reading down at once and creeps back up
    // (about 0.8 dB/s), so it settles on the gaps between words. The
    // monitor reports on Pipewire's cubic scale, hence 60·log10; it reads
    // 0 until its first sample, which is skipped. Main's VoxtypeOsd.qml
    // measured all this.
    property real noiseFloor: 0

    function loudness(p) {
        if (p <= 0)
            return 0
        const db = 60 * Math.log10(p)
        noiseFloor = db < noiseFloor ? db : noiseFloor + 0.05
        return Math.max(0, Math.min(1, (db - noiseFloor - 4) / 24))
    }

    Timer {
        interval: 60
        repeat: true
        running: root.recording
        onTriggered: {
            // A test makes up a voice instead of reading the microphone.
            const target = root.testState !== "" ? 0.3 + 0.5 * Math.random() : root.loudness(peak.peak)
            // Fast attack, slow release: words jump up, gaps drift down.
            root.level = target > root.level ? target : root.level * 0.8 + target * 0.2
            const next = []
            for (let i = 0; i < root.barCount; i++) {
                const jitter = 0.55 + 0.45 * Math.random()
                next.push(Math.min(1, root.level * root.envelope[i] * jitter * 1.3))
            }
            root.levels = next
        }
    }

    IpcHandler {
        target: "dictation"

        // "recording" or "transcribing" puts up the face without
        // recording anything; "" follows voxtype again.
        function test(state: string): void { root.testState = state }
        function status(): string { return root.shownState }
    }
}
