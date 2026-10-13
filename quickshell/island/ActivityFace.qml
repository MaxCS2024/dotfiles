import QtQuick

// The generic face: draws any activity from its icon, label and progress,
// in the compact, transient or expanded layout. Features with a look of
// their own (media's art and waveform) get faces of their own later.
Item {
    id: face

    property var activity: null
    // "compact", "transient" or "expanded".
    property string mode: "compact"

    readonly property bool hasProgress: (activity?.progress ?? -1) >= 0

    implicitWidth: mode === "expanded" ? expandedLayout.implicitWidth : row.implicitWidth
    implicitHeight: mode === "expanded" ? Config.expandedHeight : row.implicitHeight

    // ── Compact and transient: one row ──
    Row {
        id: row
        visible: face.mode !== "expanded"
        anchors.centerIn: parent
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: face.activity?.icon ?? ""
            visible: text !== ""
            color: Config.foreground
            font.family: Config.font
            font.pixelSize: Config.iconSize
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Config.maxWidth - Config.padX * 2 - 80)
            text: face.activity?.label ?? ""
            elide: Text.ElideRight
            color: Config.foreground
            font.family: Config.font
            font.weight: Font.Bold
            font.pixelSize: Config.fontSize
        }

        // Only the transient row shows a level; compact stays a glance.
        Bar {
            anchors.verticalCenter: parent.verticalCenter
            visible: face.mode === "transient" && face.hasProgress
            width: 64
            value: face.activity?.progress ?? 0
        }
    }

    // ── Expanded: icon and label over a full-width bar ──
    Column {
        id: expandedLayout
        visible: face.mode === "expanded"
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 16

        Row {
            spacing: 16

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: face.activity?.icon ?? ""
                visible: text !== ""
                color: Config.foreground
                font.family: Config.font
                font.pixelSize: Config.expandedIconSize
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: expandedLayout.width - x
                text: face.activity?.label ?? ""
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                color: Config.foreground
                font.family: Config.font
                font.weight: Font.Bold
                font.pixelSize: Config.fontSize
            }
        }

        Bar {
            visible: face.hasProgress
            width: expandedLayout.width
            value: face.activity?.progress ?? 0
        }
    }

    component Bar: Rectangle {
        property real value: 0

        height: 4
        radius: height / 2
        color: Config.track

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.value))
            height: parent.height
            radius: parent.radius
            color: Config.foreground

            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
}
