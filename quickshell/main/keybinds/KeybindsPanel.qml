import Quickshell
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

// Every key this desktop binds, all of them on screen at once.
//
// The third home for this list and the first one with room for it. It
// was a pane of the old Settings window (no way to search it), then a
// level of the Conf menu (searchable at last, but forty rows in a slab
// 410px wide, one group at a time, where "Reload Hyprland config" and
// "Show or hide the bar" both elided beside their keys). Keys are a
// reference you scan, not a menu you walk: what you want is to see the
// whole table, or the part of it that matches a word, without paging
// through six groups to find out which one holds the key you half
// remember. So this is a window, and the list is Keybinds.qml's — the
// panel is only a view over it.
//
// What the shape follows from:
//
//   * One flat column, every row the full width of the window (user
//     request 2026-09-19). It was three columns of grouped rows, with
//     headings; the groups are still in Keybinds.qml, and still order
//     this list so related keys sit together, but nothing on screen
//     names them any more.
//   * Which means it scrolls: 44 rows do not fit a window that stops
//     at 82% of the screen, where three columns of them did. Hence the
//     ListView and the rail beside it.
//   * Filtering is over the flat list. A group's *name* still matches
//     all of its binds (Keybinds.matching), which with the headings
//     gone is the only way left to ask for "everything media".
//   * No selection, no Enter. Nothing here is actuable — every row is
//     a fact, and a row you can highlight invites a press that would
//     have to do nothing. Escape closes; the field takes everything
//     else.
//   * The field and the keys, and nothing else on the surface (user
//     request 2026-09-19). There was a title line above and a key
//     legend below; both said what the window already shows — it is
//     called Keybindings from the row that opens it, the field says
//     "Filter", and Escape is Escape everywhere in this shell.
//
// The Conf menu is the way in (its Learn › Keybindings row), and it
// hands over whatever was in its filter when you pressed Enter — see
// `find()`.
ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:keybinds"
    surfaceName: "keybinds"

    onSurfaceOpened: (query) => filterInput.text = query || ""
    focusTarget: filterInput

    // Theme.animPanel (220), not ShellSurface's 200: this surface fades on the
    // shell-wide panel duration, and a refactor is not the place to
    // quietly shorten it.
    exitDuration: Theme.animPanel

    anchors { top: true; bottom: true; left: true; right: true }



    // The field is the filter state; mirroring it into a property here
    // would just be two things to keep in step. Same call as the Conf
    // menu's.
    readonly property string query: filterInput.text

    readonly property var binds: Keybinds.matching(panel.query)


    // Clamped rather than handed straight to contentY: a Flickable will
    // happily sit past either end of its own content, and a list you
    // can push into empty space is a list that looks broken.
    function scrollBy(delta) {
        const limit = Math.max(0, list.contentHeight - list.height)
        list.contentY = Math.max(0, Math.min(list.contentY + delta, limit))
    }

    // ── Open / close ──────────────────────────────────────
    // Opening with a word already typed. The Conf menu's Keybindings row
    // sends whatever its own filter held, so "volume" there arrives here
    // as "volume" rather than being asked for twice; `qs ipc call
    // keybinds find <text>` is the same door from outside.
    // The query rides in on open() and arrives at onSurfaceOpened, so
    // one path serves the keybind, the IPC and the Conf menu row alike.
    function find(text) { panel.open(text || "") }


    // Only the window takes clicks — a near-miss on the backdrop does
    // nothing rather than dismissing it, same as the Conf menu and the
    // power menu. Focus leaving by any other route still closes.
    mask: Region { item: box }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: panel.shown ? 0.5 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard }
        }
    }

    // ── The window ────────────────────────────────────────
    Rectangle {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter
        // 800, which is what omarchy asks its own menu for:
        //
        //     omarchy-menu-select 'Keybindings' -- --width 800 --height 500
        //
        // A 35-character chord column and a short action name do not
        // fill 1100, which is what this was while it still had three
        // columns to spread. Capped against the surface so it still
        // fits a small screen.
        width: Math.min(800, Math.round(parent.width * 0.68))
        // Tall enough for the content and no taller, so a filtered
        // view shrinks to what it found instead of sitting in a fixed
        // box mostly empty. The ceiling is what makes the full list
        // scroll rather than overflow the screen — all 44 rows in one
        // column is taller than any display this runs on.
        height: Math.min(content.implicitHeight + 32, Math.round(parent.height * 0.82))
        y: Math.round((parent.height - box.height) / 2.6)
        radius: Theme.radius
        color: Appearance.surface
        border.width: 1
        border.color: Appearance.border

        opacity: panel.shown ? 1 : 0
        scale: panel.shown ? 1 : 0.97
        Behavior on opacity {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard }
        }
        Behavior on scale {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingDecel }
        }
        // The height chases the filter; without this it snaps on every
        // keystroke that changes how many groups survive.
        Behavior on height {
            NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingDecel }
        }

        layer.enabled: true
        layer.effect: PopupShadow {}
        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // ── Filter ────────────────────────────────────
            // No border (user request 2026-09-19) — the fill alone is
            // enough to say "type here". It used to carry the accent
            // while focused, which was never information: this field
            // takes focus when the window opens and is the only thing
            // in it that can hold focus, so the lit state was the only
            // state anyone ever saw.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: Theme.radius
                color: Appearance.surfaceAlt

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: "\u{F0349}"
                        color: Appearance.fgFaint
                        font.pixelSize: ConfStyle.fontHint
                        font.family: Theme.font
                    }

                    TextInput {
                        id: filterInput
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        color: Appearance.fg
                        font.pixelSize: ConfStyle.fontRow
                        font.family: Theme.font
                        clip: true
                        selectByMouse: true
                        selectionColor: Appearance.selected
                        verticalAlignment: TextInput.AlignVCenter

                        // Escape clears a typed filter before it closes
                        // the window, the same two-step the Conf menu's
                        // field does — one key that always means "back
                        // out of the last thing I did".
                        //
                        // The rest scroll the list. The field keeps
                        // focus the whole time this window is open, so
                        // without these there is no keyboard way to
                        // reach the bottom of a list that no longer
                        // fits — only the wheel. Up/Down and the paging
                        // keys never mean anything to a single-line
                        // field, so nothing is being taken from it.
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                if (filterInput.text !== "") filterInput.text = ""
                                else panel.close()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down) {
                                panel.scrollBy(ConfStyle.rowHeight * 3)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up) {
                                panel.scrollBy(-ConfStyle.rowHeight * 3)
                                event.accepted = true
                            } else if (event.key === Qt.Key_PageDown) {
                                panel.scrollBy(list.height)
                                event.accepted = true
                            } else if (event.key === Qt.Key_PageUp) {
                                panel.scrollBy(-list.height)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Home) {
                                list.positionViewAtBeginning()
                                event.accepted = true
                            } else if (event.key === Qt.Key_End) {
                                list.positionViewAtEnd()
                                event.accepted = true
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: filterInput.text.length === 0
                            text: "Filter by action or key…"
                            color: Appearance.placeholder
                            font.pixelSize: ConfStyle.fontRow
                            font.family: Theme.font
                        }
                    }
                }
            }

            // ── The keys ──────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: list.contentHeight
                spacing: 6
                visible: panel.binds.length > 0

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: panel.binds
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: bindRow
                        required property var modelData

                        width: list.width
                        height: ConfStyle.rowHeight

                        RowLayout {
                            anchors.fill: parent
                            spacing: 10

                            // Super + Shift + J → Move window down. No
                            // brackets: they were how the shape was
                            // described, not part of it. The chord list
                            // in Keybinds.qml is what puts the pluses
                            // in the right places.
                            //
                            // omarchy pads the chord to column 35 and
                            // then writes the arrow:
                            //
                            //     column = 35
                            //     printf "%-*s → %s", column, chord, action
                            //
                            // 35 monospace characters is what that is,
                            // so that is what this is — derived from
                            // the font rather than frozen at 273px, so
                            // it still holds 35 characters if the Conf
                            // scale moves again. Every chord here fits
                            // it twice over (the longest, "SUPER + RIGHT
                            // -DRAG", is 18), which is why the arrows
                            // sit in a column with air before them —
                            // omarchy's do the same.
                            Text {
                                Layout.preferredWidth: Math.round(ConfStyle.fontKeys * 0.6 * 35)
                                text: Keybinds.chord(bindRow.modelData)
                                color: Appearance.accent
                                font.pixelSize: ConfStyle.fontKeys
                                font.family: Theme.fontMono
                                elide: Text.ElideRight
                            }

                            Text {
                                text: "\u2192"
                                color: Appearance.fgDim
                                font.pixelSize: ConfStyle.fontKeys
                                font.family: Theme.font
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: bindRow.modelData.action
                                color: Appearance.fg
                                font.pixelSize: ConfStyle.fontRow
                                font.family: Theme.font
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                ListScrollBar {
                    Layout.fillHeight: true
                    view: list
                    trackColor: Appearance.scrollTrack
                    thumbColor: Appearance.scrollThumb
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 24
                Layout.bottomMargin: 24
                visible: panel.binds.length === 0
                horizontalAlignment: Text.AlignHCenter
                text: "No key matches “" + panel.query.trim() + "”"
                color: Appearance.fgFaint
                font.pixelSize: ConfStyle.fontRow
                font.family: Theme.font
            }

        }
    }
}
