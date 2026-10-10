import Quickshell.Services.Pipewire
import QtQuick

// One PipeWire node's volume in the settings window: a round 32px icon
// button that mutes and unmutes (white at 12% while hovered), the
// slider, and the percentage in bold 13px, left-aligned in the width of
// "100%". Capped at 100%, like the island's slider; muted reads 0%.
// `level` (0–1, or -1 for none) draws the input meter: a 2px line under
// the slider's track.
Item {
    id: row

    property PwNode node: null
    property bool input: false
    property real level: -1

    readonly property bool ready: node !== null && node.audio !== null
    readonly property real volume: ready ? Math.min(1, node.audio.volume) : 0
    readonly property bool muted: ready ? node.audio.muted : false
    readonly property real shown: muted ? 0 : volume

    implicitHeight: 32
    opacity: ready ? 1 : 0.4

    Rectangle {
        id: muteButton
        width: 32
        height: 32
        radius: 16
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(1, 1, 1, muteArea.containsMouse ? 0.12 : 0)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            // Microphone on/off, or the speaker's off / low / medium / high.
            text: row.input ? (row.shown === 0 ? "\u{f036d}" : "\u{f036c}")
                : row.shown === 0 ? "\u{f0581}"
                : row.shown < 0.34 ? "\u{f057f}"
                : row.shown < 0.67 ? "\u{f0580}" : "\u{f057e}"
            color: "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 18
        }

        MouseArea {
            id: muteArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: row.ready
            onClicked: row.node.audio.muted = !row.node.audio.muted
        }
    }

    Slider {
        id: slider
        anchors.left: muteButton.right
        anchors.leftMargin: 8
        anchors.right: percent.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        enabled: row.ready
        value: row.shown
        onMoved: v => {
            row.node.audio.volume = v
            if (v > 0 && row.node.audio.muted)
                row.node.audio.muted = false
        }
    }

    // The input meter, under the track.
    Rectangle {
        visible: row.level >= 0
        anchors.left: slider.left
        y: slider.y + slider.height / 2 + 6
        width: slider.width * Math.max(0, row.level)
        height: 2
        radius: 1
        color: "white"
        opacity: 0.6
        Behavior on width { NumberAnimation { duration: 60 } }
    }

    Text {
        id: percent
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: fit.implicitWidth
        text: Math.round(row.shown * 100) + "%"
        color: "white"
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13

        Text {
            id: fit
            visible: false
            text: "100%"
            font: percent.font
        }
    }
}
