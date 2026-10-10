import QtQuick

// A dropdown that opens in place: a 32px pill (white at 12%, 20% while
// hovered) with the current value and a chevron. A click unfolds the
// options below it, five rows tall, scrolling past that; picking one, or
// a second click on the pill, folds it again. `options` are
// { label, value }.
Column {
    id: choice

    property var options: []
    property var value
    property bool expanded: false
    signal picked(var value)

    readonly property var current: options.find(o => o.value === value)

    spacing: 4

    Rectangle {
        width: choice.width
        height: 32
        radius: height / 2
        color: Qt.rgba(1, 1, 1, headArea.containsMouse ? 0.2 : 0.12)
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
            width: list.width
            height: 32
            label: modelData.label
            active: modelData.value === choice.value
            onClicked: {
                choice.expanded = false
                choice.picked(modelData.value)
            }
        }
    }
}
