import QtQuick
import "../config"
import "../theme"
import "../common"

// The slab an OSD draws in, and the way it arrives: a short rise from
// 12 to 28px off the bottom edge, with a scale and a fade on the same
// beat.
//
// The rise is short on purpose rather than a slide from off-screen.
// Combined with the scale it reads as the popup settling into place
// instead of travelling a fixed distance, which is what made the earlier
// `anchors.bottomMargin: -height → 28` slide feel mechanical.
//
// Out is quicker than in — 160 against 300, InCubic against OutBack —
// because an OSD leaving is not an event, it is the end of one. That
// asymmetry is the whole character of these popups, and it was written
// out three times in identical Behaviors before this file existed:
// osd/OsdContent.qml's box, osd/CapsLockOsd.qml's and osd/ZenOsd.qml's,
// the last two byte-for-byte the same.
//
// Content goes in as children — this is a Rectangle, so its default
// property is the caller's to fill:
//
//     OsdBox {
//         shown: osd.shown
//         width: 200
//         RowLayout { anchors.centerIn: parent }
//     }
Rectangle {
    id: box

    // Driven by the window's `shown` — see osd/OsdWindow.qml, which owns
    // when that goes true and false.
    required property bool shown

    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: box.shown ? 28 : 12

    // Width is the caller's: a reading with a progress bar wants 280, a
    // boolean with two words wants 200. The height is the same for all of
    // them, which is what makes them read as one family.
    height: 56
    radius: Theme.radius
    color: Appearance.surface
    border.color: Appearance.border
    border.width: 1
    opacity: box.shown ? 1 : 0

    transformOrigin: Item.Bottom
    scale: box.shown ? 1 : 0.9

    layer.enabled: true
    layer.effect: PopupShadow {}

    Behavior on anchors.bottomMargin {
        NumberAnimation {
            duration: box.shown ? 300 : 160
            easing.type: box.shown ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 1.3
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: box.shown ? 300 : 160
            easing.type: box.shown ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 1.3
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: box.shown ? 200 : 120
            easing.type: Easing.OutQuad
        }
    }
}
