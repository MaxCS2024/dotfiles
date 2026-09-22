import QtQuick
import QtQuick.Layouts
import "../config"

// A header control for the gallery: a glyph and a word in a pill.
//
// Its own file rather than a copy at each of the two call sites, and not
// the bordered glyph button the rails use in their headers: those sit on
// a card and take their tones from Appearance, while these sit on the
// gallery's dim, where the background is a fixed 92% black and the
// palette's foregrounds are the wrong reference (see the window's own
// header). Labelled, too — a rail header has room for a glyph and a
// tooltip, this one has a whole screen's width and nothing to gain from
// making you hover to find out what a button does.
Rectangle {
    id: root

    property string glyph: ""
    property string label: ""

    signal tapped()

    implicitWidth: row.implicitWidth + 24
    implicitHeight: 32
    radius: Theme.radius
    color: hover.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.18)
    // Dimmed rather than hidden when there is nothing for it to do: the
    // header should not reflow because a folder has one image in it.
    opacity: root.enabled ? 1 : 0.35

    Behavior on color {
        ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Text {
            text: root.glyph
            color: "#ffffff"
            font.pixelSize: Theme.fontNormal
            font.family: Theme.font
        }

        Text {
            text: root.label
            color: "#ffffff"
            font.pixelSize: Theme.fontSmall
            font.family: Theme.font
        }
    }

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.tapped()
    }
}
