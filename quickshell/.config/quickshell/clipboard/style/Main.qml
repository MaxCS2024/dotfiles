pragma Singleton
import Quickshell
import QtQuick
import "../config"
import "../theme"

// The clipboard window's look as it was before skins (2026-10-11): the
// bar's palette (../theme/Appearance.qml, read-only) and main's Theme and
// ConfStyle, so it changes with the bar's theme and corner-radius setting.
//
// A skin is every visual value ClipboardPanel.qml uses and nothing else.
// To switch skins, point style/qmldir at another file; each one has the
// same properties.
Singleton {
    // The dim over the screen behind the window.
    readonly property color scrim: "black"
    readonly property real scrimOpacity: 0.5

    // The window. width and height are caps; a small screen gets less.
    readonly property int width: 940
    readonly property int height: 580
    readonly property real radius: Theme.radius
    readonly property color background: Appearance.surface
    readonly property color borderColor: Appearance.border
    readonly property int borderWidth: Theme.hyprBorderWidth
    // The compositor's gradient window border (common/HyprFrame.qml).
    readonly property bool frame: true
    // common/PopupShadow.qml.
    readonly property bool shadow: true
    // The window grows from this scale as it opens.
    readonly property real openScale: 0.97
    readonly property int padding: Theme.space4
    // Between the search row and the columns, and between the columns.
    readonly property int gap: Theme.space3
    // Inside rows: the field and Wipe, the field's glyph and text, the
    // pane's lines.
    readonly property int smallGap: Theme.space2

    readonly property string font: Theme.font
    readonly property int fontWeight: Font.Normal

    // The search field.
    readonly property int fieldHeight: 40
    readonly property real fieldRadius: Theme.radius
    readonly property color field: Appearance.surfaceAlt
    readonly property int fieldPadX: Theme.space3
    readonly property color searchIcon: Appearance.fgFaint
    readonly property int searchIconSize: ConfStyle.fontHint
    readonly property color searchText: Appearance.fg
    readonly property int searchSize: ConfStyle.fontRow
    readonly property color placeholder: Appearance.placeholder
    readonly property color selection: Appearance.selected

    // Wipe, beside the field. Danger tones only under the pointer.
    readonly property color wipe: Appearance.surfaceAlt
    readonly property color wipeHover: Appearance.dangerBg
    readonly property color wipeText: Appearance.fgSoft
    readonly property color wipeTextHover: Appearance.red
    readonly property int wipeBorderWidth: 1
    readonly property color wipeBorder: Appearance.clear(Appearance.dangerBorder)
    readonly property color wipeBorderHover: Appearance.dangerBorder
    readonly property int wipePadX: 10

    // The history list.
    readonly property color emptyText: Appearance.fgDim
    readonly property int emptySize: Theme.fontSmall
    readonly property int rowHeight: 32
    readonly property int rowSpacing: 2
    readonly property real rowRadius: Theme.radius
    readonly property int rowPadLeft: Theme.space3
    readonly property int rowPadRight: Theme.space2
    readonly property color rowRest: Appearance.clear(Appearance.hover)
    readonly property color rowHover: Appearance.hover
    readonly property color rowSelected: Appearance.selected
    readonly property color rowText: Appearance.fg
    readonly property color rowTextSelected: Appearance.fgStrong
    readonly property int rowTextSize: Theme.fontNormal

    // The preview pane.
    readonly property color pane: Appearance.surfaceAlt
    readonly property real paneRadius: Theme.radius
    readonly property int panePadding: Theme.space3
    readonly property color infoText: Appearance.fgMuted
    readonly property int infoSize: Theme.fontSmall
    // "shown to 200k" when an entry is cut short.
    readonly property color warnText: Appearance.orange
    readonly property int warnSize: Theme.fontTiny
    readonly property color bodyText: Appearance.fg
    // A binary entry's descriptor, in place of its body.
    readonly property color bodyTextMuted: Appearance.fgMuted
    readonly property int bodySize: Theme.fontNormal
    readonly property string bodyFont: Theme.fontMono
    readonly property int bodyWeight: Font.Normal

    // Motion. `panel` times the open/close: the scrim and window fade on
    // easingFade, the window's scale on easingMove. `fast` is Wipe's hover.
    readonly property int animPanel: Theme.animPanel
    readonly property int easingFade: Theme.easingStandard
    readonly property int easingMove: Theme.easingDecel
    readonly property int animFast: Theme.animFast
    readonly property int easingFast: Theme.easingStandard
}
