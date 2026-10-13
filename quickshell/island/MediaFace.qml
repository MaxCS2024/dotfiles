import Quickshell.Services.Mpris
import Quickshell.Widgets
import QtQuick

// The media face. Compact: the album art at the left end, the playing
// bars at the right. Expanded: art, title and artist, the progress, and
// previous / play-pause / next. It reads the player the activity carries.
Item {
    id: face

    property var activity: null
    property string mode: "compact"

    readonly property var player: activity?.player ?? null
    readonly property bool playing: player?.isPlaying ?? false

    // Compact is a fixed width: the art and the bars sit at the ends.
    implicitWidth: mode === "expanded" ? Config.expandedWidth - Config.padX * 2 : 168
    implicitHeight: mode === "expanded" ? Config.expandedHeight : Config.compactHeight

    // ── Compact ──
    Item {
        anchors.fill: parent
        visible: face.mode !== "expanded"

        Art {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            player: face.player
            size: 20
            radius: 6
        }

        PlayingBars {
            playing: face.playing
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // ── Expanded ──
    // Laid out at the full expanded size from the top, so nothing reflows
    // while the pill is still growing; the pill clips what doesn't fit yet.
    Item {
        visible: face.mode === "expanded"
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Config.expandedWidth
        height: Config.expandedHeight

        Art {
            id: bigArt
            x: 20
            y: 20
            player: face.player
            size: 56
            radius: 12
        }

        Column {
            anchors.left: bigArt.right
            anchors.leftMargin: 12
            anchors.right: bars.left
            anchors.rightMargin: 12
            anchors.verticalCenter: bigArt.verticalCenter
            spacing: 4

            Text {
                width: parent.width
                text: face.player?.trackTitle ?? ""
                elide: Text.ElideRight
                color: Config.foreground
                font.family: Config.font
                font.weight: Font.Bold
                font.pixelSize: Config.fontSize
            }

            Text {
                width: parent.width
                text: face.player?.trackArtist ?? ""
                visible: text !== ""
                elide: Text.ElideRight
                color: Config.foregroundSoft
                font.family: Config.font
                font.weight: Font.Bold
                font.pixelSize: Config.fontSize
            }
        }

        PlayingBars {
            id: bars
            playing: face.playing
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: bigArt.verticalCenter
        }

        // ── Progress ──
        Item {
            id: progress
            visible: face.player?.lengthSupported && face.player.length > 0
            x: 20
            y: 88
            width: parent.width - 40
            height: 16

            // MPRIS sends no ticks; asking for the position again each
            // second is how Quickshell's position moves.
            Timer {
                running: progress.visible && face.playing && face.visible
                interval: 1000
                repeat: true
                onTriggered: face.player.positionChanged()
            }

            readonly property real length: face.player?.length ?? 0
            readonly property real position: Math.min(face.player?.position ?? 0, length)

            Time {
                id: elapsed
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                seconds: progress.position
            }

            Rectangle {
                anchors.left: elapsed.right
                anchors.leftMargin: 12
                anchors.right: remaining.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: 4
                radius: height / 2
                color: Config.track

                Rectangle {
                    width: progress.length > 0 ? parent.width * progress.position / progress.length : 0
                    height: parent.height
                    radius: parent.radius
                    color: Config.foreground
                }
            }

            Time {
                id: remaining
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                seconds: progress.length - progress.position
                prefix: "-"
            }
        }

        // ── Controls ──
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 108
            spacing: 24

            Control {
                glyph: "\u{f04ae}"
                enabled: face.player?.canGoPrevious ?? false
                onActivated: face.player.previous()
            }
            Control {
                glyph: face.playing ? "\u{f03e4}" : "\u{f040a}"
                glyphSize: 24
                enabled: face.player?.canTogglePlaying ?? false
                onActivated: face.player.togglePlaying()
            }
            Control {
                glyph: "\u{f04ad}"
                enabled: face.player?.canGoNext ?? false
                onActivated: face.player.next()
            }
        }
    }

    // ── Parts ──
    // The track's art, or a music note on a dark square while there is none.
    component Art: ClippingRectangle {
        id: art
        property var player: null
        property int size: 20

        width: size
        height: size
        color: Config.track

        Text {
            anchors.centerIn: parent
            visible: cover.status !== Image.Ready
            text: "\u{f075a}"
            color: Config.foreground
            font.family: Config.font
            font.pixelSize: Math.round(art.size / 2)
        }

        Image {
            id: cover
            anchors.fill: parent
            source: art.player?.trackArtUrl ?? ""
            sourceSize.width: art.size * 2
            sourceSize.height: art.size * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }
    }

    // Four bars that dance while the player plays and lie flat when it
    // doesn't. Made up, not the audio: the brief asks for a playing
    // indicator. Stops while not on screen.
    component PlayingBars: Row {
        id: barsRow
        property bool playing: false
        spacing: 2

        readonly property bool dancing: playing && barsRow.visible

        Repeater {
            model: 4

            Rectangle {
                id: bar
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                radius: 1.5
                color: Config.foreground
                height: 3

                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Timer {
                    running: barsRow.dancing
                    interval: 180 + index * 20
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: bar.height = 4 + Math.round(Math.random() * 10)
                    onRunningChanged: if (!running) bar.height = 3
                }
            }
        }
    }

    component Time: Text {
        property real seconds: 0
        property string prefix: ""

        readonly property int whole: Math.max(0, Math.floor(seconds))
        text: prefix + Math.floor(whole / 60) + ":" + String(whole % 60).padStart(2, "0")
        color: Config.foregroundSoft
        font.family: Config.font
        font.weight: Font.Bold
        font.pixelSize: Config.fontSizeSmall
    }

    // A round button: a glyph, a faint fill on hover, dim when unavailable.
    component Control: Rectangle {
        id: control
        property string glyph: ""
        property int glyphSize: 20
        signal activated()

        width: 36
        height: 36
        radius: height / 2
        color: hover.hovered && enabled ? Config.track : Qt.rgba(1, 1, 1, 0)
        opacity: enabled ? 1 : 0.4

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: control.glyph
            color: Config.foreground
            font.family: Config.font
            font.pixelSize: control.glyphSize
        }

        HoverHandler { id: hover }

        MouseArea {
            anchors.fill: parent
            enabled: control.enabled
            onClicked: control.activated()
        }
    }
}
