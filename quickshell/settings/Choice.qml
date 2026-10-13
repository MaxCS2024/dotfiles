import QtQuick

// A dropdown that opens in place: a 32px pill (white at 12%, 20% while
// hovered) with the current value and a chevron. A click unfolds the
// options below it, five rows tall, scrolling past that; picking one, or
// a second click on the pill, folds it again. `options` are
// { label, value }. Focused by the keys (settings window) the pill lifts
// to SettingsWindow.focusFill; Enter or Space unfolds it, ↑ ↓ move through the options,
// Enter or Space picks one, Escape folds it again.
Column {
    id: choice

    property var options: []
    property var value
    property bool expanded: false
    signal picked(var value)

    readonly property var current: options.find(o => o.value === value)

    spacing: 4

    readonly property bool navigable: true
    property bool inRow: false
    Component.onCompleted: inRow = SettingsWindow.inKeyRow(choice)
    readonly property bool keyed: activeFocus && SettingsWindow.keyboard === true
    property int cursor: 0

    onActiveFocusChanged: if (!activeFocus) expanded = false

    Keys.onPressed: event => {
        const k = event.key
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            if (!expanded) {
                cursor = Math.max(0, options.findIndex(o => o.value === value))
                expanded = true
                list.positionViewAtIndex(cursor, ListView.Contain)
                Qt.callLater(() => SettingsWindow.reveal(choice))
            } else if (cursor < options.length) {
                expanded = false
                picked(options[cursor].value)
            }
        } else if (expanded && (k === Qt.Key_Up || k === Qt.Key_Down)) {
            cursor = Math.max(0, Math.min(options.length - 1, cursor + (k === Qt.Key_Down ? 1 : -1)))
            list.positionViewAtIndex(cursor, ListView.Contain)
        } else if (expanded && k === Qt.Key_Escape) {
            expanded = false
        } else
            return
        event.accepted = true
    }

    Rectangle {
        width: choice.width
        height: 32
        radius: height / 2
        color: Qt.rgba(1, 1, 1, choice.keyed && !choice.expanded && !choice.inRow ? SettingsWindow.focusFill : headArea.containsMouse ? 0.2 : 0.12)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: chevron.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: choice.current ? choice.current.label : ""
            color: "white"
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Bold
            font.pixelSize: 13
        }

        Text {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: choice.expanded ? "\u{f0143}" : "\u{f0140}"
            color: "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
        }

        MouseArea {
            id: headArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: choice.expanded = !choice.expanded
        }
    }

    ListView {
        id: list
        visible: choice.expanded
        width: choice.width
        height: Math.min(count, 5) * 36 - 4
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: choice.options

        delegate: ListRow {
            required property var modelData
            required property int index
            width: list.width
            height: 32
            label: modelData.label
            active: modelData.value === choice.value
            highlighted: choice.keyed && index === choice.cursor
            onClicked: {
                choice.expanded = false
                choice.picked(modelData.value)
            }
        }
    }
}
