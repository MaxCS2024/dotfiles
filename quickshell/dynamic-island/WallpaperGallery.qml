import Quickshell.Widgets
import QtQuick

// The island's wallpaper gallery (AGENTS.md, Wallpaper gallery): the
// images in a row, the chosen one in the middle, larger and raised a
// little, the others smaller and dimmed to either side, cut off at the
// edges. ← and → move, Enter sets the middle one, Escape closes.
// `reset()` starts it on the wallpaper showing now.
Item {
    id: gallery

    property var images: []
    property int index: 0
    signal picked(string path)
    signal cancelled()

    // The middle image: 16:9, 62% of the height; the others 70% of it.
    readonly property real bigH: Math.round(height * 0.62)
    readonly property real bigW: Math.round(bigH * 16 / 9)
    readonly property real smallH: Math.round(bigH * 0.7)
    readonly property real smallW: Math.round(bigW * 0.7)
    readonly property real gap: 16
    readonly property real lift: 10

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

            // Centre-to-centre: half the big one, a gap, half a small one
            // for the first step, then a small one and a gap for each more.
            readonly property real offset: d === 0 ? 0
                : Math.sign(d) * (gallery.bigW / 2 + gallery.gap + gallery.smallW / 2
                    + (Math.abs(d) - 1) * (gallery.smallW + gallery.gap))

            width: chosen ? gallery.bigW : gallery.smallW
            height: chosen ? gallery.bigH : gallery.smallH
            x: gallery.width / 2 + offset - width / 2
            y: (gallery.height - height) / 2 - (chosen ? gallery.lift : 0)
            visible: Math.abs(offset) - width / 2 < gallery.width / 2
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.12)
            opacity: chosen ? 1 : 0.5

            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160 } }

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
