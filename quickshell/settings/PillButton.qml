import QtQuick

// A 32px round text button in the settings window. `primary` is solid
// white with black text (Apply, Keep); otherwise white at 12%, 20% while
// hovered. Disabled reads at 40% and takes no clicks. Focused by the
// keys it lifts to SettingsWindow.focusFill (focusSolid when primary); Enter or Space
// clicks it.
Rectangle {
    id: button

    property string text: ""
    property bool primary: false
    signal clicked()

    readonly property bool navigable: true
    readonly property bool lit: activeFocus && SettingsWindow.keyboard === true

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            button.clicked()
            event.accepted = true
        }
    }

    implicitWidth: label.implicitWidth + 32
    height: 32
    radius: height / 2
    opacity: enabled ? 1 : 0.4
    color: primary ? Qt.rgba(1, 1, 1, lit ? SettingsWindow.focusSolid : 1)
        : Qt.rgba(1, 1, 1, lit ? SettingsWindow.focusFill : area.containsMouse ? 0.2 : 0.12)
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
