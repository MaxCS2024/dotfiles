import QtQuick
import "../config"
import "../theme"

// The 1px-track/gold-fill slider shape repeated across the
// popouts (quick settings' Vol/Lum with a knob, now-playing's progress and
// the audio mixer's device/per-app rows without one). Only the track
// itself: the flanking label/value `Text`s are each surface's own row
// layout, since their shape differs per surface (a fixed-width label
// before, a value after, sometimes neither); the design builds every one
// of these as sibling flex children, not a single fused control.
Item {
    id: root

    property real value: 0        // 0..1
    property bool showKnob: false
    property real trackHeight: 1
    property color trackColor: Appearance.trackBg
    property color fillColor: Appearance.accent
    property bool interactive: false
    property real stepSize: 0.05

    signal moved(real value)

    readonly property real _knobSize: 7
    implicitHeight: Math.max(root.trackHeight, root.showKnob ? root._knobSize : 0)

    // Was mouse-drag only when `interactive`.
    activeFocusOnTab: root.interactive
    Keys.onPressed: (event) => {
        if (!root.interactive) return
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) {
            root.moved(Math.max(0, root.value - root.stepSize))
            event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) {
            root.moved(Math.min(1, root.value + root.stepSize))
            event.accepted = true
        }
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.trackHeight
        color: root.trackColor

        Rectangle {
            width: track.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            color: root.fillColor
        }
    }

    Rectangle {
        visible: root.showKnob
        width: root._knobSize
        height: root._knobSize
        radius: root._knobSize / 2
        color: Appearance.surface
        border.width: 1
        border.color: root.fillColor
        anchors.verticalCenter: track.verticalCenter
        x: Math.max(0, Math.min(root.width - width, track.width * root.value - width / 2))
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        function setFromX(x) { root.moved(Math.max(0, Math.min(1, x / width))) }
        onPressed: (mouse) => { root.forceActiveFocus(); setFromX(mouse.x) }
        onPositionChanged: (mouse) => { if (pressed) setFromX(mouse.x) }
    }
}
