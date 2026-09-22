// The on-screen toast stack.
//
// Owns popup *lifetime*; NotificationCard owns how a popup looks. The split
// matters because the same card is also drawn by history rows, which have no
// lifetime at all.
import Quickshell
import Quickshell.Wayland
import QtQuick
import "../config"
import "../services"

PanelWindow {
    id: popupWin

    // 420 rather than the 320 this stack was built at (user request
    // 2026-09-18): a toast should grow sideways before it grows down. At
    // 320 an ordinary two-sentence body wrapped to three or four lines and
    // the card turned into a column; the extra 100px buys roughly a line
    // and a half back, so the same message lands shorter and the stack
    // holds more of them on screen at once.
    readonly property int cardWidth: 420
    readonly property int cardGap: 8
    // How far the stack is held off the screen edges. Drives the top and
    // right margins together; the top edge is measured from under the bar,
    // which reserves its own 35px, so this is the gap below the bar as much
    // as it is the gap in from the right.
    //
    // 8 by preference, pulled in from the 16 that 21a229a arrived at. That
    // 16 was measured rather than picked — it put a card's right edge on the
    // same pixel column as the bar's rightmost tray glyph, so the stack hung
    // directly under the icons it most often reports on. At 8 that alignment
    // is gone: the cards overhang the tray column by 8px and sit nearer both
    // edges. Still deliberately not flush, which is the one thing 64a1f8d
    // established and 21a229a kept — hard-edged geometry lying on the screen
    // boundary reads as having been pushed against it.
    readonly property int inset: 8
    // Room for the card shadow, on the two sides that face *away* from the
    // screen edges the stack is anchored to. The other two sides get
    // `inset`, which now doubles as the shadow's room there; padding
    // nothing at all would clip the shadow of the last card against the
    // bottom of the window.
    readonly property int shadowPad: 24

    readonly property int enterDuration: 280
    readonly property int exitDuration: 200
    readonly property int exitFadeDuration: 140

    anchors { top: true; right: true }
    // How far left the stack steps to stay clear of the network rail
    // (network/NetworkPanel.qml), which anchors to this same corner and
    // would otherwise be drawn straight over. Taken as-is, with no `inset`
    // added: rightRailWidth already reaches from the screen edge to the
    // rail's near side, and the column's own rightMargin below supplies
    // the gap — adding one here too spaced the two cards 16px apart,
    // twice what a card sits from the screen edge and twice `cardGap`.
    // 0 whenever the rail isn't showing, which is almost always.
    readonly property int railGap: Panels.rightRailWidth

    // Deliberately NOT `railGap` — that one animates, and binding the
    // surface width to it would run a compositor resize per frame for the
    // whole slide, which is the exact cost the fixed implicitHeight below
    // exists to avoid. This steps instead: up the instant the rail claims
    // space, and back down only once the column has finished sliding home,
    // so a toast is never clipped by a surface that narrowed out from
    // under it mid-animation.
    property int _railReserve: 0

    onRailGapChanged: {
        if (popupWin.railGap > popupWin._railReserve) {
            railShrink.stop()
            popupWin._railReserve = popupWin.railGap
        } else {
            railShrink.restart()
        }
    }

    Timer {
        id: railShrink
        interval: popupWin.enterDuration
        onTriggered: popupWin._railReserve = popupWin.railGap
    }

    implicitWidth: popupWin.cardWidth + popupWin.shadowPad + popupWin.inset
        + popupWin._railReserve
    // Fixed, NOT sized to the column. A layer-shell surface resize is a
    // compositor round trip, and this used to run one on every frame of a
    // card's collapse — the exit animation drives the column's height down
    // continuously, where the enter leaves it alone (a slot is full height
    // from its first frame and only opacity and translate move). Measured
    // with a per-frame probe: 16.2ms mean while the stack sat on screen,
    // 47.2ms mean through the collapse, alternating 16ms/100ms as each
    // resize stalled waiting on the compositor, which left the exit about
    // six frames to play with. Holding the window still costs a transparent
    // full-height surface and buys back the frame rate. The input region is
    // `mask` below, not the window bounds, so the extra area is not in
    // anyone's way, and `visible` still takes the whole thing away when the
    // stack is empty.
    implicitHeight: popupWin.screen ? popupWin.screen.height : 1080
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:osd-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0
    mask: Region { item: column }

    // Only actually present on screen while there's something to show — an
    // empty transparent layer-shell window still occupies space. Driven by
    // the local stack rather than Notifications.popups, so a card that has
    // just been dismissed gets to finish animating out.
    visible: stack.count > 0

    // ── Local mirror of Notifications.popups ─────────────
    // Notifications.popups is a plain JS array that gets REPLACED on every
    // change, and a Repeater bound straight to it therefore tears down and
    // rebuilds every delegate whenever any single row changes. That cost two
    // things: each card's countdown restarted from full whenever a new
    // notification arrived (a toast the user had nearly waited out got a
    // fresh lease because an unrelated one showed up), and a card could
    // never animate away, because the delegate was already destroyed by the
    // time the row left the array.
    //
    // This model is keyed by row id and edited in place: rows are appended,
    // updated with setProperty, and — critically — marked `closing` rather
    // than removed, so the delegate that owns the exit animation is still
    // alive to play it. dynamicRoles is what lets `payload` hold the row
    // object itself instead of a flattened copy.
    ListModel {
        id: stack
        dynamicRoles: true
    }

    // ListModel copies whatever it is handed — a JS object goes in as a
    // QVariantMap and comes back out as a different object — so the model's
    // own `payload` can never be compared by identity against the service's
    // row. These are the originals, kept purely so _sync can tell "same row"
    // from "row was rewritten": Notifications allocates a new object only for
    // a row whose content actually changed, which makes reference equality
    // exactly the right test, and a content-blind setProperty on every sync
    // would reset the very countdowns this model exists to preserve.
    property var _rowRefs: ({})

    function _indexOfRow(id) {
        for (var i = 0; i < stack.count; i++)
            if (stack.get(i).rowId === id) return i
        return -1
    }

    // Where a newly-seen row belongs: directly after its predecessor in the
    // service's array, not at the end. Restored rows are PREPENDED to
    // Notifications.popups, so appending blindly would show them below
    // notifications they arrived before.
    function _insertIndexFor(rowPos, rows) {
        if (rowPos === 0) return 0
        const prev = popupWin._indexOfRow(rows[rowPos - 1].id)
        return prev < 0 ? stack.count : prev + 1
    }

    function _sync() {
        const rows = Notifications.popups

        for (var i = 0; i < rows.length; i++) {
            const row = rows[i]
            const idx = popupWin._indexOfRow(row.id)
            if (idx < 0) {
                stack.insert(popupWin._insertIndexFor(i, rows),
                    { rowId: row.id, payload: row, closing: false })
                popupWin._rowRefs[row.id] = row
                continue
            }
            // An id that comes back while its card is still animating out —
            // a replaces_id reusing it, or a restore landing mid-exit —
            // cancels the exit rather than leaving a live row whose card is
            // on its way to being deleted.
            if (stack.get(idx).closing) stack.setProperty(idx, "closing", false)
            if (popupWin._rowRefs[row.id] !== row) {
                popupWin._rowRefs[row.id] = row
                stack.setProperty(idx, "payload", row)
            }
        }

        const live = {}
        for (var j = 0; j < rows.length; j++) live[rows[j].id] = true
        for (var k = 0; k < stack.count; k++) {
            const e = stack.get(k)
            if (!live[e.rowId] && !e.closing) stack.setProperty(k, "closing", true)
        }
    }

    // Called by a delegate once its exit animation has finished.
    function _drop(id) {
        const idx = popupWin._indexOfRow(id)
        if (idx >= 0) stack.remove(idx)
        delete popupWin._rowRefs[id]
    }

    Connections {
        target: Notifications
        function onPopupsChanged() { popupWin._sync() }
    }

    Component.onCompleted: popupWin._sync()

    Column {
        id: column
        anchors.top: parent.top
        anchors.topMargin: popupWin.inset
        anchors.right: parent.right
        anchors.rightMargin: popupWin.inset + popupWin.railGap
        // The stack slides sideways to make room rather than jumping, on
        // the same curve a card arrives on.
        Behavior on anchors.rightMargin {
            NumberAnimation {
                duration: popupWin.enterDuration
                easing.type: Theme.easingDecel
            }
        }
        width: popupWin.cardWidth
        // Zero, because the gap between cards belongs to the slots
        // themselves — a collapsing card has to take its share of the gap
        // with it, or dismissing one leaves an 8px hole in the stack until
        // the model row is finally removed.
        spacing: 0

        Repeater {
            model: stack

            // The delegate is a lifetime slot: it owns the countdown and the
            // enter/exit animation, and hands the card a plain progress
            // number. The card itself stays free of any notion of time.
            delegate: Item {
                id: slot

                required property int rowId
                required property var payload
                required property bool closing

                width: column.width

                // Collapse is what the exit animates; the natural height
                // passes through untouched. Animating `height` directly
                // would also animate an ordinary content change (a body
                // rewritten by replaces_id) and, worse, would race the
                // closing flag on the way out.
                property real collapse: slot.closing ? 0 : 1
                height: (card.implicitHeight + popupWin.cardGap) * slot.collapse
                clip: slot.collapse < 1

                Behavior on collapse {
                    NumberAnimation {
                        duration: popupWin.exitDuration
                        easing.type: Easing.InCubic
                    }
                }

                // Set after construction, never in the binding: a Behavior
                // does not animate a property's initial value, so the card
                // has to be told to move once it already exists.
                property bool entered: false
                Component.onCompleted: slot.entered = true

                readonly property bool _settled: slot.entered && !slot.closing

                opacity: slot._settled ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: slot.closing ? popupWin.exitFadeDuration : popupWin.enterDuration
                        easing.type: slot.closing ? Easing.InCubic : Theme.easingDecel
                    }
                }

                // Translate rather than `x`, so the slide never argues with
                // the Column about where the item belongs. Cards arrive from
                // and leave toward the screen edge they are anchored to;
                // anything past the window edge is simply not drawn, which
                // is what makes it read as sliding off-screen.
                transform: Translate {
                    x: slot._settled ? 0 : (slot.closing ? 64 : 32)
                    Behavior on x {
                        NumberAnimation {
                            duration: slot.closing ? popupWin.exitDuration : popupWin.enterDuration
                            easing.type: slot.closing ? Easing.InCubic : Theme.easingDecel
                        }
                    }
                }

                Timer {
                    interval: popupWin.exitDuration
                    running: slot.closing
                    onTriggered: popupWin._drop(slot.rowId)
                }

                readonly property int lifetime: Notifications.durationFor(
                    slot.payload.urgency, slot.payload.expireTimeout)

                // 0 means "stays until dismissed" — critical alerts, and any
                // sender that asked for expire_timeout=0.
                readonly property bool counting: slot.lifetime > 0 && !card.hovered && !slot.closing
                property real remaining: 1.0

                // A replaces_id update is a new message in an old slot, so it
                // earns a full duration. Neighbours are untouched now that
                // they are no longer rebuilt alongside it.
                onPayloadChanged: slot.remaining = 1.0

                // Decrementing a remaining fraction, rather than restarting a
                // one-shot Timer, is what makes hover a genuine pause: an
                // interval-based timer would hand back the FULL duration
                // every time the pointer left the card, so a toast the user
                // brushed past would outlive one they never touched.
                Timer {
                    interval: 50
                    repeat: true
                    running: slot.counting
                    onTriggered: {
                        if (slot.lifetime <= 0) return
                        slot.remaining -= 50.0 / slot.lifetime
                        if (slot.remaining <= 0) {
                            slot.remaining = 0
                            Notifications.dismiss(slot.payload)
                        }
                    }
                }

                NotificationCard {
                    id: card
                    anchors.top: parent.top
                    width: parent.width
                    row: slot.payload
                    // Negative hides the bar: nothing is counting down on a
                    // card that never expires, or one being hovered.
                    progress: slot.counting ? slot.remaining : -1
                }
            }
        }
    }
}
