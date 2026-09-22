import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"
import "../common"

// Windows-like: collapsed to a single trigger; a click reveals every
// registered tray icon sliding out to the trigger's own left — user
// request 2026-09-16. (First cut of this was a separate popout window
// that opened below the bar; replaced same day, at the user's own
// follow-up request, for a reveal that stays inline in the bar
// instead.)
//
// Lives entirely inside this one Item — no LazyLoader, no second
// window, nothing on services/Panels.qml. bar/Bar.qml's right-hand
// RowLayout is anchored by its *right* edge, and "tray" is its *first*
// (leftmost) child: growing this Item's own implicitWidth moves only
// this item's own left edge and the row's shared origin — every
// sibling that comes after it (network, volume, battery) keeps its
// exact on-screen position, because a RowLayout computes each child's
// offset from the *previous* children's cumulative width, and those
// don't change. Revealed icons sliding out "to the left" falls
// straight out of that; there is no positioning code of its own here.
Item {
    id: root

    property int iconSize: Theme.iconSize
    property var barWindow

    property bool expanded: false

    // Icon-to-icon spacing within the reveal, only — not the gap to the
    // toggle, which is its own property below. They used to be the same
    // number; split 2026-09-16 so widening one doesn't also widen the
    // other.
    readonly property int spacing: 4

    // The gap between the toggle and the icon nearest it, user request
    // 2026-09-16 ("a little more space") — was root.spacing (4px, the
    // same number icons use between each other), now double that so the
    // trigger reads as its own control rather than one more icon in the
    // row. Widening this can only ever add clearance for the hover
    // pill's own left-side overhang (see its comment below); it doesn't
    // reopen that fix.
    readonly property int toggleGap: 8

    // The gap between the toggle and the *next bar module* (network),
    // user request 2026-09-16 — the other side of the arrow from
    // toggleGap above. bar/Bar.qml's rightRow.spacing (3px) already
    // puts *some* space between every pair of right-side modules
    // uniformly; this adds to it for this one pair specifically,
    // without touching network-to-volume or volume-to-battery, which
    // widening that shared property would have. Matched to toggleGap's
    // own 8px rather than picked separately, so the arrow sits with
    // even breathing room on both sides instead of looking like it
    // drifted toward one neighbor.
    readonly property int trailingGap: 8

    // Same mechanism every other bar module already relies on to size
    // itself inside bar/Bar.qml's RowLayout (Clock, MediaPlayer, ...):
    // there's no Layout.preferredWidth override on this item itself,
    // so the RowLayout falls back to reading implicitWidth straight off
    // it. revealClip.width changes on every frame of its own Behavior
    // below, so this recomputes every frame too — that's the animation,
    // not a separate one bolted on afterward.
    //
    // This has to stay in lockstep, pixel for pixel, with whatever the
    // inner RowLayout actually renders below, or the arrow visibly
    // moves — verified the hard way. Went through two shapes before
    // this one:
    //   1. Both gaps folded into RowLayout.spacing (one shared number),
    //      with the toggleGap term here gated on revealClip.width > 0
    //      to only count it once something was revealed. That gating
    //      was wrong: RowLayout.spacing sits between revealClip and
    //      toggle *unconditionally*, 0-width child or not, so this
    //      formula disagreed with the real layout by one whole gap in
    //      exactly one of the two states. Small enough to hide at 4px;
    //      at 8px it was a visible ~4px jump in toggle's own screen
    //      x on every expand.
    //   2. Dropped the gate (unconditional root.toggleGap here, still
    //      relying on the row's own `spacing` to render it) — fixed the
    //      *first* discrepancy, but a *second* one showed up: with two
    //      children and no fillWidth on either, an inner RowLayout with
    //      slack (root wider than revealClip+spacing+toggle) doesn't
    //      reliably leave that slack purely after the last child the
    //      way its own docs suggest — measured toggle 4px further right
    //      than revealClip.width + toggleGap predicted, only while
    //      expanded, tracked down via toggle.x/.mapToItem in both
    //      states rather than guessed at.
    // Both were the same class of mistake: leaving *any* width
    // unaccounted for and trusting RowLayout to place it somewhere
    // predictable. This version leaves nothing to trust — spacing: 0
    // below, and both gaps are explicit Layout.rightMargin on the
    // children that own them, so implicitWidth and the actual rendered
    // width are the same sum, not two formulas that happen to agree.
    implicitWidth: revealClip.width + root.toggleGap
        + toggle.implicitWidth + root.trailingGap
    implicitHeight: root.iconSize

    // Deliberately NOT self-hiding when SystemTray.items is empty, unlike
    // MediaPlayer/ActiveWindow — tried that first and reverted it 2026-09-16
    // after two reports of "the icon disappeared" in a row. Quickshell's own
    // SystemTray service can start a stale, empty view of a bus that
    // already has an item on it (same issue as Mpris, see
    // [[quickshell-mpris-stale-players]]), self-healing on the next reload
    // — but a trigger whose *presence* depends on that count makes every
    // stale window read as a missing button with no obvious cause and no
    // visible way back. Real Windows doesn't hide its own overflow chevron
    // when nothing is hidden either, for the same reason: a control whose
    // existence you can't rely on isn't one you can find again. Always
    // showing it means "stale" is now something you can only notice by
    // clicking and finding nothing revealed, not by the whole button
    // vanishing.
    readonly property int trayCount: SystemTray.items.values.length

    // An empty reveal with nothing left in it and no way it got there is
    // just dead space in the bar — collapse it the moment the last icon
    // disappears, same reasoning a hover dropdown would apply by just
    // closing on its own.
    onTrayCountChanged: if (root.trayCount === 0) root.expanded = false

    // Tints the trigger when something behind it is asking for
    // attention, so a NeedsAttention item doesn't go unnoticed just for
    // being tucked away — the whole point of collapsing them was to get
    // them out from under foot, not to hide them.
    readonly property bool _hasUrgent: {
        for (const it of SystemTray.items.values)
            if (it.status === Status.NeedsAttention) return true
        return false
    }

    RowLayout {
        anchors.fill: parent
        // 0, not root.toggleGap — see implicitWidth's own comment above.
        // Both gaps are each child's own explicit Layout.rightMargin
        // instead, so there's no shared "spacing" value whose actual
        // rendered placement has to be trusted or reverse-engineered.
        spacing: 0

        // ── Revealed icons ───────────────────────────────────
        Item {
            id: revealClip
            clip: true
            Layout.preferredWidth: root.expanded ? revealRow.implicitWidth : 0
            Layout.preferredHeight: root.iconSize
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: root.toggleGap

            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard }
            }

            RowLayout {
                id: revealRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.spacing

                Repeater {
                    model: SystemTray.items

                    delegate: Item {
                        id: trayItem
                        required property var modelData

                        implicitWidth: root.iconSize
                        implicitHeight: root.iconSize

                        Image {
                            id: trayIcon
                            anchors.fill: parent
                            // modelData.icon is already a loadable URL — see
                            // this file's own git history, 2026-09-16, for
                            // the doubled image://icon/ prefix that used to
                            // make every tray icon a "not found" placeholder.
                            source: trayItem.modelData.icon
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
                                    trayIcon.source = Qt.binding(() => trayItem.modelData.icon)
                                }
                            }
                        }

                        MouseArea {
                            id: trayMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            hoverEnabled: true
                            // An icon under the clip is exactly as
                            // technically clickable as a fully-revealed
                            // one otherwise — gated on `expanded` so a
                            // click that lands mid-collapse (icon already
                            // invisible, the clip still finishing its
                            // Behavior) can't activate something the user
                            // can no longer see.
                            enabled: root.expanded

                            // Menu coordinates must be mapped into `root`,
                            // since that's the item passed as the menu's
                            // parent.
                            function showMenu(x, y) {
                                if (!trayItem.modelData.hasMenu) return
                                const p = trayItem.mapToItem(root, x, y)
                                trayItem.modelData.display(root, p.x, p.y)
                            }

                            onClicked: mouse => {
                                if (mouse.button === Qt.LeftButton) {
                                    if (trayItem.modelData.onlyMenu) trayMouse.showMenu(mouse.x, mouse.y)
                                    else trayItem.modelData.activate()
                                } else if (mouse.button === Qt.MiddleButton) {
                                    trayItem.modelData.secondaryActivate()
                                } else if (mouse.button === Qt.RightButton) {
                                    trayMouse.showMenu(mouse.x, mouse.y)
                                }
                            }

                            onWheel: wheel => trayItem.modelData.scroll(wheel.angleDelta.y, false)

                            Tooltip {
                                anchorItem: trayItem
                                barWindow: root.barWindow
                                anchorHovered: root.expanded && trayMouse.containsMouse
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

        // ── Trigger ──────────────────────────────────────────
        Item {
            id: toggle
            implicitWidth: root.iconSize
            implicitHeight: root.iconSize
            Layout.rightMargin: root.trailingGap

            HoverPill {
                id: pill
                // NOT matched to BarButton.qml's own "+22" padding — tried
                // that 2026-09-16 for visual parity with the sibling
                // buttons, and it was wrong for this one specifically.
                // BarButton's neighbors are every other item in the *outer*
                // row, all a uniform 3px apart with nothing else competing
                // for that space. This toggle has a second, closer neighbor
                // none of them do: the revealed icons, sharing root's own
                // inner RowLayout only root.toggleGap away (4px when this
                // was written, since widened to 8 — see that property's own
                // comment, which only ever gives this more room, not less).
                // +22 gave 11px of overhang *per side* — comfortably past
                // both gaps — and the left side of that overhang painted
                // straight over the right half of the first revealed icon
                // whenever the toggle was hovered and expanded at once,
                // which is most opens: the click that reveals icons
                // typically leaves the cursor sitting right where it
                // clicked. +4 keeps the overhang (2px/side) inside the
                // tighter of the two gaps (the outer row's own 3px) with a
                // pixel to spare, so the pill can never reach a neighbor on
                // either side, expanded or not.
                implicitWidth: parent.width + 4
                implicitHeight: parent.height + 2
                anchors.centerIn: parent
                active: toggleHover.hovered || root.expanded
            }

            Text {
                anchors.centerIn: parent
                // Codicons "cod-triangle_left"/"cod-triangle_right"
                // (U+EB6F/U+EB70), user request 2026-09-16 — was MDI
                // arrow-left. A plain \u escape is correct here (unlike
                // the MDI glyphs this bar mostly uses): these codepoints
                // are 4-hex-digit BMP ones in the Private Use Area, not
                // the 5-digit Supplementary PUA-A MDI's own icons live
                // in, so they don't hit the \u{...} trap
                // ClipboardButton.qml's own comment calls out. Points
                // right while expanded (toggle collapses it back).
                text: root.expanded ? "" : ""
                color: root._hasUrgent ? Appearance.orange : Appearance.icon
                font.pixelSize: Theme.iconSize
                font.family: Theme.font
            }

            HoverHandler { id: toggleHover }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: root.expanded = !root.expanded
            }
        }
    }
}
