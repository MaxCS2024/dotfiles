import QtQuick

// An on/off switch: a 36 × 20 pill, white at 20% with a white knob while
// off, solid white with a black knob while on, as a fused-pill segment
// goes solid white when active. `on` comes from outside; `toggled` asks
// for the other state. Focused by the keys (settings window) it sits on
// a 48 × 32 pill (SettingsWindow.focusFill), unless its row lights up; Enter or Space flips it.
Rectangle {
    id: toggle

    property bool on: false
    signal toggled()

    readonly property bool navigable: true
    property bool inRow: false
    Component.onCompleted: inRow = SettingsWindow.inKeyRow(toggle)

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            toggle.toggled()
            event.accepted = true
        }
    }

    Rectangle {
        z: -1
        anchors.centerIn: parent
        width: parent.width + 12
        height: parent.height + 12
        radius: height / 2
        visible: toggle.activeFocus && SettingsWindow.keyboard === true && !toggle.inRow
        color: Qt.rgba(1, 1, 1, SettingsWindow.focusFill)
    }

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
