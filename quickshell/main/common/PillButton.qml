import QtQuick
import "../config"
import "../theme"

// The small outlined pill that sits at the right-hand end of a section
// header and does whatever that section's one action is — "Refresh" in
// packages/PackagesList.qml, "Install" in packages/PackagesWindow.qml,
// "Edit" in theme/ThemesPanel.qml. The list read "clipboard, dashboard,
// system and packages panes, 'Rescan' in the network one" until
// 2026-09-21; three of those surfaces have been deleted since and the
// other two stopped using a pill, so it is call sites by filename now
// rather than a prose list to keep right. Five hand-copied Rectangles
// of the same twenty lines until 2026-09-20, which is exactly long
// enough for one of them to drift: systemsettings/
// SettingsSystemTab.qml had already grown the small-caps heading face
// the rest never got. That variant survives as
// `heading` below rather than being flattened away — it is the settings
// window's own type treatment (Theme.fontHeading), not an
// accident — but it is now one property instead of a divergent copy.
//
//     PillButton { text: "Refresh"; onClicked: root.refresh() }
//
// `enabled` is the plain Item property, so a false value stops the click
// *and* the hover tint. The network pane's "Scanning…" state is the only
// caller that sets it, and it used to gate its MouseArea alone — the pill
// went on lighting up under the cursor while refusing to be pressed.
// Taking the tint away with the click is the point of saying disabled.
Rectangle {
    id: root

    property alias text: label.text
    // Small-caps heading face instead of the body font. See above.
    property bool heading: false

    signal clicked()

    implicitWidth: label.implicitWidth + 16
    implicitHeight: 24
    radius: Theme.radius
    color: hover.hovered ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong)
    border.color: Appearance.border
    border.width: 1

    Text {
        id: label
        anchors.centerIn: parent
        color: Appearance.fgSoft
        font.pixelSize: Theme.fontSmall
        font.family: root.heading ? Theme.fontHeading : Theme.font
        font.capitalization: root.heading ? Font.SmallCaps : Font.MixedCase
        font.letterSpacing: root.heading ? Theme.tracking(Theme.fontSmall, 0.1) : 0
    }

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
