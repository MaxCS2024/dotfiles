pragma Singleton
import Quickshell
import QtQuick

// The tokens Bar.qml reads. The real Theme loads matugen's palette and
// reloads Hyprland when it does; short durations keep the slide tests fast.
Singleton {
    readonly property int animNormal: 40
    readonly property int animPanel: 60
    readonly property int easingDecel: Easing.OutCubic
    readonly property int easingStandard: Easing.InOutQuad
    readonly property int radiusLarge: 4
    readonly property int space1: 4
    readonly property int space2: 8
}
