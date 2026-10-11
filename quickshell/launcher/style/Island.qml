pragma Singleton
import Quickshell
import QtQuick

// The launcher in the dynamic island's look (2026-10-11): white bold text
// on black, fully round, no border, frame or shadow. Like the island
// (../../dynamic-island/AGENTS.md, Colours), it overrides STYLE.md §2 and
// uses no Appearance tokens, so it doesn't follow the bar's theme.
// Selected rows are the island's: solid white with black text, as in its
// ListRow and SidebarRow.
//
// Same properties as Main.qml; see there for what each one is.
Singleton {
    readonly property int width: 560
    readonly property int top: 120
    readonly property int padding: 12
    // Launcher.qml caps this at half the collapsed height, so the search
    // bar alone is a pill, and the corners stay that round as it grows.
    readonly property real radius: 32
    readonly property color background: "black"
    readonly property color borderColor: "black"
    readonly property int borderWidth: 0
    readonly property bool frame: false
    readonly property bool shadow: false

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontWeight: Font.Bold

    readonly property color searchText: "white"
    readonly property int searchSize: 16
    readonly property color placeholder: Qt.rgba(1, 1, 1, 0.5)

    readonly property color separator: Qt.rgba(1, 1, 1, 0.12)
    readonly property int emptyHeight: 48
    readonly property color emptyText: Qt.rgba(1, 1, 1, 0.6)
    readonly property int emptySize: 13

    readonly property int rowHeight: 40
    readonly property real rowRadius: 20
    readonly property int rowPadX: 12
    readonly property int gap: 8
    readonly property color rowRest: Qt.rgba(1, 1, 1, 0)
    readonly property color rowSelected: "white"
    readonly property color rowText: "white"
    readonly property color rowTextSelected: "black"
    readonly property int rowTextSize: 13
    readonly property color rowDetail: Qt.rgba(1, 1, 1, 0.6)
    readonly property color rowDetailSelected: Qt.rgba(0, 0, 0, 0.6)
    readonly property int rowDetailSize: 11
    readonly property int rowDetailWidth: 160
    readonly property int iconSize: 24
    readonly property color tile: Qt.rgba(1, 1, 1, 0.12)
    readonly property color tileSelected: Qt.rgba(0, 0, 0, 0.12)
    readonly property int tileRadius: 12

    readonly property color scrollTrack: Qt.rgba(1, 1, 1, 0.08)
    readonly property color scrollThumb: Qt.rgba(1, 1, 1, 0.3)
    readonly property int scrollWidth: 4
    readonly property real scrollRadius: 2

    // The island's own width animation: 160ms, decelerating.
    readonly property int animPanel: 160
    readonly property int easingPanel: Easing.OutCubic
    readonly property int animFast: 120
    readonly property int easingFast: Easing.InOutQuad
}
