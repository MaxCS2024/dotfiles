import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"
import "../theme"
import "../common"

// Boolean on/off, unlike Volume/Mic/Brightness's 0-100 value, so it does
// not reuse osd/OsdContent.qml — that is built around an icon, a progress
// bar and a reading, and a lock key has none of those.
//
// That was once a reason to copy everything else too: this file carried
// its own window, its own two timers and its own animated box, because
// the only thing on offer was the body it could not use. The window is
// osd/OsdWindow.qml's now and the slab is osd/OsdBox.qml's, so what is
// left here is the two words and the glyph, which is all this ever was.
OsdWindow {
    id: osd

    surfaceNamespace: "quickshell:osd-capslock"

    Connections {
        target: CapsLock
        // The first report is the poll telling us what the key already
        // was — see OsdWindow.afterFirst().
        function onActiveChanged() { if (osd.afterFirst()) osd.show() }
    }

    OsdBox {
        shown: osd.shown
        width: 200

        RowLayout {
            anchors.centerIn: parent
            spacing: Theme.space3

            Text {
                text: "\uf023"   // fa-lock, same glyph as PowerTab's "Lock"
                color: CapsLock.active ? Appearance.green : Appearance.icon
                font.pixelSize: 20
                font.family: Theme.font
            }

            Text {
                text: CapsLock.active ? "Caps Lock On" : "Caps Lock Off"
                color: Appearance.fg
                font.pixelSize: Theme.fontNormal
                font.family: Theme.font
            }
        }
    }

    // Lets an external keybind force the OSD to show independently of
    // an actual toggle — same escape hatch as osd-brightness.
    IpcHandler {
        target: "osd-capslock"
        function popup(): void { osd.show() }
    }
}
