import QtQuick
import "../config"
import "../theme"

// The one focus affordance every interactive element uses: a 2px #b68235
// ring at 2px offset, never the platform default. A single shared
// component so
// that rule can't drift per-site the way a hand-copied `border` block
// would; every consumer just anchors this to fill its own bounds and
// binds `active` to whatever "this is the current keyboard stop" means
// for it (a real `TextInput.activeFocus`, a `ListView` selection index,
// this app's own `keyboardFocused` bar-nav convention, ...).
//
// Drawn as a separate item *outside* the target's own border/background,
// not a `border.*` override on it — the ring sits 2px clear of the
// target's edge (the "2px offset" above), so it can't be confused with,
// or fought over with, the target's own resting-state border.
Item {
    id: root

    property bool active: false
    // Radius of the *target*, not the ring — the ring grows past it by
    // `Theme.focusRingOffset` on every side, same as the offset grows the
    // ring past the target's edges.
    property real targetRadius: 0
    // Overridable only for a target that is *itself* drawn in a color
    // other than Appearance.accent — powermenu's danger tile (red), and any
    // surface following theme/Appearance.qml's custom palette, whose
    // accent is a different hue from Theme's fixed brand one. Two accents
    // meeting on one control reads as a rendering fault, not as focus.
    // Everything else leaves this alone: the default *is* the rule, and
    // the point of this component is that it can't drift per site.
    property color ringColor: Appearance.accent

    anchors.fill: parent
    anchors.margins: -Theme.focusRingOffset
    visible: active
    z: 1000

    Rectangle {
        anchors.fill: parent
        radius: root.targetRadius + Theme.focusRingOffset
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: root.ringColor
    }
}
