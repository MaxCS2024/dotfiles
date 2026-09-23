import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"

// A numbered workspace indicator and the scratchpad toggle share this
// one component — same shape, different inputs.
//
// Was a permanently-visible filled/bordered chip whose fill color also
// changed size on hover/active — the only bar element that looked like
// that. Every other bar icon (BarButton.qml) is a bare glyph that's
// transparent until hovered, with HoverPill supplying that highlight.
// Rebuilt on the same HoverPill so this reads as one more minimal bar
// icon instead of a different, heavier design language living inside
// the same bar.
Item {
    id: root

    property bool active: false
    property bool occupied: false
    property string label: ""
    property bool labelBold: false
    property real labelSize: Theme.fontMedium
    property bool urgent: false
    // Forwarded from Workspaces.qml (which gets it from
    // BarModuleLoader) purely so the urgent pulse below can stop while
    // the bar is hidden.
    property var barWindow

    signal clicked()

    width: 22
    height: 22
    Layout.alignment: Qt.AlignVCenter

    readonly property bool hovered: hoverHandler.hovered

    // Same reasoning as WorkspacePill's old border pulse — a plain
    // looping value the color bindings below read, not a Behavior
    // (Behaviors animate toward a target on change, they don't loop on
    // their own). Linear, not eased, for an even blink rhythm.
    property real _urgentPulse: 0
    SequentialAnimation on _urgentPulse {
        // Also gated on the bar being on screen. Hiding the bar
        // (SUPER+ALT+SPACE) leaves this subtree mapped at opacity 0
        // rather than tearing it down — see bar/Bar.qml — so an
        // infinite loop left running would repaint a bar nobody can see
        // for as long as the workspace stays urgent. barWindow is unset
        // until Workspaces.qml forwards it, hence the null guard.
        running: root.urgent && (!root.barWindow || root.barWindow.shown)
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 500 }
        NumberAnimation { from: 1; to: 0; duration: 500 }
    }

    readonly property color _markColor: root.urgent
        ? Qt.rgba(Appearance.red.r, Appearance.red.g, Appearance.red.b, 0.5 + 0.5 * root._urgentPulse)
        : (root.active ? Appearance.bar
           : (root.occupied ? Appearance.fgStrong : Appearance.fgDim))

    readonly property color _accentTint: Qt.rgba(
        Appearance.surface.r * 0.6 + Appearance.accent.r * 0.4,
        Appearance.surface.g * 0.6 + Appearance.accent.g * 0.4,
        Appearance.surface.b * 0.6 + Appearance.accent.b * 0.4,
        1)

    // A resting background, not just HoverPill's on-hover one — bare
    // glyphs on the bare bar read as too flat/minimal for a cluster of
    // same-shaped items like these (unlike a single icon elsewhere on
    // the bar). Sits underneath HoverPill, so hovering still layers its
    // own highlight on top.
    Rectangle {
        anchors.centerIn: parent
        width: 22
        height: 22
        radius: height / 2
        // Accent-coloured: solid for the current workspace, a tint of
        // it for occupied ones, plain surface for empty ones.
        color: root.active ? Appearance.accent
             : (root.occupied ? root._accentTint : Appearance.surface)
        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
    }

    HoverPill {
        id: pill
        implicitWidth: 22
        implicitHeight: 22
        active: root.hovered
        anchors.centerIn: parent

        Text {
            id: numberText
            anchors.centerIn: parent
            visible: root.label !== ""
            text: root.label
            font.pixelSize: root.labelSize
            font.family: Theme.font
            font.bold: root.labelBold
            color: root._markColor
            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
        }

        // The scratchpad toggle has no number — a plain dot marks it
        // instead, same color logic as the number above.
        Rectangle {
            visible: root.label === ""
            anchors.centerIn: parent
            width: 6
            height: 6
            radius: 3
            color: root._markColor
            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
        }
    }

    HoverHandler { id: hoverHandler }
    MouseArea {
        anchors.fill: pill
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
