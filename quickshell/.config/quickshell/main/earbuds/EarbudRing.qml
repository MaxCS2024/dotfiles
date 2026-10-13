// One part of a pair of earbuds in the earbuds card: a ring whose filled
// arc is the charge, the part itself drawn in the middle, and its name and
// percentage underneath.
//
// The part in the middle is drawn rather than a glyph: no icon font this
// shell carries has a single bud or a charging case. The pair glyph
// (md-earbuds) cannot be cut in half for one, either — it is drawn wider
// than its advance, so half its width is not half the picture.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../config"
import "../services"
import "../theme"

ColumnLayout {
    id: root

    // "left", "right" or "case".
    required property string kind
    required property string title
    // services/Earbuds.qml's { level, charging, stale }.
    required property var part

    readonly property int level: root.part ? root.part.level : 0
    readonly property bool charging: !!root.part && root.part.charging && !root.part.stale
    readonly property bool stale: !!root.part && root.part.stale

    // A reading the earbuds have stopped repeating is drawn at rest rather
    // than in the warning colours: it was true a while ago, and a case that
    // read 20% before it went on the charger is not low now.
    readonly property color tone: root.stale ? Appearance.fgMuted
                                             : Battery.levelColor(root.level, root.charging)

    readonly property int ringSize: 72
    readonly property int stroke: 8

    spacing: Theme.space1

    Item {
        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: Theme.space1
        implicitWidth: root.ringSize
        implicitHeight: root.ringSize

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // The track: the whole circle, in the colour every other
            // level track in this shell sits on (common/Slider.qml).
            ShapePath {
                fillColor: "transparent"
                strokeColor: Appearance.trackBg
                strokeWidth: root.stroke
                capStyle: ShapePath.FlatCap
                PathAngleArc {
                    centerX: root.ringSize / 2
                    centerY: root.ringSize / 2
                    radiusX: (root.ringSize - root.stroke) / 2
                    radiusY: (root.ringSize - root.stroke) / 2
                    startAngle: 0
                    sweepAngle: 360
                }
            }

            // The charge, clockwise from twelve o'clock.
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.tone
                strokeWidth: root.stroke
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: root.ringSize / 2
                    centerY: root.ringSize / 2
                    radiusX: (root.ringSize - root.stroke) / 2
                    radiusY: (root.ringSize - root.stroke) / 2
                    startAngle: -90
                    sweepAngle: 360 * Math.max(0, Math.min(100, root.level)) / 100

                    Behavior on sweepAngle {
                        NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingDecel }
                    }
                }

                Behavior on strokeColor {
                    ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                }
            }
        }

        // A single bud: a round head, and the stem hanging from its outer
        // side — the left bud's on the left, the right bud's on the right,
        // the way the pair glyph (md-earbuds) draws them.
        Item {
            visible: root.kind !== "case"
            anchors.centerIn: parent
            width: 20
            height: 32

            Rectangle {
                x: root.kind === "left" ? 4 : 0
                width: 16
                height: 16
                radius: height / 2
                color: root.tone

                Behavior on color {
                    ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                }
            }

            Rectangle {
                x: root.kind === "left" ? 4 : 10
                y: 12
                width: 6
                height: 20
                radius: width / 2
                color: root.tone

                Behavior on color {
                    ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                }
            }
        }

        // The case: a rounded box with the seam of its lid.
        Rectangle {
            visible: root.kind === "case"
            anchors.centerIn: parent
            width: 28
            height: 20
            radius: height / 2
            color: root.tone

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                y: 6
                height: 2
                color: Appearance.surface
            }

            Behavior on color {
                ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
            }
        }
    }

    Text {
        Layout.alignment: Qt.AlignHCenter
        text: root.title
        color: Appearance.fgSoft
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
    }

    // The percentage, with a bolt while charging; "last seen" under a
    // reading the earbuds have stopped repeating.
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: root.level + "%" + (root.charging ? " 󱐋" : "")
        color: root.stale ? Appearance.fgMuted : Appearance.fg
        font.pixelSize: Theme.fontNormal
        font.family: Theme.font
    }

    Text {
        visible: root.stale
        Layout.alignment: Qt.AlignHCenter
        text: "last seen"
        color: Appearance.fgMuted
        font.pixelSize: Theme.fontTiny
        font.family: Theme.font
    }
}
