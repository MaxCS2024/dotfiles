import QtQuick

// A 32px round text button in the settings window. `primary` is solid
// white with black text (Apply, Keep); otherwise white at 12%, 20% while
// hovered. Disabled reads at 40% and takes no clicks.
Rectangle {
    id: button

    property string text: ""
    property bool primary: false
    signal clicked()

    implicitWidth: label.implicitWidth + 32
    height: 32
    radius: height / 2
    opacity: enabled ? 1 : 0.4
    color: primary ? "white" : Qt.rgba(1, 1, 1, area.containsMouse ? 0.2 : 0.12)
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: label
        anchors.centerIn: parent
        text: button.text
        color: button.primary ? "black" : "white"
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: button.enabled
        onClicked: button.clicked()
    }
}
