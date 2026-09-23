import QtQuick
import "../config"
import "../theme"

Item {
    id: pill

    property bool active: false

    // Plain Item doesn't bind width/height to implicitWidth/Height on
    // its own — without this, `pill` (sized only via BarButton.qml
    // setting its implicitWidth/Height) actually stays 0x0, so `bg`
    // below (anchors.fill: parent) is invisible regardless of active/
    // scale/color. The icon+label RowLayout inside still renders fine
    // either way since children aren't clipped by a zero-size parent
    // here — which is exactly why this went unnoticed: everything
    // *looked* correct except the one thing (the highlight) that
    // needs real size to show. Found via the bar's keyboard focus
    // — the first non-mouse way to drive `active` true and check it,
    // since real hover has never been simulatable in this environment
    // (see 1.3/2.2's own notes on the same limitation).
    width: implicitWidth
    height: implicitHeight

    // Visual background only. The icon/label content BarButton.qml
    // declares inside `HoverPill { ... }` lands as a sibling of this
    // Rectangle (Item's default children go at the top level, not
    // inside a specific child) — that separation is what lets only
    // the highlight expand/retract while the icon and label stay at
    // fixed scale and fully visible the whole time.
    Rectangle {
        id: bg
        anchors.fill: parent
        // Fully round, not Theme.radius — a true pill shape, per its name.
        radius: height / 2
        // The hover colour at zero alpha, not "transparent": that is
        // transparent *black*, so the colour fade passed through a dark
        // half-alpha grey and an occupied workspace chip visibly dipped
        // darker than its own fill before the highlight arrived (and
        // again on the way out). Same RGB at both ends means only the
        // alpha moves.
        color: Appearance.clear(Appearance.selected)

        // transformOrigin defaults to Item.Center, so scaling from
        // 0 → 1 grows outward from the middle with no extra setup.
        scale: pill.active ? 1.0 : 0.0

        Behavior on scale {
            NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingDecel }
        }
        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

        states: State {
            when: pill.active
            PropertyChanges {
                target: bg
                // The anchor note for the bar following the theme again.
                // This was a flat translucent white for as long as
                // Bar.qml's background was a fixed literal decoupled from
                // the palette: a wallpaper-following highlight over a
                // fixed dark bar swung between barely-visible and blown
                // out depending on what matugen produced, so pinning the
                // highlight was the only way to guarantee a consistent
                // lift. Bar.qml now paints Appearance.bar, so highlight
                // and background derive from one palette again and hold
                // their spacing by construction rather than by luck —
                // Appearance.qml's _lift()/_recede() are luminance-aware,
                // so this reads correctly on a light palette (Catppuccin
                // Latte) as well as the dark ones. Every other piece of
                // on-bar content went back to its Appearance token at the
                // same time, for the same reason.
                color: Qt.rgba(Appearance.selected.r, Appearance.selected.g, Appearance.selected.b, Theme.alphaPanel)
            }
        }
    }
}
