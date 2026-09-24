import QtQuick
import "../services"

// Nothing earbuds, while they are connected: the earbuds glyph and the
// charge of whichever bud will run out first. The other bud and the case
// are in the battery rail a click away (battery/BatteryPanel.qml's Earbuds
// section). Part of the `earbuds` feature; services/Earbuds.qml has where
// the numbers come from.
BarButton {
    id: root

    // No hover dropdown, like bar/BatteryButton.qml: the rail is the
    // breakdown.
    dropdownEnabled: false

    readonly property bool hasContent: Earbuds.ready
    readonly property var bud: Earbuds.lowestBud

    icon: "󱡏"
    // Same colour rule as the laptop's own battery icon: green charging,
    // orange at 25%, red at 10%.
    iconColor: root.bud ? Battery.levelColor(root.bud.level, root.bud.charging) : Battery.levelColor(100, false)
    label: root.bud ? root.bud.level + "%" : ""

    onTapped: Panels.toggle("battery")
}
