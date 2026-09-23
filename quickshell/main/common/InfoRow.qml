import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"

RowLayout {
    id: row

    property string label: ""
    property string value: ""
    // Overridable so a surface that also writes label/value rows by hand
    // can keep the two kinds on one tone — network/NetworkPanel.qml sets
    // both its InfoRows and its own DNS row to Appearance.fg, and a fixed
    // fgMuted here made the shared rows visibly dimmer than the hand-built
    // one sitting directly under them. Default unchanged, so every
    // existing call site looks exactly as it did.
    property color labelColor: Appearance.fgMuted
    property color valueColor: Appearance.fg
    property int valueMaxWidth: 0   // 0 = unconstrained

    Layout.fillWidth: true

    Text {
        text: row.label
        color: row.labelColor
        font.pixelSize: Theme.fontNormal
        font.family: Theme.font
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        elide: Text.ElideRight
    }

    Text {
        text: row.value
        color: row.valueColor
        font.pixelSize: Theme.fontNormal
        font.family: Theme.font
        elide: Text.ElideRight
        Layout.maximumWidth: row.valueMaxWidth > 0
            ? row.valueMaxWidth
            : Number.POSITIVE_INFINITY
    }
}
