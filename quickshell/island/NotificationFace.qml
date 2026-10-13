import Quickshell.Widgets
import QtQuick

// A notification. Transient and expanded: the card, with the picture,
// the summary, the body and the action buttons; a click on it runs the
// default action. Compact (a critical one kept until dismissed): its
// icon and summary.
Item {
    id: face

    property var activity: null
    property string mode: "transient"

    readonly property var notification: activity?.notification ?? null
    readonly property var actions: Notifications.buttons(notification)
    readonly property bool card: mode === "transient" || mode === "expanded"

    implicitWidth: card ? Config.maxWidth - Config.padX * 2
        : mode === "minimal" ? Config.compactHeight
        : compactRow.implicitWidth
    implicitHeight: card ? cardItem.height
        : mode === "minimal" ? Config.compactHeight
        : compactRow.implicitHeight

    // ── Minimal (the split's circle): the picture, round ──
    Picture {
        visible: face.mode === "minimal"
        anchors.centerIn: parent
        notification: face.notification
        size: 20
        radius: 10
    }

    // ── Compact ──
    Row {
        id: compactRow
        visible: face.mode === "compact"
        anchors.centerIn: parent
        spacing: 8

        Picture {
            anchors.verticalCenter: parent.verticalCenter
            notification: face.notification
            size: 18
            radius: 4
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Config.maxWidth - Config.padX * 2 - 26)
            text: face.notification?.summary ?? ""
            elide: Text.ElideRight
            color: Config.foreground
            font.family: Config.font
            font.weight: Font.Bold
            font.pixelSize: Config.fontSize
        }
    }

    // ── Card ──
    // Laid out at its full width from the top, so nothing reflows while
    // the pill is still growing.
    Item {
        id: cardItem
        visible: face.card
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Config.maxWidth
        // From the actions, not buttons.visible: the island measures an
        // invisible copy, where `visible` always reads false.
        height: face.actions.length > 0 ? buttons.y + buttons.height + 14 : Math.max(picture.y + picture.height, text.y + text.height) + 14

        // The click: the default action. Under the buttons, which take
        // their own; a right click goes on to the pill (dismiss).
        MouseArea {
            anchors.fill: parent
            onClicked: Notifications.invoke(face.notification)
        }

        Picture {
            id: picture
            notification: face.notification
            x: 16
            y: 14
            size: 32
            radius: 8
        }

        Column {
            id: text
            x: 60
            y: 14
            width: parent.width - x - 20
            spacing: 2

            Text {
                width: parent.width
                text: face.notification?.summary ?? ""
                elide: Text.ElideRight
                color: Config.foreground
                font.family: Config.font
                font.weight: Font.Bold
                font.pixelSize: Config.fontSize
            }

            Text {
                width: parent.width
                text: face.notification?.body ?? ""
                visible: text !== ""
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: face.mode === "expanded" ? 4 : 2
                elide: Text.ElideRight
                color: Config.foregroundSoft
                font.family: Config.font
                font.weight: Font.Bold
                font.pixelSize: Config.fontSizeSmall
            }
        }

        Row {
            id: buttons
            visible: face.actions.length > 0
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: Math.max(picture.y + picture.height, text.y + text.height) + 10
            spacing: 8

            Repeater {
                model: face.actions

                PillButton {
                    required property var modelData
                    text: modelData.text
                    onClicked: Notifications.invoke(face.notification, modelData)
                }
            }
        }
    }

    // The notification's picture, or a bell while it has none (or it
    // hasn't loaded).
    component Picture: ClippingRectangle {
        id: pic
        property var notification: null
        property int size: 32

        width: size
        height: size
        color: Config.track

        Text {
            anchors.centerIn: parent
            visible: image.status !== Image.Ready
            text: "\u{f009a}"
            color: Config.foreground
            font.family: Config.font
            font.pixelSize: Math.round(pic.size / 2)
        }

        Image {
            id: image
            anchors.fill: parent
            source: Notifications.iconSource(pic.notification)
            sourceSize.width: pic.size * 2
            sourceSize.height: pic.size * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }
    }
}
