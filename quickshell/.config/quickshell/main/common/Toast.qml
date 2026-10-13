import QtQuick
import "../config"
import "../theme"

Rectangle {
    id: toast

    property string title: ""
    property string message: ""
    property bool isError: false
    property bool shown: false

    function show(t, m, err) {
        title = t
        message = m
        isError = err || false
        shown = true
        hideTimer.restart()
    }

    width: 260
    implicitHeight: col.implicitHeight + 20
    radius: Theme.radius
    color: Appearance.surface
    border.color: isError ? Appearance.red : Appearance.green
    border.width: 1

    layer.enabled: true
    layer.effect: PopupShadow {}
    opacity: shown ? 1 : 0
    y: shown ? 0 : -16
    visible: opacity > 0

    // 180ms is this widget's own distinct value, not one of Theme's
    // tokens — kept rather than forced onto the nearest token.
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Theme.easingStandard } }
    Behavior on y { NumberAnimation { duration: 180; easing.type: Theme.easingDecel } }

    Timer {
        id: hideTimer
        interval: 3000
        onTriggered: toast.shown = false
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.space2
        spacing: Theme.space1

        Row {
            spacing: Theme.space2
            Text {
                text: toast.isError ? "\uf057" : "\uf058"
                color: toast.isError ? Appearance.red : Appearance.green
                font.pixelSize: Theme.fontMedium
                font.family: Theme.font
            }
            Text {
                text: toast.title
                color: Appearance.fg
                font.bold: true
                font.pixelSize: Theme.fontNormal
                font.family: Theme.font
            }
        }

        Text {
            text: toast.message
            color: Appearance.fgMuted
            font.pixelSize: Theme.fontSmall
            font.family: Theme.font
            wrapMode: Text.WordWrap
            width: parent.width
            visible: text.length > 0
        }
    }
}
