import Quickshell.Services.Mpris
import Quickshell.Widgets
import QtQuick

// The media face. Compact: the album art at the left end, the playing
// bars at the right. Expanded: the dynamic-island's media player. It
// reads the player the activity carries.
Item {
    id: face

    property var activity: null
    property string mode: "compact"

    readonly property var player: activity?.player ?? null
    readonly property bool playing: player?.isPlaying ?? false

    // Compact is a fixed width: the art and the bars sit at the ends.
    // Minimal (the split's circle): the art alone, round. Expanded: the
    // player's 360 × 128 (the island adds its padX on either side).
    readonly property int playerWidth: 360
    readonly property int playerHeight: 128
    implicitWidth: mode === "expanded" ? playerWidth - Config.padX * 2
        : mode === "minimal" ? Config.compactHeight
        : 168
    implicitHeight: mode === "expanded" ? playerHeight : Config.compactHeight

    // ── Minimal ──
    Art {
        visible: face.mode === "minimal"
        anchors.centerIn: parent
        player: face.player
        size: 20
        radius: 10
    }

    // ── Compact ──
    Item {
        anchors.fill: parent
        visible: face.mode === "compact" || face.mode === "transient"

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

    // ── Expanded: the dynamic-island's media player ──
    // Ported from ../dynamic-island at the user's request: 360 × 128, 16px
    // in; the art (96px, 12px corners) on the left; beside it the title
    // (bold), the artist (white at 60%), a 4px progress bar, elapsed and
    // total time, and previous / play-pause / next as plain glyphs. Laid
    // out at its full size from the top, so nothing reflows while the
    // pill is still growing; the pill clips what doesn't fit yet.
    Item {
        id: playerView
        visible: face.mode === "expanded"
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: face.playerWidth
        height: face.playerHeight

        // MPRIS sends no ticks; asking for the position again each second
        // is how Quickshell's position moves.
        Timer {
            running: playerView.visible && face.playing && (face.player?.lengthSupported ?? false)
            interval: 1000
            repeat: true
            onTriggered: face.player.positionChanged()
        }

        readonly property real length: face.player?.length ?? 0
        readonly property real position: Math.min(face.player?.position ?? 0, length)
        readonly property real progress: length > 0 ? Math.max(0, Math.min(1, position / length)) : 0

        function formatTime(seconds) {
            const s = Math.max(0, Math.floor(seconds))
            return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
        }

        Art {
            id: bigArt
            x: 16
            y: 16
            player: face.player
            size: playerView.height - 32
            radius: 12
            // The player's dim note on a fainter square.
            glyphOpacity: 0.4
            glyphSize: 40
            fill: Config.button
        }

        Column {
            anchors.left: bigArt.right
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: bigArt.verticalCenter
            spacing: 4

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: face.player?.trackTitle || "Unknown"
                color: Config.foreground
                font.family: Config.font
                font.weight: Font.Bold
                font.pixelSize: Config.fontSize
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: face.player?.trackArtist ?? ""
                color: Config.foreground
                opacity: 0.6
                font.family: Config.font
                font.weight: Font.Bold
                font.pixelSize: Config.fontSize
            }

            Item { width: 1; height: 4 }

            Rectangle {
                width: parent.width
                height: 4
                radius: 2
                color: Config.track

                Rectangle {
                    width: parent.width * playerView.progress
                    height: parent.height
                    radius: 2
                    color: Config.foreground
                }
            }

            Item {
                width: parent.width
                height: 16

                Text {
                    anchors.left: parent.left
                    text: playerView.formatTime(playerView.position)
                    color: Config.foreground
                    opacity: 0.6
                    font.family: Config.font
                    font.weight: Font.Bold
                    font.pixelSize: Config.fontSizeSmall
                }

                Text {
                    anchors.right: parent.right
                    text: playerView.formatTime(playerView.length)
                    color: Config.foreground
                    opacity: 0.6
                    font.family: Config.font
                    font.weight: Font.Bold
                    font.pixelSize: Config.fontSizeSmall
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16

                Repeater {
                    model: [
                        { glyph: "\u{f04ae}", action: () => face.player.previous() },
                        { glyph: "", action: () => face.player.togglePlaying() },
                        { glyph: "\u{f04ad}", action: () => face.player.next() }
                    ]

                    delegate: Text {
                        required property var modelData
                        required property int index
                        width: 24
                        height: 24
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        // The middle button shows pause while playing.
                        text: index !== 1 ? modelData.glyph : face.playing ? "\u{f03e4}" : "\u{f040a}"
                        color: Config.foreground
                        font.family: Config.font
                        font.weight: Font.Bold
                        font.pixelSize: 18

                        MouseArea {
                            anchors.fill: parent
                            enabled: face.player !== null
                            onClicked: parent.modelData.action()
                        }
                    }
                }
            }
        }
    }

    // ── Parts ──
    // The track's art, or a music note on a dark square while there is none.
    component Art: ClippingRectangle {
        id: art
        property var player: null
        property int size: 20
        property real glyphOpacity: 1
        property int glyphSize: Math.round(size / 2)
        property color fill: Config.track

        width: size
        height: size
        color: fill

        Text {
            anchors.centerIn: parent
            visible: cover.status !== Image.Ready
            text: "\u{f075a}"
            color: Config.foreground
            opacity: art.glyphOpacity
            font.family: Config.font
            font.weight: Font.Bold
            font.pixelSize: art.glyphSize
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

    // Four bars: standing while the player plays, flat (3px) when it
    // doesn't. Made up, not the audio: the brief asks for a playing
    // indicator. `Config.mediaBars` picks how they move while playing:
    // "still" (fixed heights; no constant motion at the edge of sight),
    // "subtle" (slow, small swells) or "dancing". Moving ones stop while
    // not on screen.
    component PlayingBars: Row {
        id: barsRow
        property bool playing: false
        spacing: 2

        readonly property string style: Config.mediaBars
        readonly property bool moving: playing && barsRow.visible && style !== "still"
        readonly property var standing: [6, 11, 8, 13]

        Repeater {
            model: 4

            Rectangle {
                id: bar
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                radius: 1.5
                color: Config.foreground
                height: barsRow.playing ? barsRow.standing[index] : 3

                Behavior on height {
                    NumberAnimation {
                        duration: barsRow.style === "subtle" ? 700 : 180
                        easing.type: barsRow.style === "subtle" ? Easing.InOutSine : Easing.OutCubic
                    }
                }

                Timer {
                    running: barsRow.moving
                    interval: barsRow.style === "subtle" ? 700 + bar.index * 90 : 180 + bar.index * 20
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: bar.height = barsRow.style === "subtle"
                        ? barsRow.standing[bar.index] - 2 + Math.round(Math.random() * 4)
                        : 4 + Math.round(Math.random() * 10)
                    // Back to the binding's standing or flat height.
                    onRunningChanged: if (!running) bar.height = Qt.binding(() => barsRow.playing ? barsRow.standing[bar.index] : 3)
                }
            }
        }
    }
}
