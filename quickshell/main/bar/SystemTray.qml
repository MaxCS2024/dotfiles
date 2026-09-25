import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"
import "../common"

// Every registered tray icon, always shown, in a row.
//
// Until 2026-09-23 this was collapsed behind an arrow that slid the icons
// out to its left on a click (user request 2026-09-16); the user asked
// for the slider to go, so the icons sit in the bar the whole time and
// the arrow, its reveal animation and its urgency tint went with it.
Item {
    id: root

    property int iconSize: Theme.iconSize
    property var barWindow

    readonly property int spacing: Theme.space1

    // Hidden while nothing is registered, like MediaPlayer with no
    // player, so an empty tray leaves no gap in the row (see
    // bar/BarModuleLoader.qml). The arrow was deliberately kept up when
    // empty — Quickshell's SystemTray can start with a stale, empty view
    // that a reload fixes, and a trigger that vanished read as a missing
    // button. With no trigger left there is nothing to go missing: a
    // stale tray is empty either way.
    readonly property bool hasContent: SystemTray.items.values.length > 0

    implicitWidth: row.implicitWidth
    implicitHeight: root.iconSize

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.spacing

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayItem
                required property var modelData

                implicitWidth: root.iconSize
                implicitHeight: root.iconSize

                // Some apps ask for their -symbolic icon, which is one
                // flat grey (#bebebe) by design: Spotify's tray item
                // names com.spotify.Client-symbolic, so its icon showed
                // grey instead of green (2026-09-25). Where the theme
                // has the full-colour icon of the same name, that is
                // drawn instead; otherwise the symbolic one stays.
                //
                // Some name an icon the host doesn't have: Flatpak VLC's
                // tray item asks for "vlc", but the Flatpak exports it as
                // org.videolan.VLC, so it drew as a "not found" placeholder
                // (2026-09-25). Then the app's desktop entry, found from
                // the item's id, supplies the icon. Desktop entries load
                // after startup; reading the list re-runs this when they do.
                readonly property string iconSource: {
                    const src = trayItem.modelData.icon
                    const m = /^image:\/\/icon\/([^?]+)$/.exec(src)
                    if (!m) return src
                    const sym = /^(.+)-symbolic$/.exec(m[1])
                    if (sym) {
                        const full = Quickshell.iconPath(sym[1], true)
                        if (full !== "") return full
                    }
                    if (Quickshell.iconPath(m[1], true) !== "") return src
                    DesktopEntries.applications.values
                    const entry = DesktopEntries.heuristicLookup(trayItem.modelData.id)
                        ?? DesktopEntries.heuristicLookup(m[1])
                    if (!entry || entry.icon === "") return src
                    const fromEntry = Quickshell.iconPath(entry.icon, true)
                    return fromEntry !== "" ? fromEntry : src
                }

                Image {
                    id: trayIcon
                    anchors.fill: parent
                    // modelData.icon is already a loadable URL — see
                    // this file's own git history, 2026-09-16, for
                    // the doubled image://icon/ prefix that used to
                    // make every tray icon a "not found" placeholder.
                    source: trayItem.iconSource
                    // Rasterises the SVG at the size it's drawn
                    // instead of being rescaled into it — see the
                    // same day's measurement (28 vs 69 tones).
                    sourceSize.width: root.iconSize
                    sourceSize.height: root.iconSize
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    opacity: trayItem.modelData.status === Status.NeedsAttention ? 1.0 : 0.9

                    // Icon lookups can fail if a tray item registers
                    // before its icon theme path is mounted/indexed
                    // yet (e.g. a flatpak app right after login) —
                    // Quickshell doesn't retry a failed lookup, and
                    // it renders a "not found" placeholder rather
                    // than an error, so nothing here would otherwise
                    // notice. Re-run the same lookup once, shortly
                    // after creation, to self-heal that race.
                    Timer {
                        interval: 3000
                        running: true
                        onTriggered: {
                            trayIcon.source = ""
                            trayIcon.source = Qt.binding(() => trayItem.iconSource)
                        }
                    }
                }

                TrayMenu {
                    id: trayMenu
                    anchorItem: trayItem
                    barWindow: root.barWindow
                    rootMenu: trayItem.modelData.menu
                }

                MouseArea {
                    id: trayMouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    hoverEnabled: true
                    // Drawn by the shell, not modelData.display() — see
                    // TrayMenu.qml for why the platform menu never opened.
                    function showMenu() {
                        if (!trayItem.modelData.hasMenu) return
                        if (trayMenu.visible) trayMenu.visible = false
                        else trayMenu.open()
                    }

                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            if (trayItem.modelData.onlyMenu) trayMouse.showMenu()
                            else trayItem.modelData.activate()
                        } else if (mouse.button === Qt.MiddleButton) {
                            trayItem.modelData.secondaryActivate()
                        } else if (mouse.button === Qt.RightButton) {
                            trayMouse.showMenu()
                        }
                    }

                    onWheel: wheel => trayItem.modelData.scroll(wheel.angleDelta.y, false)

                    Tooltip {
                        anchorItem: trayItem
                        barWindow: root.barWindow
                        anchorHovered: trayMouse.containsMouse
                        text: {
                            const title = trayItem.modelData.tooltipTitle || trayItem.modelData.title
                            const description = trayItem.modelData.tooltipDescription
                            return description ? (title + "\n" + description) : title
                        }
                    }
                }
            }
        }
    }
}
