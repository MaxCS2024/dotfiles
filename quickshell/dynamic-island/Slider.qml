import QtQuick

// A thin white slider: 4px track, the filled part white, a 12px knob.
// `value` is 0–1 and comes from outside; `moved` asks for a new one.
// While dragged it shows the dragged value, so a source that updates
// late (brightness is polled) doesn't make the knob jump back.
Item {
    id: slider

    property real value: 0
    signal moved(real value)

    property real dragValue: 0
    readonly property real shownValue: area.pressed ? dragValue : value

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
