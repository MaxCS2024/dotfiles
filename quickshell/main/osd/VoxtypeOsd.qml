import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import "../config"
import "../theme"
import "../services"

// Dictation, Wispr Flow style: a small pill at the bottom of the screen
// for as long as voxtype is recording or transcribing (services/
// Voxtype.qml). While recording it shows the microphone as a live
// waveform between a cancel button and a stop button; once the audio is
// handed off, the buttons fade and the bars turn into a travelling wave
// until the text has been typed.
//
// It borrows OsdWindow's window and exit timing and OsdBox's motion, but
// not the display timer: nothing here times out, it is up exactly while
// Voxtype.busy is. The pill is the one OSD you can click, so the window
// masks input to it instead of being click-through.
OsdWindow {
    id: osd

    surfaceNamespace: "quickshell:osd-voxtype"

    mask: Region { item: box }

    Connections {
        target: Voxtype
        function onBusyChanged() {
            if (Voxtype.busy) {
                // Start high so the first readings pull it down to the
                // room, and every recording starts from silence.
                osd.noiseFloor = 0
                osd.level = 0
                osd.heights = new Array(osd.barCount).fill(osd.barMin)
                osd.visible = true
                osd.shown = true
            } else {
                osd.shown = false
            }
        }
    }

    // ── The waveform ────────────────────────────────────────
    readonly property int barCount: 16
    readonly property int barMin: 2
    readonly property int barMax: Theme.space6

    // Heavier in the middle, so the loudest bars are the centre ones.
    readonly property var envelope: {
        const out = []
        for (let i = 0; i < osd.barCount; i++) {
            const t = (i - (osd.barCount - 1) / 2) / (osd.barCount / 2)
            out.push(Math.exp(-2.2 * t * t))
        }
        return out
    }

    property var heights: new Array(osd.barCount).fill(osd.barMin)
    property real level: 0
    // 0 → 2π, looping, while transcribing.
    property real phase: 0

    PwNodePeakMonitor {
        id: peak
        node: Mic.source
        enabled: Voxtype.recording && osd.visible
    }

    // Peak → 0..1, measured from the room's own noise floor rather
    // than from a fixed level: this machine's mic idles around -25 dB
    // peak, where a quiet one sits at -60, and a fixed range either shows
    // the fan as speech or a quiet voice as nothing. The floor follows
    // the quietest reading down at once and creeps back up (~0.8 dB/s),
    // so it settles on the gaps between words. Speech lands 10-30 dB
    // above it.
    //
    // The monitor reports on Pipewire's cubic volume scale, not a linear
    // one (room noise read 0.40 here against -24 dB from pw-record, and
    // 0.40³ is -24 dB), hence 60·log10 rather than 20. It reads 0 until
    // its first sample arrives, which would drag the floor to the bottom,
    // so a 0 is skipped.
    property real noiseFloor: 0

    function _loudness(p: real): real {
        if (p <= 0) return 0
        const db = 60 * Math.log10(p)
        osd.noiseFloor = db < osd.noiseFloor ? db : osd.noiseFloor + 0.05
        return Math.max(0, Math.min(1, (db - osd.noiseFloor - 4) / 24))
    }

    Timer {
        interval: 60
        repeat: true
        running: osd.visible && Voxtype.recording
        onTriggered: {
            const target = osd._loudness(peak.peak)
            // Fast attack, slow release: words jump up, gaps drift down.
            osd.level = target > osd.level ? target : osd.level * 0.8 + target * 0.2
            const span = osd.barMax - osd.barMin
            const next = []
            for (let i = 0; i < osd.barCount; i++) {
                const jitter = 0.55 + 0.45 * Math.random()
                next.push(osd.barMin + span * Math.min(1, osd.level * osd.envelope[i] * jitter * 1.3))
            }
            osd.heights = next
        }
    }

    NumberAnimation on phase {
        from: 0
        to: 2 * Math.PI
        duration: 900
        loops: Animation.Infinite
        running: osd.visible && Voxtype.transcribing
    }

    function _waveHeight(i: int): real {
        if (Voxtype.transcribing) {
            const s = Math.sin(osd.phase - i * 0.55)
            return osd.barMin + (Theme.space2 - osd.barMin) * Math.max(0, s)
        }
        return osd.heights[i]
    }

    OsdBox {
        id: box
        shown: osd.shown
        height: Theme.space10
        radius: height / 2
        width: Theme.space2 * 2 + Theme.space6 * 2 + Theme.space3 * 2 + wave.width

        // Cancel: throws the recording away instead of typing it
        // (`voxtype record cancel`).
        Rectangle {
            id: cancel
            anchors.left: parent.left
            anchors.leftMargin: Theme.space2
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.space6
            height: Theme.space6
            radius: height / 2
            color: cancelArea.containsMouse ? Appearance.hover : Appearance.surfaceAlt
            opacity: Voxtype.recording ? 1 : 0

            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
            Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingDecel } }

            Text {
                anchors.centerIn: parent
                text: "\u{F0156}"   // nf-md-close
                color: Appearance.fgSoft
                font.family: Theme.font
                font.pixelSize: Theme.fontNormal
            }

            MouseArea {
                id: cancelArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: Voxtype.recording
                cursorShape: Qt.PointingHandCursor
                onClicked: Voxtype.cancel()
            }
        }

        Row {
            id: wave
            anchors.centerIn: parent
            height: Theme.space6

            Repeater {
                model: osd.barCount

                // A 4px cell per bar (2px bar + 2px gap), so the bar's
                // height is the only thing that moves; the row's width
                // never changes.
                Item {
                    required property int index
                    width: Theme.space1
                    height: wave.height

                    Rectangle {
                        anchors.centerIn: parent
                        width: 2
                        radius: width / 2
                        height: osd._waveHeight(parent.index)
                        color: Voxtype.recording ? Appearance.fg : Appearance.fgMuted

                        Behavior on height {
                            enabled: Voxtype.recording
                            NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingDecel }
                        }
                        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                    }
                }
            }
        }

        // Stop: ends the recording and types it out, same as SUPER+V.
        // Red because the microphone is live; the one coloured thing on
        // the pill.
        Rectangle {
            id: stop
            anchors.right: parent.right
            anchors.rightMargin: Theme.space2
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.space6
            height: Theme.space6
            radius: height / 2
            color: Appearance.red
            opacity: Voxtype.recording ? 1 : 0
            scale: stopArea.pressed ? 0.9 : 1

            Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingDecel } }
            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingDecel } }

            Text {
                anchors.centerIn: parent
                text: "\u{F04DB}"   // nf-md-stop
                color: Appearance.bar
                font.family: Theme.font
                font.pixelSize: Theme.fontNormal
            }

            MouseArea {
                id: stopArea
                anchors.fill: parent
                enabled: Voxtype.recording
                cursorShape: Qt.PointingHandCursor
                onClicked: Voxtype.toggle()
            }
        }
    }
}
