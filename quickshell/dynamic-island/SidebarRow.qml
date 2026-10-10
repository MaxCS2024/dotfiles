import QtQuick

// One section in the settings window's sidebar: a 40px fully round pill
// with the section's icon and name, like a ListRow without the detail.
// No fill at rest, white at 12% while hovered, solid white with black
// text for the current section. `compact` (the window tiled narrow)
// leaves only the icon, centred in a 40px circle.
Rectangle {
    id: row

    property string icon: ""
    property string label: ""
    property bool active: false
    property bool compact: false
    signal clicked()

    height: 40
    radius: height / 2
    // `hovered` rather than area.containsMouse here: while the window is
    // torn down the area can go first, and the colour came out undefined.
    property bool hovered: false
    color: active ? "white" : Qt.rgba(1, 1, 1, hovered ? 0.12 : 0)
    Behavior on color { ColorAnimation { duration: 120 } }

    readonly property color ink: active ? "black" : "white"

    Text {
        id: rowIcon
        x: row.compact ? (row.width - width) / 2 : 12
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        horizontalAlignment: Text.AlignHCenter
        text: row.icon
        color: row.ink
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 18
    }

    Text {
        visible: !row.compact
        anchors.left: rowIcon.right
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: row.label
        color: row.ink
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onContainsMouseChanged: row.hovered = containsMouse
        onClicked: row.clicked()
    }
}
