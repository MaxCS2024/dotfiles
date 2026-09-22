import Quickshell
import Quickshell.Io
import QtQuick
import "../services"

OsdWindow {
    id: osd

    surfaceNamespace: "quickshell:osd-volume"

    OsdContent {
        id: content
        shown: osd.shown
        icon: Volume.icon
        value: Volume.volume
        muted: Volume.muted
    }

    property real _lastVolume: -1

    Connections {
        target: Volume
        function onVolumeChanged() {
            if (!osd.afterFirst()) {
                osd._lastVolume = Volume.volume
                return
            }
            if (Math.abs(Volume.volume - osd._lastVolume) > 0.01) {
                osd._lastVolume = Volume.volume
                osd.show()
            }
        }
        function onMutedChanged() {
            if (osd.seenFirst) osd.show()
        }
    }

    // `popup`, not `show`, for the reason in osd-brightness's handler.
    IpcHandler {
        target: "osd-volume"
        function popup(): void { osd.show() }
    }
}
