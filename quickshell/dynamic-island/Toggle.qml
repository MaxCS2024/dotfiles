import QtQuick

// An on/off switch: a 36 × 20 pill, white at 20% with a white knob while
// off, solid white with a black knob while on, as a fused-pill segment
// goes solid white when active. `on` comes from outside; `toggled` asks
// for the other state.
Rectangle {
    id: toggle

    property bool on: false
    signal toggled()

    width: 36
    height: 20
    radius: height / 2
    color: on ? "white" : Qt.rgba(1, 1, 1, 0.2)
    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
        x: toggle.on ? toggle.width - width - 4 : 4
        anchors.verticalCenter: parent.verticalCenter
        width: 12
        height: 12
        radius: 6
        color: toggle.on ? "black" : "white"
        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: toggle.toggled()
    }
}
