import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"

// The value half of a stat grid cell (see StatLabel.qml): right-aligned
// against the middle or the right edge, taking whatever width its
// column has left.
Text {
    color: Appearance.fg
    font.pixelSize: Theme.fontNormal
    font.family: Theme.font
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    Layout.fillWidth: true
    Layout.minimumWidth: 0
}
