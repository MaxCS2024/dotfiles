import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"

// The quick-settings 2-column tile: label +
// italic state line, gold border/tint when `on`. One component since all
// four tiles (Wi-Fi, Bluetooth, DND, Idle inhibit) share this exact shape
// and only differ in label/state/on-ness/click target.
Rectangle {
    id: root

    property string label: ""
    property string state: ""
    property bool on: false

    signal clicked()

    Layout.fillWidth: true
    Layout.preferredWidth: 1
    implicitHeight: column.implicitHeight + 20

    radius: Theme.radiusLarge
    border.width: 1
    border.color: root.on ? Appearance.accent : Appearance.border
    color: tap.pressed ? Appearance.hoverStrong
         : root.on ? Qt.rgba(Appearance.accent.r, Appearance.accent.g, Appearance.accent.b, 0.09)
                   : (hover.hovered ? Appearance.hover : Qt.rgba(Appearance.hover.r, Appearance.hover.g, Appearance.hover.b, 0))

    activeFocusOnTab: true
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.clicked()
            event.accepted = true
        }
    }

    FocusRing {
        active: root.activeFocus
        targetRadius: Theme.radiusLarge
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        spacing: 5

        Text {
            text: root.label
            // `fg`, not `fgStrong` — matches the pre-6.6 tab files' own
            // convention for plain row text.
            color: root.on ? Appearance.accent : Appearance.fg
            font.pixelSize: Theme.fontMedium
            font.family: Theme.fontHeading
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Text {
            text: root.state
            color: Appearance.fgMuted
            font.pixelSize: Theme.fontSmall
            font.italic: true
            font.family: Theme.font
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }

    HoverHandler { id: hover }
    TapHandler {
        id: tap
        onTapped: { root.forceActiveFocus(); root.clicked() }
    }
}
