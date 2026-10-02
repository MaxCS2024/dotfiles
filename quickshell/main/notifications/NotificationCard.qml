// Notification card.
//
// Renders a plain-data row (services/Notifications.qml), never a live
// Notification object, so the same component draws a live toast and one
// restored from disk.
//
// The sending app's icon sits before the headline, so a card says where it
// came from; only the app's own icon, never `image` (an avatar or a
// thumbnail), and nothing in its place when the app names none — no
// fallback glyph, no close mark. Left-click runs the row's action (or
// dismisses when there is none); right-click always dismisses.
import Quickshell
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

Item {
    id: root

    required property var row
    // Countdown remaining, 1.0 down to 0.0; negative hides it.
    property real progress: -1

    readonly property bool hovered: cardHover.hovered
    readonly property bool _critical: root.row.urgency === "critical"
    readonly property bool _low: root.row.urgency === "low"
    readonly property string _title: root.row.summary || root.row.appName || ""
    readonly property string _body: root.row.body || ""
    readonly property var _actions: Notifications.actionsFor(root.row)
    readonly property bool _activatable: Notifications.isActivatable(root.row)
    readonly property string _appIcon: Notifications.iconFor(root.row)

    // Urgency is text colour only: red headline when critical.
    readonly property color _titleColor: root._critical ? Appearance.red : Appearance.fgStrong

    HoverHandler { id: cardHover }

    implicitHeight: box.implicitHeight

    Rectangle {
        id: box
        width: parent.width
        implicitHeight: content.implicitHeight + 2 * Theme.space3
        radius: Theme.radius
        color: root.hovered ? Appearance.hover : Appearance.surface
        border.width: 2
        border.color: Appearance.border
        clip: true

        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

        layer.enabled: true
        layer.effect: PopupShadow {}
        HyprFrame { frameWidth: box.border.width; targetRadius: box.radius }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton && root._activatable)
                    Notifications.activate(root.row)
                else
                    Notifications.dismiss(root.row)
            }
        }
        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: Theme.space4
            anchors.rightMargin: Theme.space4
            anchors.topMargin: Theme.space3
            spacing: Theme.space1

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                Image {
                    Layout.preferredWidth: Theme.iconSize
                    Layout.preferredHeight: Theme.iconSize
                    source: root._appIcon
                    // Rasterised at the size it is drawn — see
                    // bar/SystemTray.qml.
                    sourceSize.width: Theme.iconSize
                    sourceSize.height: Theme.iconSize
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    visible: status === Image.Ready
                }

                Text {
                    text: root._title
                    color: root._titleColor
                    font.bold: true
                    font.pixelSize: Theme.fontMedium
                    font.family: Theme.font
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            Text {
                visible: root._body !== ""
                text: root._body
                textFormat: Text.PlainText
                color: root._low ? Appearance.fgMuted : Appearance.fgSoft
                font.pixelSize: Theme.fontMedium
                font.family: Theme.font
                lineHeight: 1.2
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

                RowLayout {
                    visible: root._actions.length > 0
                    Layout.topMargin: Theme.space1
                    spacing: Theme.space2

                    Repeater {
                        model: root._actions

                        delegate: Rectangle {
                            id: actionBtn
                            required property var modelData

                            implicitWidth: actionLabel.implicitWidth + Theme.space6
                            implicitHeight: 24
                            radius: Theme.radius
                            color: actionHover.hovered ? Appearance.hoverStrong : Appearance.hover

                            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

                            Text {
                                id: actionLabel
                                anchors.centerIn: parent
                                text: actionBtn.modelData.text
                                color: Appearance.fg
                                font.pixelSize: Theme.fontSmall
                                font.family: Theme.font
                            }

                            HoverHandler { id: actionHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Notifications.invokeAction(root.row, actionBtn.modelData)
                            }
                        }
                    }
                }
        }

        // Countdown: a faint 2px rule inside the frame. Latched so a hover
        // pause freezes it instead of draining it.
        Rectangle {
            id: countdown
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: box.border.width
            height: 2
            color: Appearance.clear(Appearance.fgMuted)
            opacity: root.progress >= 0 ? 1 : 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard } }

            property real shownFraction: 0
            Connections {
                target: root
                function onProgressChanged() {
                    if (root.progress >= 0)
                        countdown.shownFraction = Math.max(0, Math.min(1, root.progress))
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * countdown.shownFraction
                color: Appearance.fgMuted
                opacity: 0.5
                Behavior on width { NumberAnimation { duration: 50; easing.type: Easing.Linear } }
            }
        }
    }
}
