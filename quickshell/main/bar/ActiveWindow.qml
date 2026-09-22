import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"

// Shows the focused window's icon + title. ToplevelManager.activeToplevel
// is compositor-global (one focused window across the whole compositor,
// not per-monitor), so this only renders on the bar whose monitor is
// actually focused — otherwise every monitor's bar would show the same
// title, which is wrong when the pointer/keyboard focus is elsewhere.
Item {
    id: root

    property var screen

    readonly property var toplevel: ToplevelManager.activeToplevel

    readonly property bool onFocusedMonitor: root.screen
        && Hyprland.monitorFor(root.screen) === Hyprland.focusedMonitor

    readonly property var desktopEntry: (root.toplevel && root.toplevel.appId !== "")
        ? DesktopEntries.byId(root.toplevel.appId) : null

    // Layout children with visible:false are excluded from the parent
    // RowLayout's size calculation (same trick MediaPlayer.qml uses), so
    // this collapses cleanly when nothing is focused or focus is on
    // another monitor, rather than leaving an empty gap.
    // Hiding an ancestor via `visible` would latch this false for good
    // — see the invariant on BarModuleLoader.qml's own `visible`.
    visible: root.toplevel !== null && root.onFocusedMonitor

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    HoverPill {
        id: pill
        // Was "+ 16" — see BarButton.qml's note on the same bump, made
        // when HoverPill went fully round.
        implicitWidth: content.implicitWidth + 22
        implicitHeight: content.implicitHeight + 6
        active: hover.hovered
        anchors.centerIn: parent

        RowLayout {
            id: content
            anchors.centerIn: parent
            spacing: 6

            Image {
                id: appIcon
                Layout.preferredWidth: Theme.iconSize
                Layout.preferredHeight: Theme.iconSize
                source: (root.desktopEntry && root.desktopEntry.icon !== "")
                    ? Quickshell.iconPath(root.desktopEntry.icon, true) : ""
                // Matches the Layout size above so the SVG rasterises at the
                // size it is drawn rather than being rescaled into it — see
                // bar/SystemTray.qml for the measurement.
                sourceSize.width: Theme.iconSize
                sourceSize.height: Theme.iconSize
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: status === Image.Ready
            }

            Text {
                text: root.toplevel ? (root.toplevel.title || "") : ""
                color: Appearance.fg
                font.pixelSize: Theme.fontMedium
                font.family: Theme.font
                elide: Text.ElideRight

                // Fixed, not just capped — this pill sits before "media"
                // in the bar's left-anchored group, so letting it shrink
                // to fit short titles shifts every item after it
                // (including the media pill's own buttons) whenever the
                // focused window's title changes length — e.g. a player
                // that puts the current track in its window title, which
                // then resizes this widget on every track change. See
                // MediaPlayer.qml's matching fix on its own title Text.
                Layout.preferredWidth: 280
            }
        }
    }

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: pill
        acceptedButtons: Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.toplevel) root.toplevel.close()
    }
}
