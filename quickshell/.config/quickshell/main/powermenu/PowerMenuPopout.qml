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
// now: a single row of five compact action tiles, each a glyph over a
// label, in the same monospace face as the rest of the shell. They sat on
// a slab until 2026-10-06, when the user had it removed; the tiles now
// stand straight on the dimmed backdrop.
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
// "classical plate" tokens, as the bento dashboard rebuilt in ff379e3
// did — same grounds, same corner scale, same staggered reveal. The
// tiles are fully opaque; only the backdrop is see-through.
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
    // Ignore, not the default Normal: Normal keeps this surface out of
    // the strip the bar reserves, so the dim would stop at the bar's edge
    // instead of covering it. Overlay sits above the bar's Top layer.
    exclusionMode: ExclusionMode.Ignore

    // The tiles fade out on their own duration; the window has to
    // outlive the slowest of them or the row blinks out from under its
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

    // Only `box` (the tile row) is click-through-masked, same as every
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
        // Deeper than the 0.55 the portrait cards sat on: the tile row is
        // a single smaller object now, and it needs the screen behind it
        // to recede further for it to read as the only thing in focus.
        opacity: panel.shown ? 0.62 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard } }
    }

    Item {
        id: box

        // Lock/Reboot/Power off keep the commands and icons of the power
        // UIs this replaced (PowerTab.qml, PowerOrbMenu.qml, both since
        // deleted); Log out is the row the 6.6 mockup added. This is the
        // shell's only power UI now. Suspend was removed per user request
        // 2026-10-08.
        readonly property var items: [
            { icon: "", label: "Lock",      cmd: "pidof hyprlock || hyprlock", danger: false },
            { icon: "", label: "Reboot",    cmd: "systemctl reboot",           danger: false },
            { icon: "", label: "Log out",   cmd: Theme.logoutCmd,              danger: false },
            { icon: "", label: "Power off", cmd: "systemctl poweroff",         danger: true  },
        ]

        readonly property var current: box.items[box.kbIndex]

        anchors.centerIn: parent
        implicitWidth: box.stripWidth
        implicitHeight: box.tileHeightSelected
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

        // ── Tiles ────────────────────────────────────────
        // One row of equal tiles straight on the dimmed backdrop, with no
        // slab behind them (user request 2026-10-06). The selected tile
        // grows tallest and its two neighbours a little, so the row
        // swells like a wave around the selection; every tile grows
        // evenly up and down and stays centred on the same line. This
        // replaced the 2026-10-02 sliding scale, where every tile shrank
        // with its distance from the selection. Each tile's own animated
        // value, wavePos, drives its height; the tiles aren't in a
        // layout, so the growth re-lays nothing out (STYLE.md §7).
        readonly property int tileWidth: 128
        // Height by distance from the selection: selected, neighbour,
        // everything further out.
        readonly property var waveHeights: [200, 176, 160]
        readonly property int tileHeightSelected: box.waveHeights[0]
        // Close-set (user request 2026-10-06): a sliver of backdrop
        // between tiles, enough to tell them apart and no more.
        readonly property int gap: Theme.space2

        property bool snapFocus: false

        // Each tile follows the selection on its own spring (tile.wavePos
        // below), and the tiles set off one after another, rippling out
        // from the newly selected tile by rippleStep per place. Until
        // 2026-10-06 one shared spring moved every tile on the same frame,
        // which the user found stiff and unnatural.
        readonly property int rippleStep: 40

        // Tiles used to darken with distance too, one ladder step per
        // tile away ("kind of a shadow effect", 2026-10-02); removed per
        // user request 2026-10-06, so every resting tile now shares one
        // fill and only the selection stands out.
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

        // How far tile i sits below the row's top edge: half of what it
        // has left to grow. The height runs linearly between the
        // waveHeights steps, so mid-slide the wave moves smoothly from
        // one tile to the next. Rounded so the top and bottom edges move
        // by whole pixels, the same amount each, and the tile's label
        // stays exactly on the row's centre.
        function insetAt(i, f) {
            const hs = box.waveHeights
            const x = Math.min(hs.length - 1, Math.abs(f - i))
            const k = Math.min(hs.length - 2, Math.floor(x))
            const h = hs[k] + (hs[k + 1] - hs[k]) * (x - k)
            return Math.round((box.tileHeightSelected - h) / 2)
        }
        readonly property int stripWidth: box.items.length * box.tileWidth + (box.items.length - 1) * box.gap

        // Hover selects the tile under the pointer only when the pointer
        // itself moved. A tile growing under a still cursor would
        // otherwise count as hovering it.
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

        // Not a Row: each tile places itself from its index and
        // box.insetAt(), straight on the backdrop.
        Repeater {
            model: box.items

            delegate: Rectangle {
                id: tile
                required property var modelData
                required property int index

                readonly property bool pressed: tileTap.pressed
                width: box.tileWidth
                x: tile.index * (box.tileWidth + box.gap)
                y: box.insetAt(tile.index, tile.wavePos)
                height: box.tileHeightSelected - 2 * tile.y

                // This tile's own copy of the selection, which its height
                // follows. It's handed the new kbIndex after a delay that
                // grows with the tile's distance from it, so the wave
                // ripples outward instead of every tile jumping at once.
                property real wavePos: 0
                Component.onCompleted: tile.wavePos = box.kbIndex
                // A spring, not a timed ease: a 120ms OutCubic slide here
                // looked stiff (user, 2026-10-02). The spring also keeps
                // its velocity when a second key press retargets it
                // mid-slide, where a NumberAnimation restarts from rest
                // and stutters.
                Behavior on wavePos {
                    enabled: !box.snapFocus
                    SpringAnimation { spring: 3.5; damping: 0.32; epsilon: 0.005 }
                }
                Timer {
                    id: rippleTimer
                    onTriggered: tile.wavePos = box.kbIndex
                }
                Connections {
                    target: box
                    function onKbIndexChanged() {
                        const d = Math.abs(box.kbIndex - tile.index)
                        if (box.snapFocus || d === 0) {
                            rippleTimer.stop()
                            tile.wavePos = box.kbIndex
                        } else {
                            rippleTimer.interval = d * box.rippleStep
                            rippleTimer.restart()
                        }
                    }
                }
                radius: SlabStyle.cardRadius

                // State is the fill, a step up the ladder per
                // state, and the glyph's colour below; nothing
                // else (STYLE.md §2, §8). This was an accent (or
                // red) wash mixed into the card, plus a
                // coloured rule along the top edge and a 3%
                // scale-up, until 2026-09-27.
                color: tile.pressed ? Appearance.hoverStrong
                     : box.mix(Appearance.surfaceAlt, Appearance.selected, tile.sel)
                border.width: 1
                border.color: SlabStyle.cardBorder

                // The selection highlight (user request
                // 2026-10-02): `selected` fill, accent glyph,
                // strongest label. It crossfades on its own
                // timer, the new tile fading in while the old
                // one fades out.
                property real sel: box.kbIndex === tile.index ? 1 : 0
                Behavior on sel { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard } }

                // ── Reveal ───────────────────────────
                // The tiles deal themselves onto the screen left
                // to right on open, borrowed from the
                // deleted DashboardCard. As there, the
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
                        // selection.
                        color: tile.modelData.danger ? Appearance.red
                             : box.mix(Appearance.fg, Appearance.accent, tile.sel)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontHuge
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: tile.modelData.label
                        color: box.mix(Appearance.fg, Appearance.fgStrong, tile.sel)
                        font.family: Theme.fontHeading
                        // Was Theme.fontSmall (11px), which
                        // was unreadable: the small caps this
                        // used to carry rendered the lowercase
                        // letters as capitals around 0.75em,
                        // so an 11px label was really an ~8px
                        // one. These are the only words left
                        // on the menu and they name what the
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
