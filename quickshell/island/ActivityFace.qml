import QtQuick

// The generic face: draws any activity from its icon, label and progress,
// in the compact, transient, expanded or minimal (the split's circle)
// layout. Features with a look of
// their own (media's art and waveform) get faces of their own later.
Item {
    id: face

    property var activity: null
    // "compact", "transient" or "expanded".
    property string mode: "compact"

    readonly property bool hasProgress: (activity?.progress ?? -1) >= 0

    implicitWidth: mode === "expanded" ? expandedLayout.implicitWidth
        : mode === "minimal" ? Config.compactHeight
        : row.implicitWidth
    implicitHeight: mode === "expanded" ? Config.expandedHeight
        : mode === "minimal" ? Config.compactHeight
        : row.implicitHeight

    // ── Compact and transient: one row ──
    Row {
        id: row
        visible: face.mode === "compact" || face.mode === "transient"
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
            // What's left of the widest pill after the icon and the bar.
            width: Math.min(implicitWidth, Config.maxWidth - Config.padX * 2
                - (face.activity?.icon ? Config.iconSize + 8 : 0)
                - (face.hasProgress ? (face.mode === "transient" ? 64 : 40) + 8 : 0))
            text: face.activity?.label ?? ""
            elide: Text.ElideRight
            color: Config.foreground
            font.family: Config.font
            font.weight: Font.Bold
            font.pixelSize: Config.fontSize
        }

        // A level: 64px in a transient, 40px compact (a script's
        // download or build).
        Bar {
            anchors.verticalCenter: parent.verticalCenter
            visible: face.hasProgress
            width: face.mode === "transient" ? 64 : 40
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

    // ── Minimal: the icon, ringed by the level when there is one ──
    Item {
        visible: face.mode === "minimal"
        anchors.centerIn: parent
        width: Config.compactHeight
        height: width

        Text {
            anchors.centerIn: parent
            text: face.activity?.icon ?? ""
            color: Config.foreground
            font.family: Config.font
            font.pixelSize: Config.iconSize
        }

        Canvas {
            id: ring
            anchors.fill: parent
            anchors.margins: 3
            visible: face.hasProgress

            property real value: Math.max(0, Math.min(1, face.activity?.progress ?? 0))
            onValueChanged: requestPaint()
            onVisibleChanged: requestPaint()

            onPaint: {
                const c = getContext("2d")
                c.reset()
                c.lineWidth = 2
                c.lineCap = "round"
                const r = width / 2 - 1
                c.strokeStyle = Config.track
                c.beginPath()
                c.arc(width / 2, height / 2, r, 0, 2 * Math.PI)
                c.stroke()
                if (value <= 0)
                    return
                c.strokeStyle = Config.foreground
                c.beginPath()
                c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * value)
                c.stroke()
            }
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
