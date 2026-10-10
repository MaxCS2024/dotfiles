import QtQuick

// A one-line text field in the settings window: a 40px pill, white at
// 12%, bold 13px text, a placeholder at 40% while empty, like the
// island's password field. `password` hides the text. Enter sends
// `accepted`, Escape `cancelled`.
Rectangle {
    id: field

    property alias text: input.text
    property string placeholder: ""
    property bool password: false
    signal accepted()
    signal cancelled()

    function focusInput() {
        input.forceActiveFocus()
    }

    height: 40
    radius: 20
    color: Qt.rgba(1, 1, 1, 0.12)

    MouseArea {
        anchors.fill: parent
        onClicked: input.forceActiveFocus()
    }

    TextInput {
        id: input
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        selectByMouse: true
        echoMode: field.password ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        color: "white"
        selectionColor: Qt.rgba(1, 1, 1, 0.3)
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
        onAccepted: field.accepted()
        Keys.onEscapePressed: field.cancelled()

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: field.placeholder
            color: "white"
            opacity: 0.4
            font: input.font
        }
    }
}
