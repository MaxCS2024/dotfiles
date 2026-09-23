// The themes menu — a card that drops from the top of the screen,
// opened from the conf menu's Style section or the themes-toggle key.
//
// Palettes.qml next door has held eight named palettes since it was
// written, and the only way to reach them was System settings ›
// Appearance: open the window, find the tab, set Theme Source to Themes,
// then pick a chip out of a Flow. That is the right place to *edit* a
// palette — eight colour rows, hex fields, a reset per row — and the
// wrong place to *switch* one, which is something done on a whim and
// undone as fast.
//
// Then the settings panel was deleted outright (2026-09-21) — every one
// of its tabs had been replaced by a rail, a card or a window, and this
// card was the last replacement it was waiting for — so the editing half
// came here too, as a second level behind the Edit pill. One surface
// switches a palette and edits one, and nothing else in the shell does
// either.
//
// Built like calendar/CalendarPanel.qml rather than like a rail, for the
// reason that card is: it drops from under the bar rather than filling a
// screen edge. It hung under a bar module of its own until 2026-09-22;
// it is opened from the conf menu's Style section and the themes-toggle
// shortcut now, and centres itself (see cardSlot below).
//
// Two kinds of row, which is the whole of the model Appearance.qml has:
//
//   · Wallpaper — useCustom false, the palette following the wallpaper
//     (matugen), or the Default preset until matugen has run.
//   · one row per Palettes.list entry — useCustom true, pinned to that
//     palette's eight colours.
//
// Nothing here records which of them is showing. Appearance.
// matchesPalette() reads that back off the colours themselves (see its
// own note), so a palette hand-edited afterwards in the settings tab
// simply stops being ticked here, with no stored name to go stale.
//
// Picking does not close the card. Choosing a theme is done by eye, and
// this card is drawn in Appearance's own tones — it repaints with
// everything else, so it is its own preview, and trying all eight is
// eight keystrokes rather than eight round trips. Escape, a click
// outside, or the key again closes it.
import Quickshell
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"

ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:themes"
    surfaceName: "themes"
    focusTarget: card

    // Room below and beside the card for its own shadow, which a
    // layer-shell surface clips like anything else.
    readonly property int shadowPad: 24
    // Wide enough for "Catppuccin Mocha" beside its two swatches without
    // eliding, which is the longest name Palettes.list carries.
    // Which level is showing: the nine-row menu, or the palette editor
    // behind the Edit pill. One card, two contents — rather than a second
    // window — because editing a palette is looking at it, and a surface
    // that moved or resized between choosing and adjusting would break
    // that in the one place it matters.
    property bool editing: false

    // The menu is as wide as its longest theme name; the editor is as
    // wide as a PaletteColorRow (78 label + 22 swatch + 96 field + 38
    // reset, and the spacing between them). The card animates between
    // the two — see cardSlot.
    readonly property int cardWidth: panel.editing ? 302 : 236
    readonly property int rowHeight: 30

    // Content, plus the padding either side of it — the same contract as
    // the calendar and the rails, and the same reason it doesn't loop: a
    // ColumnLayout's implicitHeight comes from its children, and nothing
    // in `body` fills height.
    readonly property int cardHeight: body.implicitHeight + Theme.cardPadding * 2


    // Up and behind the bar, not sideways: this card belongs to a module
    // in the bar, and the bar is where it should come from and go back
    // to. Far enough that the shadow clears too.
    readonly property int slideDistance: panel.cardHeight + panel.inset + 24


    // Following the wallpaper first, then the named palettes in
    // Palettes.list's own order. One array rather than two lists side by
    // side so the keyboard walks the whole menu, the wallpaper row
    // included — it is a choice among the rest, not a switch above them.
    readonly property var entries: [{ wallpaper: true, name: "Wallpaper" }].concat(Palettes.list)

    // Which Appearance property each editor row writes (`key`) and which
    // resolved token it previews (`token`) — the same for the three base
    // colours, different for anything derived. `derivable` marks the rows
    // whose override can be cleared back to "" (see PaletteColorRow.qml).
    readonly property var baseColors: [
        { key: "customBg",      token: "customBg",     label: "Background", derivable: false },
        { key: "customSurface", token: "surface",      label: "Surface",    derivable: true },
        { key: "customFg",      token: "customFg",     label: "Text",       derivable: false },
        { key: "customAccent",  token: "customAccent", label: "Accent",     derivable: false },
        { key: "customBorder",  token: "border",       label: "Border",     derivable: true },
    ]
    readonly property var statusColors: [
        { key: "customGreen",  token: "green",  label: "Success", derivable: true },
        { key: "customOrange", token: "orange", label: "Warning", derivable: true },
        { key: "customRed",    token: "red",    label: "Danger",  derivable: true },
    ]

    // Where the keyboard is. Hover moves it too, so there is one notion
    // of "the row Enter would apply" whichever way the card is being
    // driven.
    property int cursor: 0

    function isCurrent(entry) {
        return entry.wallpaper ? !Appearance.useCustom
                               : Appearance.useCustom && Appearance.matchesPalette(entry)
    }

    function currentIndex() {
        for (let i = 0; i < panel.entries.length; i++)
            if (panel.isCurrent(panel.entries[i])) return i
        // A hand-edited palette is current without matching any row, so
        // this is a real case and not a fallback: start at the top rather
        // than nowhere.
        return 0
    }

    function apply(entry) {
        if (entry.wallpaper) {
            Appearance.useCustom = false
            return
        }
        // Colours first, useCustom second. The other order paints one
        // frame of whatever palette was pinned last before this one lands
        // — invisible when switching between two named themes, a flash of
        // the old one when coming from the wallpaper.
        Appearance.applyPalette(entry)
        Appearance.useCustom = true
    }

    function moveCursor(delta) {
        panel.cursor = Math.max(0, Math.min(panel.entries.length - 1, panel.cursor + delta))
    }

    // A full-width strip under the bar, not the screen: the card hangs
    // from the top of it, and the height is the card's own plus the room
    // its shadow needs. exclusiveZone 0 reserves nothing and respects
    // what the bar reserves, which is what puts this strip's top edge
    // under the bar rather than behind it.
    anchors { top: true; left: true; right: true }
    implicitHeight: panel.inset + panel.cardHeight + panel.shadowPad

    exclusiveZone: 0
    mask: cardMask
    Region { id: cardMask; item: cardSlot }

    // The input region is taken from THIS, an empty item pinned where the
    // card comes to rest, and never from `card` itself, which carries the
    // slide-in Translate — network/NetworkPanel.qml has the full account
    // of what goes wrong when a mask item is being transformed.
    //
    // Centred on the screen. This tracked a Panels.themesAnchor fraction
    // until 2026-09-22, the way calendar/CalendarPanel.qml still centres
    // itself on the clock: the bar's themes module published where its
    // middle sat, because the two surfaces are separate layer-shell
    // windows and neither can see the other's geometry. That module is
    // gone (user request — the conf menu's Style section already opens
    // this card), so there is no longer a bar item to hang under, and
    // the openers that remain are menu/ConfMenu.qml, whose own slab is
    // horizontally centred, and the themes-toggle shortcut, which has no
    // position at all. Centring is what "under the thing that opened me"
    // now means for both.
    //
    // Still clamped, so a card wider than the screen is inset rather
    // than hanging off both edges.
    Item {
        id: cardSlot
        anchors.top: parent.top
        anchors.topMargin: panel.inset
        width: panel.cardWidth
        height: panel.cardHeight
        // Rounded: the card renders into a texture for its shadow
        // (layer.enabled below), so a half-pixel x from an odd width
        // difference is resampled rather than merely nudged — see the
        // calendar's grid metrics for where that was first paid for.
        x: Math.round(Math.max(panel.inset,
                               (panel.width - panel.cardWidth) / 2))

        // The card changes size when the editor opens, and again as a
        // derivable row's note wraps. Animated for the same reason the
        // slide is, and on the same easing the calendar's own height
        // changes use.
        Behavior on width {
            NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard }
        }
        Behavior on height {
            NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard }
        }
    }

    onSurfaceOpened: {
        // Always the menu. The editor is somewhere you go, not somewhere
        // you are left — the same call the calendar makes about its year
        // view.
        panel.editing = false
        // Every open starts on what is actually showing: Enter straight
        // away is then a no-op rather than a surprise, and the arrows walk
        // from where the desktop already is.
        panel.cursor = panel.currentIndex()
    }

    Rectangle {
        id: card

        anchors.fill: cardSlot

        radius: Theme.radius
        color: Appearance.surface
        border.width: Theme.hyprBorderWidth
        border.color: Appearance.border
        clip: true

        focus: true
        Keys.onPressed: (event) => {
            // Everything below Escape walks the menu, which is not on
            // screen while the editor is: those keys belong to whichever
            // hex field has the cursor.
            if (panel.editing && event.key !== Qt.Key_Escape) return

            switch (event.key) {
            case Qt.Key_Escape:
                // One layer at a time, like the calendar's year view:
                // Escape out of the editor leaves the card up.
                if (panel.editing) panel.editing = false
                else panel.close()
                break
            case Qt.Key_Up:
                panel.moveCursor(-1)
                break
            case Qt.Key_Down:
                panel.moveCursor(1)
                break
            case Qt.Key_Home:
                panel.cursor = 0
                break
            case Qt.Key_End:
                panel.cursor = panel.entries.length - 1
                break
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                panel.apply(panel.entries[panel.cursor])
                break
            case Qt.Key_E:
                // The Edit pill's key. Without it the editor is the one
                // part of this card the keyboard cannot reach, which is
                // the same thing that made the bar's clock a dead stop
                // for SUPER+B until it grew a tapped() — see
                // bar/Clock.qml. Gated exactly as the pill is: on the
                // Wallpaper row there is no palette to edit.
                if (Appearance.useCustom) panel.editing = true
                break
            default:
                return
            }
            event.accepted = true
        }

        opacity: panel.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: panel.shown ? panel.enterDuration : panel.exitDuration
                easing.type: panel.shown ? Theme.easingDecel : Easing.InCubic
            }
        }

        transform: Translate {
            y: panel.shown ? 0 : -panel.slideDistance
            Behavior on y {
                NumberAnimation {
                    duration: panel.shown ? panel.enterDuration : panel.exitDuration
                    easing.type: panel.shown ? Theme.easingDecel : Easing.InCubic
                }
            }
        }

        layer.enabled: true
        layer.effect: PopupShadow {}
        HyprFrame {
            frameWidth: card.border.width
            targetRadius: card.radius
        }

        ColumnLayout {
            id: body

            anchors.fill: parent
            anchors.margins: Theme.cardPadding
            spacing: Theme.space2

            // ── Header ───────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                SectionTitle { text: panel.editing ? "Palette" : "Themes" }

                // In and out of the editor. Disabled on the Wallpaper
                // row, where there is nothing to edit: those colours are
                // matugen's, and the eight fields would be writing a
                // palette that isn't the one on screen.
                PillButton {
                    text: panel.editing ? "Done" : "Edit"
                    enabled: panel.editing || Appearance.useCustom
                    onClicked: panel.editing = !panel.editing
                }
            }

            // ── The menu ─────────────────────────────────
            ColumnLayout {
                visible: !panel.editing
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: panel.entries

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index

                        readonly property bool current: panel.isCurrent(row.modelData)
                        readonly property bool active: row.index === panel.cursor

                        Layout.fillWidth: true
                        // The gap that says the first row is a different
                        // kind of thing from the eight under it — a line
                        // would say the same and cost the card a row of
                        // its own height to say it.
                        Layout.bottomMargin: row.index === 0 ? 6 : 0
                        implicitHeight: panel.rowHeight
                        radius: Theme.radius
                        color: row.current ? SlabStyle.tintSelected
                             : (row.active ? Appearance.hover : Appearance.clear(Appearance.hover))
                        // The current row is the accent-filled, borderless
                        // "selected" look every selected button in the shell
                        // shares (SlabStyle.tintSelected), so this and the
                        // installer's chips agree on what "showing now"
                        // looks like.
                        border.width: row.current ? 0 : 1
                        border.color: row.active ? Appearance.border : Appearance.clear(Appearance.border)

                        Behavior on color {
                            ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space2
                            anchors.rightMargin: Theme.space2
                            spacing: Theme.space2

                            // Ground and accent, the pair the settings
                            // tab's chips carry: enough to tell the
                            // palettes apart by eye, and enough to spot
                            // the light one before picking it. The
                            // Wallpaper row shows the wallpaper palette's two, which
                            // are the colours it would switch back to.
                            Rectangle {
                                implicitWidth: 12
                                implicitHeight: 12
                                radius: 2
                                color: row.modelData.wallpaper ? Appearance.wallpaperBase.bg : row.modelData.bg
                                border.color: Appearance.border
                                border.width: 1
                            }
                            Rectangle {
                                implicitWidth: 12
                                implicitHeight: 12
                                radius: 2
                                color: row.modelData.wallpaper ? Appearance.wallpaperBase.accent : row.modelData.accent
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: row.modelData.name
                                color: Appearance.fg
                                font.pixelSize: Theme.fontMedium
                                font.family: Theme.font
                                elide: Text.ElideRight
                            }

                            // Only the wallpaper row is named after where
                            // its colours come from rather than after
                            // itself, so only it needs the word.
                            Text {
                                visible: row.modelData.wallpaper === true
                                text: "matugen"
                                color: Appearance.fgDim
                                font.pixelSize: Theme.fontTiny
                                font.family: Theme.font
                            }
                        }

                        HoverHandler {
                            id: rowHover
                            onHoveredChanged: if (rowHover.hovered) panel.cursor = row.index
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.apply(row.modelData)
                        }
                    }
                }
            }

            // ── The editor ───────────────────────────────
            // The eight rows that make a palette that is none of the
            // nine above. Ported whole from systemsettings/
            // SettingsAppearanceTab.qml when the settings panel was
            // deleted; the only change is the shape, one column here
            // against that panel's two, because a card grows downward as
            // far as it likes and a fixed 520px-tall content box did not.
            ColumnLayout {
                visible: panel.editing
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: Theme.space2

                Text {
                    text: "Base"
                    color: Appearance.fgSoft
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.font
                }

                Repeater {
                    model: panel.baseColors
                    delegate: PaletteColorRow {
                        required property var modelData

                        label: modelData.label
                        derivable: modelData.derivable
                        resolved: Appearance[modelData.token]
                        // A derivable row stores "" while it is following
                        // its derivation; the three that are derived *from*
                        // always hold a real colour, which has to be spelled
                        // back out as hex for the field.
                        overrideHex: modelData.derivable
                            ? Appearance[modelData.key]
                            : Appearance.toHex(Appearance[modelData.key])

                        onEdited: (hex) => Appearance[modelData.key] = hex
                        onCleared: Appearance[modelData.key] = ""
                    }
                }

                Text {
                    text: "Status"
                    color: Appearance.fgSoft
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.font
                    Layout.topMargin: 2
                }

                Repeater {
                    model: panel.statusColors
                    delegate: PaletteColorRow {
                        required property var modelData

                        label: modelData.label
                        derivable: modelData.derivable
                        resolved: Appearance[modelData.token]
                        overrideHex: Appearance[modelData.key]

                        onEdited: (hex) => Appearance[modelData.key] = hex
                        onCleared: Appearance[modelData.key] = ""
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    text: "Surface and Border follow Background, and the status "
                        + "colors follow the wallpaper theme, until you set them — "
                        + "a theme sets all eight, \u201creset\u201d hands one back."
                    color: Appearance.fgFaint
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.font
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
