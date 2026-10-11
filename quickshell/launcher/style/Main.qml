pragma Singleton
import Quickshell
import QtQuick
import "../config"
import "../theme"

// The launcher's look as it was before skins (2026-10-11): the bar's
// palette (../theme/Appearance.qml, read-only) and main's Theme, so it
// changes with the bar's theme and corner-radius setting.
//
// A skin is every visual value Launcher.qml uses and nothing else. To
// switch skins, point style/qmldir at another file; each one has the same
// properties.
Singleton {
    // The box.
    readonly property int width: 560
    readonly property int top: 120
    readonly property int padding: 12
    readonly property real radius: Theme.radius
    readonly property color background: Appearance.surface
    // 2px to match Hyprland's own `border_size`
    // (hypr/modules/decorations.lua); 1px made a ring half the weight of
    // the window edges either side of it. The colour is what shows if the
    // gradient frame is ever hidden; it covers this band otherwise.
    readonly property color borderColor: Appearance.border
    readonly property int borderWidth: Theme.hyprBorderWidth
    // The compositor's gradient window border (common/HyprFrame.qml).
    readonly property bool frame: true
    // common/PopupShadow.qml.
    readonly property bool shadow: true

    // Text.
    readonly property string font: Theme.font
    readonly property int fontWeight: Font.Normal

    // The search field.
    readonly property color searchText: Appearance.fg
    readonly property int searchSize: Theme.iconSize
    readonly property color placeholder: Appearance.placeholder

    readonly property color separator: Appearance.separator
    readonly property int emptyHeight: 48
    readonly property color emptyText: Appearance.fgMuted
    readonly property int emptySize: Theme.fontNormal

    // The result rows.
    readonly property int rowHeight: 40
    readonly property real rowRadius: Theme.radius
    readonly property int rowPadX: Theme.space2
    readonly property int gap: Theme.space2
    readonly property color rowRest: Appearance.clear(Appearance.selected)
    readonly property color rowSelected: Appearance.selected
    readonly property color rowText: Appearance.fg
    readonly property color rowTextSelected: Appearance.fg
    readonly property int rowTextSize: Theme.fontBig
    readonly property color rowDetail: Appearance.fgFaint
    readonly property color rowDetailSelected: Appearance.fgFaint
    readonly property int rowDetailSize: Theme.fontSmall
    readonly property int rowDetailWidth: 160
    readonly property int iconSize: 32
    // The letter tile for an app without an icon.
    readonly property color tile: Appearance.selected
    readonly property color tileSelected: Appearance.selected
    readonly property int tileRadius: Theme.radius

    readonly property color scrollTrack: Appearance.scrollTrack
    readonly property color scrollThumb: Appearance.scrollThumb
    readonly property int scrollWidth: 4
    readonly property real scrollRadius: Theme.radius

    // Motion. `panel` is the open/close fade and the box growing; `fast`
    // is the row highlight and the box's opacity.
    readonly property int animPanel: Theme.animPanel
    readonly property int easingPanel: Theme.easingDecel
    readonly property int animFast: Theme.animFast
    readonly property int easingFast: Theme.easingStandard
}
