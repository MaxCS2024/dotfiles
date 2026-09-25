import Quickshell
import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"
import "../common/popupAnchor.js" as PopupAnchor
import "../common"

// A tray item's own menu (Bitwarden's "Lock vault", …), drawn by the
// shell. SystemTray.qml used to call `modelData.display()`, which opens a
// *platform* menu — a QMenu — and that only exists when quickshell runs as
// a QApplication. This shell doesn't (shell.qml has no
// `//@ pragma UseQApplication`), so every right-click only logged "Cannot
// display PlatformMenuEntry" and showed nothing (found 2026-09-25). Turning
// the pragma on would bring back a native Qt menu that ignores Appearance
// entirely; this reads the same dbusmenu through QsMenuOpener and draws it
// like the other bar popups instead.
//
// Submenus open in place: choosing one swaps the list for its children,
// with a back row on top, rather than cascading a second popup.
PopupWindow {
    id: root

    property Item anchorItem
    property var barWindow
    // The tray item's `menu` (a QsMenuHandle). Opening resets to it.
    property var rootMenu

    property int minWidth: 160
    property int edgeMargin: Theme.space1
    property int barGap: 2
    readonly property int rowHeight: 28

    // The menu currently shown: rootMenu, or a submenu drilled into.
    property var _menu: null
    property var _parents: []

    function open() {
        root._parents = []
        root._menu = root.rootMenu
        root.visible = true
    }

    function _enter(entry) {
        root._parents = root._parents.concat([root._menu])
        root._menu = entry
    }

    function _back() {
        const p = root._parents.slice()
        root._menu = p.pop()
        root._parents = p
    }

    function _activate(entry) {
        if (!entry.enabled || entry.isSeparator) return
        if (entry.hasChildren) { root._enter(entry); return }
        entry.triggered()
        root.visible = false
    }

    implicitWidth: Math.max(root.minWidth, list.implicitWidth + Theme.space1 * 2)
    implicitHeight: list.implicitHeight + Theme.space1 * 2
    color: "transparent"
    visible: false
    // Closes on a click anywhere else, the way a menu is expected to.
    grabFocus: true

    anchor.window: root.barWindow
    anchor.rect: PopupAnchor.rectBelow(root.anchorItem, root.barWindow, root.implicitWidth, root.edgeMargin, root.barGap)

    QsMenuOpener {
        id: opener
        menu: root.visible ? root._menu : null
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Appearance.surface
        border.color: Appearance.border
        border.width: 1

        layer.enabled: true
        layer.effect: PopupShadow {}

        ColumnLayout {
            id: list
            anchors.fill: parent
            anchors.margins: Theme.space1
            spacing: 0

            MenuRow {
                visible: root._parents.length > 0
                glyph: ""
                label: "Back"
                onChosen: root._back()
            }

            Repeater {
                model: opener.children

                delegate: Loader {
                    id: entryLoader
                    required property var modelData
                    Layout.fillWidth: true
                    // An entry with no label has nothing to click on. (The
                    // dbusmenu `visible` flag has no QsMenuEntry property,
                    // so hidden-but-labelled entries, like Bitwarden's two
                    // "Fake Popup" ones, rely on quickshell dropping them.)
                    visible: modelData.isSeparator || modelData.text !== ""
                    sourceComponent: modelData.isSeparator ? separator : row

                    Component {
                        id: separator
                        Item {
                            implicitHeight: Theme.space2 + 1
                            Divider {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                            }
                        }
                    }

                    Component {
                        id: row
                        MenuRow {
                            readonly property var entry: entryLoader.modelData
                            readonly property bool checkable: entry.buttonType !== QsMenuButtonType.None
                            glyph: checkable && entry.checkState === Qt.Checked ? "" : ""
                            reserveGlyph: checkable
                            label: entry.text.replace(/_(?!_)/g, "")
                            trailing: entry.hasChildren ? "" : ""
                            enabled: entry.enabled
                            onChosen: root._activate(entry)
                        }
                    }
                }
            }
        }
    }

    // One clickable line. Hover is a fill one step up the ladder (§2/§4 of
    // STYLE.md); a disabled entry drops to the disabled text colour.
    component MenuRow: Rectangle {
        id: menuRow

        property string glyph: ""
        property bool reserveGlyph: false
        property string label: ""
        property string trailing: ""
        signal chosen()

        Layout.fillWidth: true
        implicitWidth: rowLayout.implicitWidth + Theme.space3 * 2
        implicitHeight: root.rowHeight
        radius: Theme.radius
        color: rowHover.hovered && menuRow.enabled ? Appearance.hover : Appearance.clear(Appearance.hover)

        Behavior on color {
            ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
        }

        HoverHandler { id: rowHover }
        TapHandler { onTapped: if (menuRow.enabled) menuRow.chosen() }

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            anchors.leftMargin: Theme.space3
            anchors.rightMargin: Theme.space3
            spacing: Theme.space2

            Text {
                visible: menuRow.glyph !== "" || menuRow.reserveGlyph
                Layout.preferredWidth: Theme.iconSize
                text: menuRow.glyph
                color: menuRow.enabled ? Appearance.fg : Appearance.disabled
                font.family: Theme.font
                font.pixelSize: Theme.fontSmall
            }

            Text {
                Layout.fillWidth: true
                text: menuRow.label
                color: menuRow.enabled ? Appearance.fg : Appearance.disabled
                font.family: Theme.font
                font.pixelSize: Theme.fontMedium
                elide: Text.ElideRight
            }

            Text {
                visible: menuRow.trailing !== ""
                text: menuRow.trailing
                color: Appearance.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSmall
            }
        }
    }
}
