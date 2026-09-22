import Quickshell
import Quickshell.Io
import QtQuick
import "../services"
import "../theme"

OsdWindow {
    id: osd

    surfaceNamespace: "quickshell:osd-brightness"

    OsdContent {
        id: content
        shown: osd.shown
        icon: "\uf185"   // sun glyph
        value: Brightness.percent
        accentColor: Appearance.orange
        unavailableText: Brightness.available ? "" : "No backlight device found"
    }

    // Guards against firing once on startup when the device's initial
    // brightness is first read.
    property real _lastPercent: -1

    Connections {
        target: Brightness
        function onPercentChanged() {
            if (!osd.afterFirst()) {
                osd._lastPercent = Brightness.percent
                return
            }
            if (Math.abs(Brightness.percent - osd._lastPercent) > 0.01) {
                osd._lastPercent = Brightness.percent
                osd.show()
            }
        }
    }

    // Lets an external keybind force the OSD to show even if it also
    // calls brightnessctl separately. Named `popup` rather than `show`
    // because `qs ipc call` reads a bare `show` as its own sibling
    // subcommand, printing this target's interface instead of calling
    // anything — and still exiting 0. Same trap for `wait`, `listen`
    // and `prop`.
    IpcHandler {
        target: "osd-brightness"
        function popup(): void { osd.show() }
    }
}
