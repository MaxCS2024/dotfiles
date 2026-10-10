import QtQuick

// A row of 32px round options, one of them chosen (scale, rotation):
// the chosen one solid white with black text, the rest no fill, white
// at 12% while hovered, like the fused pill's segments. `options` are
// { label, value }; `picked(value)` asks for one.
Row {
    id: seg

    property var options: []
    property var value
    signal picked(var value)

    spacing: 4

    Repeater {
        model: seg.options

        Rectangle {
            id: option
            required property var modelData
            readonly property bool chosen: modelData.value === seg.value

            width: optionText.implicitWidth + 24
            height: 32
            radius: height / 2
            color: chosen ? "white" : Qt.rgba(1, 1, 1, optionArea.containsMouse ? 0.12 : 0)
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                id: optionText
                anchors.centerIn: parent
                text: option.modelData.label
                color: option.chosen ? "black" : "white"
                font.family: "JetBrainsMono Nerd Font"
                font.weight: Font.Bold
                font.pixelSize: 13
            }

            MouseArea {
                id: optionArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: seg.picked(option.modelData.value)
            }
        }
    }
}
