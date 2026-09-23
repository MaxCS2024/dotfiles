import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"

// The shared shape of every right-side bar item: hover pill, optional
// icon + label, and a dropdown that children are declared into.
Item {
    id: root

    property var barWindow

    property string icon: ""
    property string label: ""
    property color iconColor: Appearance.icon
    property color labelColor: Appearance.icon
    property int maxLabelWidth: 0        // 0 = unconstrained
    property int minWidth: 280
    property bool dropdownEnabled: true

    // Set by bar/Bar.qml's roving keyboard focus, forwarded
    // through bar/BarModuleLoader.qml the same live-binding way barWindow
    // already is. Presence of this property is also how Bar.qml decides
    // which modules are keyboard-navigable at all (bar/Workspaces.qml and
    // bar/SystemTray.qml don't subclass BarButton — house style item 6 —
    // so they don't declare it, and are skipped rather than needing an
    // exceptions list anywhere).
    property bool keyboardFocused: false

    default property alias dropdownContent: dropdown.content

    readonly property bool dropdownVisible: dropdown.visible
    readonly property bool hovered: hover.hovered

    function closeDropdown() { dropdown.visible = false }

    signal tapped()
    signal rightTapped()
    signal scrolled(int delta)

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    HoverPill {
        id: pill
        // Was "+ 16" — HoverPill went fully round (radius: height/2),
        // and that rounding eats into a fixed 16px pad more than it did
        // at the old smaller radius, leaving the icon/label looking
        // cramped against the curve.
        implicitWidth: row.implicitWidth + 2 * Theme.barItemPadX
        // A fixed height, not the row's plus a margin: the icon's line
        // height (font metrics render a 16px glyph taller than 16px)
        // put every pill at a slightly different off-grid height.
        implicitHeight: Theme.barItemHeight
        active: hover.hovered || dropdown.visible || root.keyboardFocused
        anchors.centerIn: parent

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Theme.space1

            Text {
                text: root.icon
                visible: text !== ""
                font.pixelSize: Theme.iconSize
                font.family: Theme.font
                color: root.iconColor
                Behavior on color { ColorAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard } }
            }

            Text {
                text: root.label
                visible: text !== ""
                font.pixelSize: Theme.fontNormal
                font.family: Theme.font
                color: root.labelColor
                elide: Text.ElideRight
                Layout.maximumWidth: root.maxLabelWidth > 0
                    ? root.maxLabelWidth
                    : Number.POSITIVE_INFINITY
            }
        }
    }

    HoverHandler { id: hover }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.tapped()
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.rightTapped()
    }

    WheelHandler {
        onWheel: (event) => root.scrolled(event.angleDelta.y)
    }

    DropdownPanel {
        id: dropdown
        anchorItem: root
        barWindow: root.barWindow
        minWidth: root.minWidth
        anchorHovered: root.dropdownEnabled && (hover.hovered || root.keyboardFocused)
    }
}
