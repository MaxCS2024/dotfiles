import QtQuick

// The dictation face: up for as long as voxtype records or transcribes
// (Dictation.qml). A 24px round cancel button at the left end, the
// microphone as 16 live bars in the middle, a solid white stop button at
// the right end, each button 4px in from the pill's rounded end. Once
// the audio is handed off the buttons fade and the bars, dimmed to 60%,
// turn into a wave travelling left to right until the text is typed.
// Main's dictation pill (osd/VoxtypeOsd.qml), in the island's black and
// white. One width throughout, so the pill never twitches.
Item {
    id: face

    property bool shown

    // 24 + 12 + 64 + 12 + 24; the pill adds 4px at each end.
    implicitWidth: 136
    implicitHeight: 24
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 160 } }

    readonly property int barMin: 2
    readonly property int barMax: 16
    // 0 → 2π, looping, while transcribing.
    property real phase: 0

    NumberAnimation on phase {
        from: 0
        to: 2 * Math.PI
        duration: 900
        loops: Animation.Infinite
        running: face.visible && Dictation.transcribing
    }

    function barHeight(i) {
        if (Dictation.transcribing)
            return barMin + (8 - barMin) * Math.max(0, Math.sin(phase - i * 0.55))
        return barMin + (barMax - barMin) * Dictation.levels[i]
    }

    // Cancel: throws the recording away instead of typing it.
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        radius: 12
        color: Qt.rgba(1, 1, 1, cancelArea.containsMouse ? 0.2 : 0.12)
        opacity: Dictation.recording ? 1 : 0
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: "\u{f0156}"
            color: "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
        }

        MouseArea {
            id: cancelArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: Dictation.recording
            onClicked: Dictation.cancel()
        }
    }

    Row {
        anchors.centerIn: parent
        height: face.barMax

        Repeater {
            model: Dictation.barCount

            // A 4px cell per bar (2px bar, 2px gap), so only the
            // heights move.
            Item {
                required property int index
                width: 4
                height: face.barMax

                Rectangle {
                    anchors.centerIn: parent
                    width: 2
                    radius: 1
                    height: face.barHeight(parent.index)
                    color: "white"
                    opacity: Dictation.recording ? 1 : 0.6
                    Behavior on height {
                        enabled: Dictation.recording
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
            }
        }
    }

    // Stop: ends the recording and types it out, the same as SUPER+V.
    Rectangle {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        radius: 12
        color: "white"
        opacity: Dictation.recording ? 1 : 0
        scale: stopArea.pressed ? 0.9 : 1
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Text {
            anchors.centerIn: parent
            text: "\u{f04db}"
            color: "black"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
        }

        MouseArea {
            id: stopArea
            anchors.fill: parent
            enabled: Dictation.recording
            onClicked: Dictation.stop()
        }
    }
}
