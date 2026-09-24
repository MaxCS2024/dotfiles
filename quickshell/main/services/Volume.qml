pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    readonly property int maxPercent: 100
    readonly property real _maxLinear: maxPercent / 100

    property real volume: 0
    property bool muted: false
    property string deviceName: "No device"

    // The speaker glyph whatever the output is. It used to turn into
    // headphones (U+F025) while the default sink was a Bluetooth one; the
    // user wanted the default icon to stay (2026-09-24), and with earbuds
    // connected the bar already shows them in their own module.
    readonly property string icon: {
        if (root.muted || root.volume === 0) return "\uf026"
        if (root.volume < 50) return "\uf027"
        return "\uf028"
    }

    function _sync() {
        if (root.sink && root.sink.audio) {
            let v = root.sink.audio.volume

            if (v > root._maxLinear + 0.002) {
                root.sink.audio.volume = root._maxLinear
                v = root._maxLinear
            }

            root.volume = Math.min(100, v * 100)
            root.muted = root.sink.audio.muted
            root.deviceName = root.sink.description || root.sink.name || "Unknown"
        } else {
            root.volume = 0
            root.muted = false
            root.deviceName = "No device"
        }
    }

    // PwNodeAudioIface.volume/.muted carry real NOTIFY signals
    // (volumesChanged/mutedChanged), so the reactive path is the primary
    // sync — no per-frame polling needed for a key press or an external
    // `wpctl` change to show up promptly. The timer below is a slow
    // safety net only, not the main path.
    Connections {
        target: root.sink ? root.sink.audio : null
        function onVolumesChanged() { root._sync() }
        function onMutedChanged() { root._sync() }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: root._sync()
    }

    onSinkChanged: root._sync()
    Component.onCompleted: root._sync()

    function setLinear(v) {
        if (!root.sink || !root.sink.audio) return
        root.sink.audio.volume = Math.max(0, Math.min(root._maxLinear, v))
        root._sync()
    }

    function adjustBy(deltaLinear) {
        if (!root.sink || !root.sink.audio) return
        const v = root.sink.audio.volume + deltaLinear
        root.setLinear(v)
        if (v > 0 && root.sink.audio.muted) {
            root.sink.audio.muted = false
            root._sync()
        }
    }

    function toggleMute() {
        if (root.sink && root.sink.audio) {
            root.sink.audio.muted = !root.sink.audio.muted
            root._sync()
        }
    }
}
