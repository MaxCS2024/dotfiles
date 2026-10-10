import QtQuick

// One setting in the settings window: the name in bold 13px on the left
// (with an optional `detail` under it, bold 11px at 60%), the control
// on the right. At least 40px tall; a control that unfolds (Choice)
// makes the row grow with it, the name staying level with its top.
// The name sits 16px in and the control 8px in, so that while the keys
// are on its control the first 40px light up as one round pill, like a
// focused ListRow (SettingsWindow.focusFill); the control's own focus
// fill then stays off (SettingsWindow.inKeyRow).
FocusScope {
    id: row

    readonly property bool keyRow: true

    property string label: ""
    property string detail: ""
    default property alias control: slot.data

    implicitHeight: Math.max(40, slot.childrenRect.height + 4)

    Rectangle {
        width: parent.width
        height: 40
        radius: 20
        visible: row.activeFocus && SettingsWindow.keyboard === true
        color: Qt.rgba(1, 1, 1, SettingsWindow.focusFill)
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: slot.left
        anchors.rightMargin: 16
        y: (40 - height) / 2

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: row.label
            color: "white"
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Bold
            font.pixelSize: 13
        }

        Text {
            visible: row.detail !== ""
            width: parent.width
            elide: Text.ElideRight
            text: row.detail
            color: "white"
            opacity: 0.6
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Bold
            font.pixelSize: 11
        }
    }

    Item {
        id: slot
        anchors.right: parent.right
        anchors.rightMargin: 8
        // Centred in the first 40px; an unfolded Choice hangs down from there.
        y: height <= 32 ? (40 - height) / 2 : 4
        width: childrenRect.width
        height: childrenRect.height
    }
}
