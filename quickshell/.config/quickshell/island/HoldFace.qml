import QtQuick

// The hold mode's count. Compact: a bell and "3 held" ("Holding" while
// none are). Expanded: the count, "Show" to see them now and "Stop
// holding".
Item {
    id: face

    property var activity: null
    property string mode: "compact"

    readonly property int count: activity?.count ?? 0

    implicitWidth: mode === "expanded" ? Config.maxWidth - Config.padX * 2
        : mode === "minimal" ? Config.compactHeight
        : compactRow.implicitWidth
    implicitHeight: mode === "expanded" ? 104
        : mode === "minimal" ? Config.compactHeight
        : compactRow.implicitHeight

    // Minimal (the split's circle): the count, or the bell while none
    // are held.
    Text {
        visible: face.mode === "minimal"
        anchors.centerIn: parent
        text: face.count > 0 ? String(face.count) : (face.activity?.icon ?? "")
        color: Config.foreground
        font.family: Config.font
        font.weight: Font.Bold
        font.pixelSize: face.count > 0 ? Config.fontSize : Config.iconSize
    }

    Row {
        id: compactRow
        visible: face.mode === "compact" || face.mode === "transient"
        anchors.centerIn: parent
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: face.activity?.icon ?? ""
            color: Config.foreground
            font.family: Config.font
            font.pixelSize: Config.iconSize
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: face.activity?.label ?? ""
            color: Config.foreground
            font.family: Config.font
            font.weight: Font.Bold
            font.pixelSize: Config.fontSize
        }
    }

    // Laid out at its full width from the top, like the other expanded
    // faces.
    Item {
        visible: face.mode === "expanded"
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Config.maxWidth
        height: 104

        Column {
            x: 24
            y: 18
            spacing: 2

            Text {
                text: face.count === 1 ? "1 notification held" : face.count ? `${face.count} notifications held` : "Holding notifications"
                color: Config.foreground
                font.family: Config.font
                font.weight: Font.Bold
                font.pixelSize: Config.fontSize
            }

            Text {
                text: "They wait here until you show them. Critical ones still come through."
                width: Config.maxWidth - 48
                wrapMode: Text.Wrap
                color: Config.foregroundSoft
                font.family: Config.font
                font.weight: Font.Bold
                font.pixelSize: Config.fontSizeSmall
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            spacing: 8

            PillButton {
                visible: face.count > 0
                text: "Show"
                onClicked: Notifications.release()
            }

            PillButton {
                text: "Stop holding"
                onClicked: Notifications.setHolding(false)
            }
        }
    }
}
