pragma Singleton
import Quickshell
import QtQuick

// The clipboard window in the dynamic island's look (2026-10-11): white
// bold text on black, round corners, no border, frame or shadow. Like the
// island (../../dynamic-island/AGENTS.md, Colours), it overrides
// STYLE.md §2 and uses no Appearance tokens, so it doesn't follow the
// bar's theme. Fills are the island's: white at 12% for a field or
// button (20% hovered, as its PillButton), solid white with black text
// for the selected row. Wipe turns solid red under the pointer (the
// user's call, 2026-10-11), the island's one colour besides black and
// white.
//
// Same properties as Main.qml; see there for what each one is.
Singleton {
    readonly property color scrim: "black"
    readonly property real scrimOpacity: 0.5

    readonly property int width: 940
    readonly property int height: 580
    // The island's player corner.
    readonly property real radius: 32
    readonly property color background: "black"
    readonly property color borderColor: "black"
    readonly property int borderWidth: 0
    readonly property bool frame: false
    readonly property bool shadow: false
    readonly property real openScale: 0.97
    readonly property int padding: 16
    readonly property int gap: 12
    readonly property int smallGap: 8

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontWeight: Font.Bold

    readonly property int fieldHeight: 40
    readonly property real fieldRadius: 20
    readonly property color field: Qt.rgba(1, 1, 1, 0.12)
    readonly property int fieldPadX: 16
    readonly property color searchIcon: Qt.rgba(1, 1, 1, 0.6)
    readonly property int searchIconSize: 13
    readonly property color searchText: "white"
    readonly property int searchSize: 13
    readonly property color placeholder: Qt.rgba(1, 1, 1, 0.5)
    readonly property color selection: Qt.rgba(1, 1, 1, 0.3)

    readonly property color wipe: Qt.rgba(1, 1, 1, 0.12)
    readonly property color wipeHover: "#ff453a"
    readonly property color wipeText: "white"
    readonly property color wipeTextHover: "white"
    readonly property int wipeBorderWidth: 0
    readonly property color wipeBorder: "black"
    readonly property color wipeBorderHover: "black"
    readonly property int wipePadX: 16

    readonly property color emptyText: Qt.rgba(1, 1, 1, 0.6)
    readonly property int emptySize: 13
    readonly property int rowHeight: 32
    readonly property int rowSpacing: 2
    readonly property real rowRadius: 16
    readonly property int rowPadLeft: 12
    readonly property int rowPadRight: 12
    readonly property color rowRest: Qt.rgba(1, 1, 1, 0)
    readonly property color rowHover: Qt.rgba(1, 1, 1, 0.12)
    readonly property color rowSelected: "white"
    readonly property color rowText: "white"
    readonly property color rowTextSelected: "black"
    readonly property int rowTextSize: 13

    readonly property color pane: Qt.rgba(1, 1, 1, 0.12)
    readonly property real paneRadius: 16
    readonly property int panePadding: 16
    readonly property color infoText: Qt.rgba(1, 1, 1, 0.6)
    readonly property int infoSize: 11
    readonly property color warnText: "white"
    readonly property int warnSize: 11
    readonly property color bodyText: "white"
    readonly property color bodyTextMuted: Qt.rgba(1, 1, 1, 0.6)
    readonly property int bodySize: 13
    readonly property string bodyFont: "JetBrainsMono Nerd Font"
    // The entry itself stays regular: it's somebody's text, not a label.
    readonly property int bodyWeight: Font.Normal

    // The island's own 160ms, decelerating.
    readonly property int animPanel: 160
    readonly property int easingFade: Easing.OutCubic
    readonly property int easingMove: Easing.OutCubic
    readonly property int animFast: 120
    readonly property int easingFast: Easing.InOutQuad
}
