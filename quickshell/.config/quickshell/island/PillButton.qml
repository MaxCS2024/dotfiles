import QtQuick

// A small round-ended text button on the black pill: a faint white fill,
// one step brighter on hover.
Rectangle {
    id: button

    property string text: ""
    signal clicked()

    implicitWidth: label.implicitWidth + 24
    implicitHeight: 28
    radius: height / 2
    color: hover.hovered ? Config.buttonHover : Config.button

    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: label
        anchors.centerIn: parent
        text: button.text
        color: Config.foreground
        font.family: Config.font
        font.weight: Font.Bold
        font.pixelSize: Config.fontSizeSmall
    }

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: parent
        onClicked: button.clicked()
    }
}
