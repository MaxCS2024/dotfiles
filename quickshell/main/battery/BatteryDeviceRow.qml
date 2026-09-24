// One battery in the battery rail's lists — a pack in the bay, a
// peripheral that reports a charge, or one part of a pair of earbuds.
//
// The shape is quicksettings/MixerTab.qml's stream row, which the volume
// rail draws too: a glyph, a name with its state beside it, a faint line
// of detail, and a bar. A pack and a playback stream have nothing in
// common except being one of several things each with a level, and that
// is exactly the part this shell should draw the same way twice.
//
// Not clickable, and deliberately not hover-tinted: there is nothing to
// do to a battery. It sits on surfaceAlt instead — a plate that says
// "a thing" where a hover tint would say "a button".
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

Rectangle {
    id: root

    // A UPowerDevice, from services/Battery.qml's `packs` or
    // `peripherals`. Everything below is read off it by default; an
    // earbud (services/Earbuds.qml), which is a level and nothing else,
    // leaves it null and sets them itself.
    property var device: null

    property real pct: root.device ? root.device.percentage * 100 : 0
    property color tone: Battery.deviceColor(root.device)
    property string glyph: Battery.deviceIcon(root.device)
    property string label: Battery.deviceLabel(root.device)
    property string stateText: Battery.deviceState(root.device)
    property string valueText: Math.round(root.pct) + "%"
    // Energy and wear, joined only where both exist — a peripheral reports
    // neither and gets no line at all rather than a row of dashes.
    property string detail: {
        const energy = Battery.deviceEnergy(root.device)
        const health = Battery.deviceHealth(root.device)
        return energy !== "" && health !== "" ? energy + " · " + health
            : energy !== "" ? energy
            : health
    }

    // The row is as tall as what is in it, like the card it sits on.
    implicitHeight: rowBody.implicitHeight + 16
    radius: Theme.radius
    color: Appearance.surfaceAlt

    RowLayout {
        id: rowBody

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.space2
        anchors.rightMargin: Theme.space2
        spacing: Theme.space2

        Text {
            text: root.glyph
            color: root.tone
            font.pixelSize: 18
            font.family: Theme.font
            Layout.alignment: Qt.AlignVCenter

            Behavior on color {
                ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: Theme.space1

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                Text {
                    text: root.label
                    color: Appearance.fg
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }

                // The state this one pack is in, which is the whole
                // reason the list exists: a ThinkPad charges its bay
                // packs one at a time, so the row that is not moving
                // says "Waiting" rather than leaving you to wonder.
                Text {
                    text: root.stateText
                    color: Appearance.fgMuted
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                }

                Text {
                    text: root.valueText
                    color: root.tone
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                    }
                }
            }

            Text {
                visible: text !== ""
                text: root.detail
                color: Appearance.fgFaint
                font.pixelSize: Theme.fontTiny
                font.family: Theme.font
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
            }

            Slider {
                Layout.fillWidth: true
                trackHeight: 4
                value: Math.max(0, Math.min(1, root.pct / 100))
                trackColor: Appearance.trackBg
                fillColor: root.tone
            }
        }
    }
}
