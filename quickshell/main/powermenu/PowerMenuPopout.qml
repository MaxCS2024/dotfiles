import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../common"
import "../theme"
import "../services"

// The power popout, replacing `PowerOrbMenu.qml`'s
// full-screen overlay per the user's "retire the orb, one power menu"
// decision.
//
// Redesigned 2026-09-10 per user request ("more modern, more linux rice
// inspired"). What it was: five 240x380 portrait plates in a row on the
// classical paper/ink palette, each just a glyph over a word. What it is
// now: one slab carrying a single row of five compact action tiles, each
// a glyph over a small-caps label, in the same monospace face as the rest
// of the shell.
//
// It opened with a good deal more — a neofetch-style identity header
// (distro mark, user@host, kernel/uptime, clock, battery), a shell-prompt
// footer echoing the command each selection would run, and a keycap chip
// per tile advertising a wlogout-style letter hotkey — all removed per
// user request 2026-09-10, over five passes, in favour of just the part
// that acts. Nothing on screen documents the keyboard any more; what
// still works is arrows/Tab/j/k to move, Enter or Space to run, Escape to
// close, and that is the whole of it.
//
// It follows theme/ (Appearance + SlabStyle), not config/Theme.qml's
// "classical plate" tokens, so it matches the bento dashboard rebuilt in
// ff379e3 — same grounds, same corner scale, same staggered reveal. The
// slab is fully opaque (user request 2026-09-10, applied to both
// surfaces at once via SlabStyle's alphas); only the backdrop it lays
// over the screen is see-through.
//
// Kept from the version before it: the dimmed backdrop, the mask-to-`box`
// + focus-grab dismissal (3.2, now common/ShellSurface.qml's), the
// "powermenu" IPC target, the
// five commands, and the GlobalShortcut (still not LazyLoader-wrapped,
// for the same first-press reason PowerOrbMenu documented).
ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:powermenu"
    surfaceName: "powermenu"
    focusTarget: box

    anchors { top: true; bottom: true; left: true; right: true }

    // The tiles fade out on their own duration; the window has to
    // outlive the slowest of them or the slab blinks out from under its
    // own closing animation. dashboard/Dashboard.qml carried the same
    // arrangement until it was deleted on 2026-09-21.
    exitDuration: Math.max(Theme.animPanel, SlabStyle.revealDuration)

    // The one surface that must not open itself when it is built. This
    // window is not LazyLoader-wrapped, but the rule it records is the
    // one ShellSurface's openOnCompleted exists for: the request that
    // reaches a freshly built window may have been a *toggle*, and only
    // the Connections below knows which arrived. An unconditional open
    // here would double up and shut it again on the very first press.
    openOnCompleted: false

    // Reset the keyboard cursor on every open, not only in box's
    // onVisibleChanged — which this used to rely on alone, the one
    // window in this shell that did. An Item's visibleChanged doesn't
    // reliably fire just because the window around it became visible, so
    // on that path the tile row could end up never taking keyboard focus
    // at all, leaving the arrow keys, Enter and Escape silently dead.
    // ShellSurface focuses focusTarget for the same reason.
    onSurfaceOpened: box.reset()

    Process { id: execProc }
    function runCmd(cmd) {
        execProc.command = ["sh", "-c", cmd]
        execProc.running = false
        execProc.running = true
        panel.close()
    }

    // Only `box` (the slab) is click-through-masked, same as every
    // version of this file before it — a click on the dimmed backdrop
    // itself does nothing rather than closing the menu (an accidental
    // near-miss click shouldn't dismiss it); the focus grab that
    // common/ShellSurface.qml holds still closes it the moment focus
    // actually leaves this window some other way.
    mask: Region { item: box }


    Rectangle {
        id: dim
        anchors.fill: parent
        color: "black"
        // Deeper than the 0.55 the portrait cards sat on: the slab is a
        // single smaller object now, and it needs the screen behind it to
        // recede further for it to read as the only thing in focus.
        opacity: panel.shown ? 0.62 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard } }
    }

    Item {
        id: box

        // Lock/Reboot/Power off match the pre-existing commands
        // (PowerTab.qml/PowerOrbMenu.qml); Suspend and Log out are the
        // rows the 6.6 mockup added that neither predecessor had. Icon
        // codepoints match quicksettings/PowerTab.qml and
        // dashboard/DashboardHero.qml exactly, so all three power UIs in
        // this shell agree; the moon glyph (U+F186) is this file's own
        // addition for Suspend, which PowerTab.qml doesn't have.
        readonly property var items: [
            { icon: "", label: "Lock",      cmd: "pidof hyprlock || hyprlock", danger: false },
            { icon: "", label: "Suspend",   cmd: "systemctl suspend",          danger: false },
            { icon: "", label: "Reboot",    cmd: "systemctl reboot",           danger: false },
            { icon: "", label: "Log out",   cmd: Theme.logoutCmd,              danger: false },
            { icon: "", label: "Power off", cmd: "systemctl poweroff",         danger: true  },
        ]

        readonly property var current: box.items[box.kbIndex]

        anchors.centerIn: parent
        implicitWidth: slab.implicitWidth
        implicitHeight: slab.implicitHeight
        opacity: panel.shown ? 1 : 0
        scale: panel.shown ? 1 : 0.98

        Behavior on opacity { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard } }
        Behavior on scale { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingQuint } }

        // The current stop for arrow keys and Enter; hover moves it too,
        // so pointer and keyboard always agree on which tile is selected.
        property int kbIndex: 0

        function step(delta) {
            box.kbIndex = (box.kbIndex + delta + box.items.length) % box.items.length
        }

        // ── Sliding scale ────────────────────────────────
        // Portrait tiles (user request 2026-10-02): the selected one is
        // full size and every other shrinks by `falloff` per step away
        // from it, so the neighbours are nearly as big and the far ends
        // smallest. One animated value, focusPos, drives every tile's
        // scale and x together, so the whole row slides as one piece
        // instead of each tile re-laying out its neighbours (STYLE.md §7).
        readonly property int tileWidth: 128
        readonly property int tileHeight: 192
        readonly property real falloff: 0.12
        readonly property real minScale: 0.6

        property real focusPos: box.kbIndex
        property bool snapFocus: false
        // A spring, not a timed ease: a 120ms OutCubic slide here looked
        // stiff (user, 2026-10-02). The spring also keeps its velocity
        // when a second key press retargets it mid-slide, where a
        // NumberAnimation restarts from rest and stutters.
        Behavior on focusPos {
            enabled: !box.snapFocus
            SpringAnimation { spring: 3.5; damping: 0.32; epsilon: 0.005 }
        }

        // Tiles darken with distance too (user request 2026-10-02, "kind
        // of a shadow effect"): one ladder step per tile away, down to
        // bar, with the text dimming alongside. The slab underneath is
        // sunken, below every tile step, so no tile ever matches it and
        // shows as a bare outline. Driven by focusPos,
        // not kbIndex, so the shading slides in step with the sizes.
        function distance(i) {
            return Math.abs(box.focusPos - i)
        }
        // Colour at distance d along stops[0], stops[1], …, one per step.
        function ramp(stops, d) {
            const x = Math.max(0, Math.min(stops.length - 1, d))
            const k = Math.min(stops.length - 2, Math.floor(x))
            return box.mix(stops[k], stops[k + 1], x - k)
        }
        function mix(a, b, t) {
            return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                           a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
        }

        // Back to the first tile without sliding there from wherever the
        // menu was last closed.
        function reset() {
            box.snapFocus = true
            box.kbIndex = 0
            box.snapFocus = false
        }

        function scaleAt(i, f) {
            return Math.max(box.minScale, 1 - box.falloff * Math.abs(f - i))
        }
        function rowWidth(f) {
            let w = (box.items.length - 1) * Theme.space4
            for (let j = 0; j < box.items.length; j++) w += box.tileWidth * box.scaleAt(j, f)
            return w
        }
        // Centre of tile i, laying the scaled tiles edge to edge with an
        // even gap and centring the row in the strip.
        function tileCenter(i) {
            const f = box.focusPos
            let left = (box.stripWidth - box.rowWidth(f)) / 2
            for (let j = 0; j < i; j++) left += box.tileWidth * box.scaleAt(j, f) + Theme.space4
            return left + box.tileWidth * box.scaleAt(i, f) / 2
        }
        // Widest the row gets (selection in the middle), so the slab
        // keeps one width whichever tile is selected.
        readonly property real stripWidth: Math.max(...box.items.map((_, i) => box.rowWidth(i)))

        // Hover selects the tile under the pointer only when the pointer
        // itself moved. The tiles slide under a still cursor, and without
        // this the selection would chase them back and forth.
        property point lastPointer: Qt.point(-1, -1)
        function pointerAt(i, p) {
            if (p.x === box.lastPointer.x && p.y === box.lastPointer.y) return
            box.lastPointer = Qt.point(p.x, p.y)
            box.kbIndex = i
        }

        focus: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                panel.close()
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                box.step(1)
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                box.step(-1)
                event.accepted = true
                return
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                panel.runCmd(box.current.cmd)
                event.accepted = true
                return
            }
            // j/k step the selection, the way every list in a riced
            // setup does. Lowercased so a shifted or caps-locked letter
            // still lands.
            //
            // These two are the only letters this menu answers to now.
            // It used to take one per action (l/s/r/e/p, wlogout-style)
            // that ran it outright; removed per user request 2026-09-10
            // together with the keycap chips that advertised them. Every
            // other keystroke falls through and does nothing, which is
            // the point — no single letter fires an action any more.
            const typed = event.text.toLowerCase()
            if (typed === "j") { box.step(1); event.accepted = true; return }
            if (typed === "k") { box.step(-1); event.accepted = true; return }
        }
        onVisibleChanged: if (panel.shown) { box.reset(); box.forceActiveFocus() }

        // ── The slab ─────────────────────────────────────
        Rectangle {
            id: slab

            readonly property int pad: Theme.space6

            implicitWidth: content.implicitWidth + slab.pad * 2
            implicitHeight: content.implicitHeight + slab.pad * 2

            color: Appearance.sunken
            radius: SlabStyle.panelRadius
            border.width: 1
            border.color: SlabStyle.panelBorder

            layer.enabled: true
            layer.effect: PopupShadow {}
            ColumnLayout {
                id: content
                anchors.fill: parent
                anchors.margins: slab.pad
                spacing: Theme.space4

                // ── Actions ──────────────────────────────────────
                // The only thing left on the slab, per user request
                // 2026-09-10: the identity header above these tiles and
                // the shell-prompt footer below them are both gone, and
                // the two hairlines that divided them from this row went
                // with them — a rule needs something on each side of it.
                // The ColumnLayout stays for the padding math even at one
                // child (slab sizes itself off `content`).
                // Not a Row: each tile places itself from box.tileCenter().
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: box.stripWidth
                    implicitHeight: box.tileHeight

                    Repeater {
                        model: box.items

                        delegate: Rectangle {
                            id: tile
                            required property var modelData
                            required property int index

                            readonly property bool pressed: tileTap.pressed
                            width: box.tileWidth
                            height: box.tileHeight
                            x: box.tileCenter(tile.index) - box.tileWidth / 2
                            scale: box.scaleAt(tile.index, box.focusPos)
                            radius: SlabStyle.cardRadius

                            // State is the fill, a step up the ladder per
                            // state, and the glyph's colour below; nothing
                            // else (STYLE.md §2, §8). This was an accent (or
                            // red) wash mixed into the card, plus a
                            // coloured rule along the top edge and a 3%
                            // scale-up, until 2026-09-27.
                            // The fill follows the slide (box.ramp), so no
                            // Behavior here: one restarted every frame
                            // would lag behind it.
                            color: tile.pressed ? Appearance.hoverStrong
                                 : box.mix(box.ramp([Appearance.hover, Appearance.surfaceAlt, Appearance.surface, Appearance.bar], tile.dist),
                                           Appearance.selected, tile.sel)
                            border.width: 1
                            border.color: SlabStyle.cardBorder

                            readonly property real dist: box.distance(tile.index)

                            // The selection highlight (user request
                            // 2026-10-02): `selected` fill, accent glyph,
                            // strongest label. It crossfades on its own
                            // timer, the new tile fading in while the old
                            // one fades out, on top of the distance shading.
                            property real sel: box.kbIndex === tile.index ? 1 : 0
                            Behavior on sel { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard } }

                            // ── Reveal ───────────────────────────
                            // The tiles deal themselves onto the slab left
                            // to right on open, borrowed from
                            // DashboardCard so the two overlays in this
                            // shell open the same way. As there, the
                            // stagger is only taken on the way in: on
                            // close every tile has to be gone before the
                            // window hides — which is what exitDuration
                            // above is set for — and a staggered fade-out
                            // would leave the last ones snapping off
                            // mid-animation.
                            readonly property int revealDelay: tile.index * SlabStyle.revealStagger
                            property real _rise: panel.shown ? 0 : SlabStyle.revealRise

                            opacity: panel.shown ? 1 : 0
                            transform: Translate { y: tile._rise }

                            Behavior on opacity {
                                SequentialAnimation {
                                    PauseAnimation { duration: panel.shown ? tile.revealDelay : 0 }
                                    NumberAnimation { duration: SlabStyle.revealDuration; easing.type: Theme.easingStandard }
                                }
                            }
                            Behavior on _rise {
                                SequentialAnimation {
                                    PauseAnimation { duration: panel.shown ? tile.revealDelay : 0 }
                                    NumberAnimation { duration: SlabStyle.revealDuration; easing.type: Theme.easingQuint }
                                }
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: Theme.space3

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: tile.modelData.icon
                                    // The danger glyph stays red whether
                                    // or not it's the current stop — it's
                                    // labelling the action, not the
                                    // selection. It still recedes with the
                                    // rest of the tile, through opacity,
                                    // so it doesn't glow out of the shade.
                                    color: tile.modelData.danger ? Appearance.red
                                         : box.mix(box.ramp([Appearance.fg, Appearance.fgSoft, Appearance.fgMuted], tile.dist),
                                                   Appearance.accent, tile.sel)
                                    opacity: tile.modelData.danger ? 1 - 0.15 * Math.min(3, tile.dist) : 1
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontHuge
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: tile.modelData.label
                                    color: box.mix(box.ramp([Appearance.fg, Appearance.fg, Appearance.fgSoft, Appearance.fgMuted], tile.dist),
                                                   Appearance.fgStrong, tile.sel)
                                    font.family: Theme.fontHeading
                                    // Was Theme.fontSmall (11px), which
                                    // was unreadable: the small caps this
                                    // used to carry rendered the lowercase
                                    // letters as capitals around 0.75em,
                                    // so an 11px label was really an ~8px
                                    // one. These are the only words left
                                    // on the slab and they name what the
                                    // button does, so they get read at a
                                    // glance or they're not worth drawing.
                                    font.pixelSize: Theme.fontLarge
                                    // Plain sentence case, per user
                                    // request 2026-09-10 — the strings in
                                    // `items` are already written that way
                                    // ("Lock", "Log out"), so nothing here
                                    // transforms them. This is the one
                                    // label in the shell that departs from
                                    // common/Plate.qml's small-caps header
                                    // recipe, and deliberately: that recipe
                                    // is for section headings a few px
                                    // tall, not for the words on a button.
                                    // The tracking went with the caps —
                                    // 0.14em is a small-caps correction and
                                    // reads as a gap at normal case.

                                }
                            }

                            HoverHandler {
                                id: tileHover
                                cursorShape: Qt.PointingHandCursor
                                onPointChanged: if (hovered) box.pointerAt(tile.index, point.scenePosition)
                            }
                            TapHandler { id: tileTap; onTapped: panel.runCmd(tile.modelData.cmd) }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "powermenu"
        function toggle(): void { panel.toggle() }
        function open(): void { panel.open() }
        function close(): void { panel.close() }
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "powermenu-toggle"
        description: "Toggle the power menu"
        onPressed: panel.toggle()
    }
}
