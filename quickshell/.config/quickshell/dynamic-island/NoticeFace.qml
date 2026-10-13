import QtQuick

// One of the pill's notices: an icon at 16px, 8px before a bold 13px
// line made of `before`, `name` and `after` ("Connected – " + network,
// device + " connected – 80%"). A line too long for `maxWidth` has only
// its name cut with "…", so the words around it always show.
Row {
    id: face

    property string icon
    property string before
    property string name
    property string after
    property real maxWidth
    property bool shown

    anchors.centerIn: parent
    spacing: 8
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 160 } }

    TextMetrics {
        id: fixedMetrics
        font: line.font
        text: face.before + face.after
    }

    TextMetrics {
        id: nameMetrics
        font: line.font
        text: face.name
        elide: Text.ElideRight
        elideWidth: face.maxWidth - iconText.implicitWidth - face.spacing - fixedMetrics.advanceWidth
    }

    Text {
        id: iconText
        anchors.verticalCenter: parent.verticalCenter
        text: face.icon
        color: "white"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 16
    }

    Text {
        id: line
        anchors.verticalCenter: parent.verticalCenter
        text: face.before + nameMetrics.elidedText + face.after
        color: "white"
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
    }
}
