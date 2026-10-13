import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"
import "../common"

Item {
    id: content
    anchors.fill: parent

    // Driven by the window — see osd/OsdWindow.qml, which owns when this
    // goes true and false, and the two timers behind that.
    required property bool shown

    property string icon: ""
    property real value: 0
    property bool muted: false
    property color accentColor: Appearance.green
    property color mutedColor: Appearance.red
    property string valueText: muted ? "Muted" : Math.round(value) + "%"
    property string unavailableText: ""

    OsdBox {
        shown: content.shown
        width: 280

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.space4
            spacing: Theme.space3

            Text {
                text: content.icon
                color: content.muted ? content.mutedColor : Appearance.icon
                font.pixelSize: 20
                font.family: Theme.font
            }

            Rectangle {
                visible: content.unavailableText === ""
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 8
                radius: Theme.radius
                color: Appearance.trackBg

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, content.value / 100))
                    height: parent.height
                    radius: Theme.radius
                    color: content.muted ? content.mutedColor : content.accentColor
                    Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                }
            }

            Text {
                visible: content.unavailableText !== ""
                text: content.unavailableText
                color: Appearance.fgDim
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                visible: content.unavailableText === ""
                text: content.valueText
                color: Appearance.fg
                font.pixelSize: Theme.fontNormal
                font.family: Theme.font
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
