import Quickshell
import Quickshell.Wayland
import QtQuick

// The window every on-screen display sits in, and the timing that makes
// it an OSD rather than a panel: it shows itself, waits, and goes away
// again without anyone dismissing it.
//
// ── Why this exists ──────────────────────────────────────
// osd/OsdContent.qml already solved the duplication here once, and cut
// the seam in the wrong place. It owns the value-shaped body — an icon, a
// progress bar and a reading — *and* the lifecycle, so the three OSDs
// that show a 0-100 value are genuinely thin, and the two that show a
// boolean cannot use any of it. CapsLockOsd.qml and ZenOsd.qml were
// therefore a full copy of the lifecycle each, and all five copied the
// window chrome regardless.
//
// The lesson is that leverage stopped exactly where the body shape
// varied, which is the one place a seam should not be. The window and the
// timing are the same for all five; only what goes in the box differs.
// So the seam moves here, and OsdContent stays as the body it always
// described.
//
// ── The timing ───────────────────────────────────────────
// Two timers, not one. `displayTimer` is how long the OSD stands there;
// `hideTimer` is the exit animation finishing, after which the window can
// actually go away. Hiding on the first alone would cut the fade off; not
// hiding at all would leave a transparent full-width surface over the
// bottom of the screen for the rest of the session.
//
// The hide is guarded on `shown` for the same reason every dismissible
// surface in this shell guards it — see common/ShellSurface.qml, which
// holds the long version. An OSD re-shown inside its own fade (turn the
// volume knob twice quickly) would otherwise be taken away mid-rise.
PanelWindow {
    id: osd

    // The layershell namespace. Not `namespace`, which is future-reserved
    // in JavaScript — common/ShellSurface.qml's header has the detail.
    required property string surfaceNamespace

    // How long it stands there before starting to leave.
    property int displayDuration: 1500

    // Matches the box's exit animation (osd/OsdBox.qml), not
    // Theme.animPanel: the dismissal is deliberately quicker than the
    // entrance.
    property int exitDuration: 160

    property bool shown: false

    function show() {
        osd.visible = true
        osd.shown = true
        displayTimer.restart()
    }

    // A service reports its state the moment it comes up, and that first
    // report is not an event worth interrupting the screen for: the
    // volume did not change, the key was already down. Every OSD here
    // absorbed that first change with a `_seenFirst` flag of its own.
    //
    // Returns false for the very first change and true for every one
    // after, so a caller that has extra work to do on that first report —
    // VolumeOsd records the level it started at — can still do it.
    readonly property bool seenFirst: osd._seenFirst
    property bool _seenFirst: false

    function afterFirst(): bool {
        if (osd._seenFirst) return true
        osd._seenFirst = true
        return false
    }

    anchors { bottom: true; left: true; right: true }
    implicitHeight: 110
    color: "transparent"
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: osd.surfaceNamespace
    // None, not OnDemand: an OSD is never typed into and must never take
    // focus from what is.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0
    // Nothing here takes clicks. The window spans the bottom of the
    // screen and all of it stays click-through.
    mask: Region {}

    onShownChanged: if (!osd.shown) hideTimer.restart()

    Timer {
        id: displayTimer
        interval: osd.displayDuration
        onTriggered: osd.shown = false
    }

    Timer {
        id: hideTimer
        interval: osd.exitDuration
        onTriggered: if (!osd.shown) osd.visible = false
    }
}
