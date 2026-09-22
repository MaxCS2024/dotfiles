import Quickshell
import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"
import "../common/popupAnchor.js" as PopupAnchor
import "../common"

PopupWindow {
    id: root

    property Item anchorItem
    property var barWindow
    default property alias content: contentArea.data

    property int minWidth: 280
    property int edgeMargin: 5
    property int barGap: 2

    property bool anchorHovered: false
    property int openDelay: 300
    property int closeDelay: 150

    readonly property bool hovered: popupHover.hovered

    implicitWidth: Math.max(minWidth, contentArea.implicitWidth + 24)
    implicitHeight: contentArea.implicitHeight + 24
    color: "transparent"
    visible: false

    onAnchorHoveredChanged: {
        if (anchorHovered) { closeTimer.stop(); openTimer.restart() }
        else { openTimer.stop(); closeTimer.restart() }
    }

    onHoveredChanged: {
        if (hovered) closeTimer.stop()
        else if (!anchorHovered) closeTimer.restart()
    }

    Timer {
        id: openTimer
        interval: root.openDelay
        onTriggered: if (root.anchorHovered) root.visible = true
    }

    Timer {
        id: closeTimer
        interval: root.closeDelay
        onTriggered: if (!root.anchorHovered && !root.hovered) root.visible = false
    }

    anchor.window: barWindow
    anchor.rect: PopupAnchor.rectBelow(anchorItem, barWindow, implicitWidth, edgeMargin, barGap)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Appearance.surface
        border.color: Appearance.border
        border.width: 1

        layer.enabled: true
        layer.effect: PopupShadow {}
        HoverHandler { id: popupHover }

        ColumnLayout {
            id: contentArea
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6
        }
    }
}
