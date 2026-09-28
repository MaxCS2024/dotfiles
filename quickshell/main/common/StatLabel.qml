import QtQuick
import "../config"
import "../theme"

// The label half of a stat grid cell: the network rail's Wi-Fi readings
// and the battery rail's, four columns of label/value/label/value.
// fgFaint, the tone of an unconnected network's wifi glyph (user request
// 2026-09-28), so the values beside it stand out — an exception to
// STYLE.md §3, asked for by name. Moved here from network/WifiTab.qml
// when the battery rail took the same grid.
Text {
    color: Appearance.fgFaint
    font.pixelSize: Theme.fontNormal
    font.family: Theme.font
    elide: Text.ElideRight
}
