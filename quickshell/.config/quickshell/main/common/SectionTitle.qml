import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"

// The bold heading that names a panel section — "Network", "Bluetooth",
// "Clipboard", "Notifications", the connected SSID on the network rail.
// Six byte-identical copies of the same eight lines until 2026-09-20,
// differing only in the string.
//
//     SectionTitle { text: "Clipboard" }
//
// The Layout attached properties come with it: every one of these sits
// as the first child of a header RowLayout with common/PillButton.qml (or
// another small control) on the right, so it takes the slack and elides
// rather than pushing that control off the edge. `Layout.minimumWidth: 0`
// is what lets it actually shrink — RowLayout otherwise floors a child at
// its implicit width, and an un-elided title would win the argument.
Text {
    color: Appearance.fgStrong
    font.bold: true
    font.pixelSize: Theme.fontLarge
    font.family: Theme.font
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    elide: Text.ElideRight
}
