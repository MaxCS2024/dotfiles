import QtQuick

// A thin white slider: 4px track, the filled part white, a 12px knob.
// `value` is 0–1 and comes from outside; `moved` asks for a new one.
// While dragged it shows the dragged value, so a source that updates
// late (brightness is polled) doesn't make the knob jump back.
// Focused by the keys (settings window) the knob sits on a 24px circle
// of white at 12%, and ← → move it by `keyStep`; it shows the keyed
// value the same way until the keys rest.
Item {
    id: slider

    property real value: 0
    signal moved(real value)
    property real keyStep: 0.05

    property real dragValue: 0
    readonly property real shownValue: area.pressed || keyRest.running ? dragValue : value

    readonly property bool navigable: true

    Keys.onPressed: event => {
        const d = event.key === Qt.Key_Right ? 1 : event.key === Qt.Key_Left ? -1 : 0
        if (d === 0)
            return
        const from = keyRest.running ? dragValue : value
        dragValue = Math.max(0, Math.min(1, from + d * keyStep))
        keyRest.restart()
        moved(dragValue)
        event.accepted = true
    }

    Timer {
        id: keyRest
        interval: 600
    }

    implicitHeight: 24

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.2)

        Rectangle {
            width: parent.width * slider.shownValue
            height: parent.height
            radius: 2
            color: "white"
        }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: slider.shownValue * (slider.width - 12) - 6
        width: 24
        height: 24
        radius: 12
        visible: slider.activeFocus && SettingsWindow.keyboard === true
        color: Qt.rgba(1, 1, 1, 0.12)
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: slider.shownValue * (slider.width - width)
        width: 12
        height: 12
        radius: 6
        color: "white"
    }

    MouseArea {
        id: area
        anchors.fill: parent
        preventStealing: true

        function update(mouseX) {
            slider.dragValue = Math.max(0, Math.min(1, (mouseX - 6) / (width - 12)))
            slider.moved(slider.dragValue)
        }

        onPressed: mouse => update(mouse.x)
        onPositionChanged: mouse => update(mouse.x)
    }
}
