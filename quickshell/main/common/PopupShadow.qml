import QtQuick
import QtQuick.Effects
import "../config"
import "../theme"

// The drop shadow every floating surface in this shell casts, as one
// component instead of the eighteen identical copies of the same six
// lines that used to sit in bar/DropdownPanel.qml, the five OSDs, both
// right-edge rails, the launcher, the Conf menu, the keybinds and
// installer windows, quick settings, the dashboard, the power menu, the
// wallpaper popup, the notification card and the screenshot toast.
//
// Used exactly where those copies were, on the surface's own backing
// Rectangle:
//
//     layer.enabled: true
//     layer.effect: PopupShadow {}
//
// `layer.effect` is a Component-typed property, so the declaration above
// is implicitly wrapped the way a delegate is — no `Component {}` around
// it, and no `source:` to wire up either, since the layer assigns its own
// texture to the effect's root.
//
// Two shadow weights live in config/Theme.qml (see its shadow tokens):
// "Popup" for surfaces that float free of any edge, "Docked" for the ones
// that sit against one. This is the Popup one, which is what every site
// listed above was already spelling out by hand. common/Plate.qml keeps
// its own inline MultiEffect rather than using this — it switches between
// both weights on its `floating` property, which is the whole reason that
// second set of tokens exists.
MultiEffect {
    shadowEnabled: true
    shadowColor: Appearance.shadow
    shadowBlur: Theme.shadowBlurPopup
    shadowVerticalOffset: Theme.shadowVerticalOffsetPopup
    shadowHorizontalOffset: 0
}
