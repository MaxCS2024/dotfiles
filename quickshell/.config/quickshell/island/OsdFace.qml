import QtQuick

// The OSD face: icon, level bar and percentage, in one fixed width so the
// pill holds still while the level moves and when volume hands over to
// brightness.
Item {
    id: face

    property var activity: null
    property string mode: "transient"

    readonly property real level: activity?.progress ?? 0

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 12

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Config.iconSize
            horizontalAlignment: Text.AlignHCenter
            text: face.activity?.icon ?? ""
            color: Config.foreground
            font.family: Config.font
            font.pixelSize: Config.iconSize
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 120
            height: 4
            radius: height / 2
            color: Config.track

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, face.level))
                height: parent.height
                radius: parent.radius
                color: Config.foreground

                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
        }

        // Right-aligned in the width of "100%".
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(widest.advanceWidth)
            horizontalAlignment: Text.AlignRight
            text: Math.round(face.level * 100) + "%"
            color: Config.foreground
            font.family: Config.font
            font.weight: Font.Bold
            font.pixelSize: Config.fontSize

            TextMetrics {
                id: widest
                text: "100%"
                font.family: Config.font
                font.weight: Font.Bold
                font.pixelSize: Config.fontSize
            }
        }
    }
}
