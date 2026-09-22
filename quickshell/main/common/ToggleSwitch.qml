import QtQuick
import "../config"

// The slide toggle for a boolean that is a *mode* rather than an action —
// something that stays on until you come back and turn it off, where a
// glyph button only ever says "pressed just now". network/NetworkPanel.qml's
// airplane mode is the first of those; the shell's other booleans are
// mostly tinted chips that also carry a label, and those are fine as they
// are.
//
// Position carries the state, not colour: the knob is on the left when off
// and the right when on, so the control still reads on a palette where the
// accent is close to the track, and it reads while the colour animation is
// halfway through.
//
// Square rather than the usual pill, at the user's asking (2026-09-18).
// Theme.radius and not a literal 0: that token is Settings.cornerRadius,
// which is 2 here — so this matches the glyph buttons it sits beside in
// network/NetworkPanel.qml's header exactly, and follows the setting if it
// is ever turned up rather than staying the one sharp thing on the card.
//
// Colours are properties with Theme defaults rather than Appearance reads,
// like every other file in common/ — this directory is symlinked into both
// shells and doesn't follow theme/Appearance.qml's custom-palette toggle
// (that file's own header says so). A surface that wants the pinned palette
// passes it in, the way network/NetworkPanel.qml does for ListScrollBar.
Item {
    id: root

    property bool checked: false

    property color trackOffColor: Theme.trackBg
    property color trackOnColor: Theme.accent
    property color borderColor: Theme.border
    property color knobColor: Theme.fgStrong

    // Emitted on click. Deliberately not a two-way binding on `checked`:
    // the caller here drives a service (AirplaneMode.toggle()) and reads the
    // result back, so the switch must not move on its own and then disagree
    // with what the radio actually did.
    signal toggled

    implicitWidth: 36
    implicitHeight: 20

    readonly property real _inset: 2
    readonly property real _knobSize: root.implicitHeight - root._inset * 2

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.checked ? root.trackOnColor : root.trackOffColor
        border.width: 1
        border.color: root.checked ? root.trackOnColor : root.borderColor

        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
        Behavior on border.color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
    }

    Rectangle {
        width: root._knobSize
        height: root._knobSize
        radius: Theme.radius
        color: root.knobColor
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? root.width - root._knobSize - root._inset : root._inset

        // The slide is the whole point of this control over a chip, so it
        // gets animNormal where the track gets animFast — the colour should
        // have settled by the time the knob arrives, not after it.
        Behavior on x { NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
