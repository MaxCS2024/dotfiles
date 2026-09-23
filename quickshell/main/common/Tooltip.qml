import Quickshell
import QtQuick
import "../config"
import "popupAnchor.js" as PopupAnchor
import "../theme"

// Themed replacement for QtQuick.Controls.ToolTip, which renders with
// the platform style and ignores Theme entirely (see SystemTray.qml's
// prior usage). Same hover-intent shape and anchoring as
// bar/DropdownPanel.qml — the anchor-rect geometry is shared via
// common/popupAnchor.js rather than duplicated.
PopupWindow {
    id: root

    property Item anchorItem
    property var barWindow
    property string text: ""

    property int edgeMargin: 5
    property int gap: 6
    property int maxWidth: 260
    property int openDelay: 300
    property int closeDelay: 150

    // Driven by the caller's own hover handler (a tray icon, a future
    // active-window label, etc.) rather than this popup tracking hover
    // itself — unlike DropdownPanel, a tooltip has no interactive
    // content of its own to keep it open once the pointer leaves the
    // anchor.
    property bool anchorHovered: false

    implicitWidth: label.width + 16
    implicitHeight: label.implicitHeight + 10
    color: "transparent"
    visible: false

    onAnchorHoveredChanged: {
        if (anchorHovered) { closeTimer.stop(); openTimer.restart() }
        else { openTimer.stop(); closeTimer.restart() }
    }

    Timer {
        id: openTimer
        interval: root.openDelay
        onTriggered: if (root.anchorHovered) root.visible = true
    }

    Timer {
        id: closeTimer
        interval: root.closeDelay
        onTriggered: if (!root.anchorHovered) root.visible = false
    }

    anchor.window: root.barWindow
    anchor.rect: PopupAnchor.rectBelow(root.anchorItem, root.barWindow, root.implicitWidth, root.edgeMargin, root.gap)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Appearance.surface
        border.color: Appearance.border
        border.width: 1

        layer.enabled: true
        layer.effect: PopupShadow {}
        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            color: Appearance.fg
            font.pixelSize: Theme.fontSmall
            font.family: Theme.font
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            width: Math.min(implicitWidth, root.maxWidth)
        }
    }
}
