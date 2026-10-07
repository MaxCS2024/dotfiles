import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"

// One island on the bar: a run of modules on its own patch of bar colour,
// floating over the screen with clear gaps either side. Bar.qml splits
// each row into islands (see islandGroups there); most modules get one to
// themselves.
Rectangle {
    id: root

    required property var names
    property var barWindow

    // For Bar.qml's keyboard-nav order: `count` is a real property, so a
    // binding that loops over loaderAt() still re-runs when it changes.
    readonly property alias count: repeater.count
    function loaderAt(i) { return repeater.itemAt(i) }

    // Hidden when every module in it is empty (no media player, no tray
    // icons), so no bare island is left behind. Reads the loaders'
    // `hasContent`, not their `visible`: hiding the island hides them,
    // and `visible` would then read false for good.
    visible: {
        for (let i = 0; i < repeater.count; i++) {
            const it = repeater.itemAt(i)
            if (it && it.hasContent) return true
        }
        return false
    }

    Layout.alignment: Qt.AlignVCenter
    implicitWidth: row.implicitWidth + Theme.space1 * 2
    implicitHeight: Theme.barItemHeight + Theme.space1 * 2
    radius: Theme.radius
    // The opaque token, as the single bar was: barGlass folds in
    // Settings.barOpacity, which is shared with other configs.
    color: Appearance.bar
    // A neutral structural edge, the same one the dropdown cards carry
    // (STYLE.md §1), so each island reads as its own piece against the
    // wallpaper.
    border.width: 1
    border.color: Appearance.border

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.space1

        Repeater {
            id: repeater
            model: root.names
            delegate: BarModuleLoader {
                id: moduleLoader
                required property string modelData
                name: modelData
                barWindow: root.barWindow
                keyboardFocused: !!root.barWindow && root.barWindow.kbActive
                    && root.barWindow.kbTargets[root.barWindow.kbIndex] === moduleLoader
            }
        }
    }
}
