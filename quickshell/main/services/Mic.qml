pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Mirrors Volume.qml's shape exactly, but for the default input
// (Pipewire.defaultAudioSource) instead of the default output.
Singleton {
    id: root

    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: root.source ? [root.source] : [] }

    readonly property int maxPercent: 100
    readonly property real _maxLinear: maxPercent / 100

    property real volume: 0
    property bool muted: false
    property string deviceName: "No device"
    property bool isBluetooth: false

    readonly property string icon: root.muted ? "\uf131" : "\uf130"

    // "Something is actively recording from the default source" — walks
    // Pipewire.linkGroups (the aggregated view, not raw links) for one
    // whose source is the default source node. For a capture connection,
    // PwLinkGroup.source is the physical device and .target is the
    // recording app's stream node — confirmed against a real
    // `pw-record` session while building this: source/target node ids
    // matched pw-dump's raw output-node/input-node exactly.
    //
    // Deliberately NOT gating on `state === PwLinkState.Active`, despite
    // that looking like the obviously-correct check: against that same
    // real session, PwLinkGroup.state read "unlinked" (PwLinkState
    // stringifies it that way) for the entire ~10s the recording ran,
    // while the link visibly existed and audio was genuinely flowing
    // per `pw-dump`'s own state field ("active"). Group existence
    // appeared exactly when recording started and disappeared exactly
    // when it stopped, so that's the part of this API that's actually
    // reliable at this Quickshell version — the aggregated group's own
    // `state` is not.
    readonly property bool inUse: {
        if (!root.source) return false
        for (const g of Pipewire.linkGroups.values) {
            if (g.source === root.source) return true
        }
        return false
    }

    function _sync() {
        if (root.source && root.source.audio) {
            let v = root.source.audio.volume

            if (v > root._maxLinear + 0.002) {
                root.source.audio.volume = root._maxLinear
                v = root._maxLinear
            }

            root.volume = Math.min(100, v * 100)
            root.muted = root.source.audio.muted
            root.deviceName = root.source.description || root.source.name || "Unknown"
            root.isBluetooth = (root.source.name || "").startsWith("bluez_")
        } else {
            root.volume = 0
            root.muted = false
            root.deviceName = "No device"
            root.isBluetooth = false
        }
    }

    // See Volume.qml's matching note: PwNodeAudioIface has real NOTIFY
    // signals, so this is the primary sync path; the timer is a slow
    // safety net only.
    Connections {
        target: root.source ? root.source.audio : null
        function onVolumesChanged() { root._sync() }
        function onMutedChanged() { root._sync() }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: root._sync()
    }

    onSourceChanged: root._sync()
    Component.onCompleted: root._sync()

    function setLinear(v) {
        if (!root.source || !root.source.audio) return
        root.source.audio.volume = Math.max(0, Math.min(root._maxLinear, v))
        root._sync()
    }

    function toggleMute() {
        if (root.source && root.source.audio) {
            root.source.audio.muted = !root.source.audio.muted
            root._sync()
        }
    }
}
