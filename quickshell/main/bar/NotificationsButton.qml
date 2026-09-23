import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"
import "../services"

BarButton {
    id: root

    icon: Settings.dnd ? "\uf1f6" : "\uf0f3"
    iconColor: Settings.dnd ? Appearance.fgDim : Appearance.icon
    minWidth: 260

    // Left click opens the right-edge rail (notifications/
    // NotificationHistoryPanel.qml), the same trade bar/NetworkButton.qml
    // made when its own rail arrived. Right click stays on Do Not
    // Disturb, which is the one thing worth having a click away from the
    // bar; the quick settings tab this button used to open is a row in
    // the rail's footer now, and the rail carries its own DND switch.
    onTapped: Panels.toggle("notification-history")
    onRightTapped: Settings.dnd = !Settings.dnd

    onDropdownVisibleChanged: if (dropdownVisible) Notifications.markAllSeen()

    Item {
        Layout.preferredWidth: 16
        Layout.preferredHeight: 16
        visible: Notifications.unreadCount > 0

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            width: 15
            height: 15
            radius: 7.5
            color: Appearance.red

            Text {
                anchors.centerIn: parent
                text: Notifications.unreadCount > 9 ? "9+" : Notifications.unreadCount
                color: Appearance.bar
                font.pixelSize: 9
                font.family: Theme.font
                font.bold: true
            }
        }
    }

    Text {
        text: "Notifications"
        color: Appearance.fgStrong
        font.bold: true
        font.pixelSize: Theme.fontMedium
        font.family: Theme.font
    }

    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.separator }

    Repeater {
        model: Notifications.history.slice(0, 3)

        delegate: ColumnLayout {
            id: entry
            required property var modelData

            Layout.fillWidth: true
            spacing: 1

            Text {
                text: entry.modelData.summary || entry.modelData.appName
                color: Appearance.fg
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                text: entry.modelData.appName
                color: Appearance.fgDim
                font.pixelSize: Theme.fontTiny
                font.family: Theme.font
            }
        }
    }

    Text {
        visible: Notifications.history.length === 0
        text: "No notifications"
        color: Appearance.fgDim
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
    }
}
