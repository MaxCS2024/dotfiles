import Quickshell
import Quickshell.Io
import QtQuick
import "../services"

// Mirrors VolumeOsd.qml exactly, but for Mic (the default input) instead
// of Volume (the default output) — including firing on any Mic.volume/
// muted change, not just the quicksettings slider, so it also covers a
// future mic-specific keybind the same way VolumeOsd already covers
// scroll-to-adjust from the bar.
OsdWindow {
    id: osd

    surfaceNamespace: "quickshell:osd-mic"

    OsdContent {
        id: content
        shown: osd.shown
        icon: Mic.icon
        value: Mic.volume
        muted: Mic.muted
    }

    property real _lastVolume: -1

    Connections {
        target: Mic
        function onVolumeChanged() {
            if (!osd.afterFirst()) {
                osd._lastVolume = Mic.volume
                return
            }
            if (Math.abs(Mic.volume - osd._lastVolume) > 0.01) {
                osd._lastVolume = Mic.volume
                osd.show()
            }
        }
        function onMutedChanged() {
            if (osd.seenFirst) osd.show()
        }
    }

    IpcHandler {
        target: "osd-mic"
        function popup(): void { osd.show() }
    }
}
