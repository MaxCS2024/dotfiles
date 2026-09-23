import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../config"
import "../common"
import "../services"
import "../theme"

PanelWindow {
    id: osd

    anchors { top: true; right: true }
    // Bound to the card's own size (rather than a fixed guess) plus the
    // 12px margin on each side — a surface exactly as wide as the card
    // would clip its left edge, since the card is inset from the right
    // by that same margin. Also covers the banner image sized off the
    // card width for a near-16:9 crop, which a fixed height would clip.
    implicitWidth: box.width + 24
    implicitHeight: box.height + 24
    color: "transparent"
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:osd-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0
    mask: Region {}

    property bool shown: false
    property string imagePath: ""
    property bool applyFailed: false
    property string message: ""

    function show() {
        osd.visible = true
        osd.shown = true
        displayTimer.restart()
    }

    Timer {
        id: displayTimer
        interval: 4000
        running: !cardHover.hovered
        onTriggered: osd.shown = false
    }

    Timer {
        id: hideTimer
        interval: Theme.animPanel
        onTriggered: if (!osd.shown) osd.visible = false
    }

    onShownChanged: if (!shown) hideTimer.restart()

    HoverHandler { id: cardHover }

    Connections {
        target: Panels
        function onWallpaperApplied(path, success, msg) {
            osd.imagePath = path
            osd.applyFailed = !success
            osd.message = msg
            osd.show()
        }
    }

    Rectangle {
        id: box
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: osd.shown ? 12 : 0
        anchors.topMargin: osd.shown ? 12 : -height

        width: 300
        implicitHeight: banner.height + footer.implicitHeight + 20
        radius: Theme.radius
        // Opaque, not panelGlass: only "quickshell:bar" gets compositor
        // blur (hypr/modules/windowrules.lua), so alpha here isn't frosted
        // glass, it's the desktop showing through the footer text. Matches
        // the notification cards this stacks with in the same corner.
        color: Appearance.surface
        border.color: Appearance.border
        border.width: 1
        opacity: osd.shown ? 1 : 0
        clip: true

        layer.enabled: true
        layer.effect: PopupShadow {}
        Behavior on anchors.topMargin {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingDecel }
        }
        Behavior on opacity { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard } }

        // Wallpapers are widescreen, so the small square crop used for
        // the screenshot thumbnail chopped off most of the image. A
        // full-width banner close to the source's own 16:9 aspect keeps
        // far more of it visible.
        Item {
            id: banner
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: osd.applyFailed ? 60 : (box.width * 9 / 16)

            Rectangle {
                anchors.fill: parent
                visible: !osd.applyFailed
                color: Appearance.surfaceAlt

                Image {
                    anchors.fill: parent
                    source: osd.imagePath !== "" ? ("file://" + osd.imagePath) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            Text {
                visible: osd.applyFailed
                anchors.centerIn: parent
                text: ""
                color: Appearance.red
                font.pixelSize: 26
                font.family: Theme.font
            }
        }

        ColumnLayout {
            id: footer
            anchors.top: banner.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 10
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: osd.applyFailed ? "Wallpaper Failed" : "Wallpaper Changed"
                    color: Appearance.fgStrong
                    font.bold: true
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }

                Text {
                    text: ""
                    color: Appearance.fgDim
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: osd.shown = false
                    }
                }
            }

            Text {
                text: osd.message
                color: Appearance.fgMuted
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }
}
