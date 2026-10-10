import Quickshell.Widgets
import QtQuick

// The island's wallpaper gallery (AGENTS.md, Wallpaper gallery): the
// images in one row, all the same size, the chosen one in the middle and
// raised a little; the row is cut off at the island's edges. ← and →
// move, Enter sets the middle one, Escape closes.
// `reset()` starts it on the wallpaper showing now.
Item {
    id: gallery

    property var images: []
    property int index: 0
    signal picked(string path)
    signal cancelled()

    // Every image 16:9; the island sets the height and makes itself just
    // tall enough for the row with the middle one raised.
    property real tileH: 120
    readonly property real tileW: Math.round(tileH * 16 / 9)
    readonly property real gap: 16
    readonly property real lift: 16

    function reset(current) {
        const i = images.indexOf(current)
        index = i >= 0 ? i : 0
        forceActiveFocus()
    }

    function step(d) {
        if (images.length > 0)
            index = Math.max(0, Math.min(images.length - 1, index + d))
    }

    focus: true
    clip: true

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left) step(-1)
        else if (event.key === Qt.Key_Right) step(1)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (images.length > 0)
                picked(images[index])
        } else if (event.key === Qt.Key_Escape) cancelled()
        else return
        event.accepted = true
    }

    Repeater {
        model: gallery.images

        ClippingRectangle {
            id: tile
            required property string modelData
            required property int index
            readonly property int d: index - gallery.index
            readonly property bool chosen: d === 0

            readonly property real offset: d * (gallery.tileW + gallery.gap)

            width: gallery.tileW
            height: gallery.tileH
            x: gallery.width / 2 + offset - width / 2
            // The row sits at the bottom, the middle one raised to the top.
            y: chosen ? 0 : gallery.lift
            visible: Math.abs(offset) - width / 2 < gallery.width / 2
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.12)

            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Image {
                anchors.fill: parent
                source: "file://" + tile.modelData
                // Decoded small: a thumbnail, not the full image per tile.
                sourceSize.width: 480
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: gallery.images.length === 0
        text: "No images in ~/Pictures/Wallpapers"
        color: "white"
        opacity: 0.6
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
    }
}
