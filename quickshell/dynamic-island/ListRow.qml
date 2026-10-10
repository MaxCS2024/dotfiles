import QtQuick

// One row of the Wi-Fi or Bluetooth page: a 40px fully round pill with an
// icon, the name and a short detail on the right ("Connected", "Saved").
// No fill at rest, white at 12% while hovered (an orb's resting fill),
// and solid white with black text while `active`. In the settings
// window it takes the keys: lit like a hovered row while focused (white
// at 80% when active), Enter or Space clicks it. `highlighted` lights it
// the same way for a list that keeps the keys itself (Choice).
Rectangle {
    id: row

    property string icon: ""
    property string label: ""
    property string detail: ""
    property bool active: false
    property bool highlighted: false
    signal clicked()

    readonly property bool navigable: true
    readonly property bool lit: highlighted || (activeFocus && SettingsWindow.keyboard === true)

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            row.clicked()
            event.accepted = true
        }
    }

    height: 40
    radius: height / 2
    color: active ? Qt.rgba(1, 1, 1, lit ? 0.8 : 1)
        : Qt.rgba(1, 1, 1, area.containsMouse || lit ? 0.12 : 0)
    Behavior on color { ColorAnimation { duration: 120 } }

    readonly property color ink: active ? "black" : "white"

    Text {
        id: rowIcon
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        horizontalAlignment: Text.AlignHCenter
        text: row.icon
        color: row.ink
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 18
    }

    Text {
        anchors.left: rowIcon.right
        anchors.leftMargin: 8
        anchors.right: rowDetail.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: row.label
        color: row.ink
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
    }

    Text {
        id: rowDetail
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: row.detail
        color: row.ink
        opacity: 0.6
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 11
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: row.clicked()
    }
}
