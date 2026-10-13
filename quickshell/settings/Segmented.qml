import QtQuick

// A row of 32px round options, one of them chosen (scale, rotation):
// the chosen one solid white with black text, the rest no fill, white
// at 12% while hovered, like the fused pill's segments. `options` are
// { label, value }; `picked(value)` asks for one. Focused by the keys
// (settings window) the chosen one shows it (SettingsWindow.focusSolid). Enter or
// Space grabs the row: ← → move a highlight (focusFill), Enter or Space
// picks, Escape lets go without picking, so ← otherwise means back.
Row {
    id: seg

    property var options: []
    property var value
    signal picked(var value)

    spacing: 4

    readonly property bool navigable: true
    property bool inRow: false
    Component.onCompleted: inRow = SettingsWindow.inKeyRow(seg)
    readonly property bool keyed: activeFocus && SettingsWindow.keyboard === true
    property int cursor: 0
    property bool grabbed: false

    function letGo() {
        grabbed = false
        cursor = Math.max(0, options.findIndex(o => o.value === value))
    }

    onActiveFocusChanged: letGo()

    Keys.onPressed: event => {
        const k = event.key
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            if (grabbed) {
                const v = options[cursor].value
                letGo()
                seg.picked(v)
            } else {
                grabbed = true
            }
        } else if (grabbed && k === Qt.Key_Left)
            cursor = Math.max(0, cursor - 1)
        else if (grabbed && k === Qt.Key_Right)
            cursor = Math.min(options.length - 1, cursor + 1)
        else if (grabbed && k === Qt.Key_Escape)
            letGo()
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
            // In a lit row only the grabbed highlight shows.
            readonly property bool lit: seg.keyed && index === seg.cursor && (seg.grabbed || !seg.inRow)

            width: optionText.implicitWidth + 24
            height: 32
            radius: height / 2
            color: chosen ? Qt.rgba(1, 1, 1, lit ? SettingsWindow.focusSolid : 1)
                : Qt.rgba(1, 1, 1, lit ? SettingsWindow.focusFill : optionArea.containsMouse ? 0.12 : 0)
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
