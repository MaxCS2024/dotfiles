import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../theme"

// One audio device list for the volume rail, output or input: a row per
// device, the one in use on the `selected` fill, and a click makes that
// device the default. The rail has one for sinks and one for sources;
// they were the same sixty lines apart from the list and the setter.
//
// Height is the content's, capped at four rows — past that the list
// scrolls, hence the bar beside it. Same arrangement as the network
// rail's known-networks block, including the explicit
// `Layout.fillHeight: false`: it defaults to true for an item that is
// itself a layout, and a filling row inside a card that sizes to its
// content is a card with no height of its own.
//
// Hidden with one device or none: a picker offering the device you are
// already on is a row of chrome.
RowLayout {
    id: root

    // PwNodes, already filtered down to devices (no streams).
    property var devices: []
    // The node in use: Volume.sink or Mic.source.
    property var current: null
    signal picked(var node)

    readonly property int rowHeight: 32

    visible: root.devices.length > 1
    Layout.fillWidth: true
    Layout.fillHeight: false
    Layout.preferredHeight: Math.min(root.devices.length, 4) * root.rowHeight
    Layout.maximumHeight: Layout.preferredHeight
    spacing: Theme.space1

    ListView {
        id: list

        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.devices
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
            id: row
            required property var modelData

            readonly property bool isCurrent: row.modelData === root.current

            width: ListView.view.width
            height: root.rowHeight
            radius: Theme.radius
            color: row.isCurrent ? Appearance.selected
                 : (rowHover.hovered ? Appearance.hover : Appearance.clear(Appearance.hover))

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space2
                anchors.rightMargin: Theme.space2
                spacing: Theme.space2

                // A fixed column, so the names beside it start on the
                // same x whichever glyph the row has.
                Text {
                    text: (row.modelData.name || "").startsWith("bluez_") ? "" : ""
                    color: Appearance.fgMuted
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    Layout.preferredWidth: Theme.space4
                }

                Text {
                    text: row.modelData.description || row.modelData.nickname || row.modelData.name || "Unknown"
                    color: Appearance.fg
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }
            }

            HoverHandler { id: rowHover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(row.modelData)
            }
        }
    }

    ListScrollBar {
        view: list
        Layout.fillHeight: true
        trackColor: Appearance.scrollTrack
        thumbColor: Appearance.scrollThumb
    }
}
