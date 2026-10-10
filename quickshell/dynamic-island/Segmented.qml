import QtQuick

// A row of 32px round options, one of them chosen (scale, rotation):
// the chosen one solid white with black text, the rest no fill, white
// at 12% while hovered, like the fused pill's segments. `options` are
// { label, value }; `picked(value)` asks for one. Focused by the keys
// (settings window), ← → move a highlight like hover (white at 80% on
// the chosen one) and Enter or Space picks it.
Row {
    id: seg

    property var options: []
    property var value
    signal picked(var value)

    spacing: 4

    readonly property bool navigable: true
    readonly property bool keyed: activeFocus && SettingsWindow.keyboard === true
    property int cursor: 0

    onActiveFocusChanged: if (activeFocus) cursor = Math.max(0, options.findIndex(o => o.value === value))

    Keys.onPressed: event => {
        const k = event.key
        if (k === Qt.Key_Left)
            cursor = Math.max(0, cursor - 1)
        else if (k === Qt.Key_Right)
            cursor = Math.min(options.length - 1, cursor + 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)
            seg.picked(options[cursor].value)
        else
            return
        event.accepted = true
    }

    Repeater {
        model: seg.options

        Rectangle {
            id: option
            required property var modelData
            required property int index
            readonly property bool chosen: modelData.value === seg.value
            readonly property bool lit: seg.keyed && index === seg.cursor

            width: optionText.implicitWidth + 24
            height: 32
            radius: height / 2
            color: chosen ? Qt.rgba(1, 1, 1, lit ? 0.8 : 1)
                : Qt.rgba(1, 1, 1, optionArea.containsMouse || lit ? 0.12 : 0)
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
