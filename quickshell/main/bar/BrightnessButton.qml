import QtQuick
import "../config"
import "../theme"
import "../common"
import "../services"

// Gated on Brightness.available so this collapses cleanly on a desktop
// with no backlight device, the same way MediaPlayer.qml collapses with
// nothing playing.
BarButton {
    id: root

    visible: Brightness.available

    icon: ""
    label: Math.round(Brightness.percent) + "%"

    // No onTapped: unlike Volume/Network/Battery there's no dedicated
    // QuickSettings tab for brightness to jump to — the dropdown below
    // already shows the current level, which is all there is to show.

    // Mirrors VolumeButton's wheel handling exactly, including the 40ms
    // throttle — a bare wheel tick can fire faster than adjustBy's own
    // brightnessctl subprocess can keep up with otherwise.
    property real _lastWheelTime: 0

    onScrolled: (delta) => {
        const now = Date.now()
        if (now - root._lastWheelTime < 40) return
        root._lastWheelTime = now

        Brightness.adjustBy(delta > 0 ? 5 : -5)
    }

    Text {
        text: "Brightness"
        color: Appearance.fgStrong
        font.bold: true
        font.pixelSize: Theme.fontMedium
        font.family: Theme.font
    }

    Divider {}

    InfoRow { label: "Level"; value: Math.round(Brightness.percent) + "%" }
}
