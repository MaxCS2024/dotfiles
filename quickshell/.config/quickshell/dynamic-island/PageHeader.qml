import QtQuick

// The top of the settings panel's pages, 32px: a round back button
// (white at 12% while hovered), the page's title, and on the right the
// radio's on/off switch, or instead a short `detail` at 60% (the battery
// page has nothing to switch). Left of those, with `hasSettings`, a
// round gear button like the back button: `settings` asks for the
// settings window's matching section.
Item {
    id: header

    property string title: ""
    property bool on: false
    // false: no switch; `detail` shows in its place.
    property bool hasToggle: true
    property string detail: ""
    property bool hasSettings: false
    signal back()
    signal toggled()
    signal settings()

    height: 32

    Rectangle {
        id: backButton
        width: 32
        height: 32
        radius: 16
        color: Qt.rgba(1, 1, 1, backArea.containsMouse ? 0.12 : 0)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: "\u{f0141}"
            color: "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 20
        }

        MouseArea {
            id: backArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: header.back()
        }
    }

    Text {
        anchors.left: backButton.right
        anchors.leftMargin: 8
        anchors.right: hasSettings ? settingsButton.left : hasToggle ? toggle.left : headerDetail.left
        anchors.rightMargin: hasSettings ? 4 : 12
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: header.title
        color: "white"
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
    }

    Rectangle {
        id: settingsButton
        visible: header.hasSettings
        anchors.right: header.hasToggle ? toggle.left : headerDetail.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32
        radius: 16
        color: Qt.rgba(1, 1, 1, settingsArea.containsMouse ? 0.12 : 0)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: "\u{f0493}"
            color: "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
        }

        MouseArea {
            id: settingsArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: header.settings()
        }
    }

    Text {
        id: headerDetail
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        visible: !header.hasToggle
        text: header.detail
        color: "white"
        opacity: 0.6
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
    }

    Toggle {
        id: toggle
        visible: header.hasToggle
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        on: header.on
        onToggled: header.toggled()
    }
}
