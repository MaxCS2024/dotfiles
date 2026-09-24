import QtQuick
import "../services"

// Nothing earbuds, while they are connected: the earbuds glyph and the
// charge of whichever bud will run out first. A click opens the earbuds
// card under it (earbuds/EarbudsPanel.qml) with both buds and the case.
// Part of the `earbuds` feature; services/Earbuds.qml has where the
// numbers come from.
BarButton {
    id: root

    // No hover dropdown, like bar/BatteryButton.qml: the card is the
    // breakdown.
    dropdownEnabled: false

    readonly property bool hasContent: Earbuds.ready
    readonly property var bud: Earbuds.lowestBud

    icon: "󱡏"
    // Same colour rule as the laptop's own battery icon: green charging,
    // orange at 25%, red at 10%.
    iconColor: root.bud ? Battery.levelColor(root.bud.level, root.bud.charging) : Battery.levelColor(100, false)
    label: root.bud ? root.bud.level + "%" : ""

    onTapped: Panels.toggle("earbuds")

    // Where this module's middle sits across the bar, for the card to
    // centre on — bar/MediaPlayer.qml has why it is a fraction, and why
    // the geometry is named in `moved` although nothing reads it.
    readonly property real anchorFraction: {
        const bw = root.barWindow
        if (!bw || bw.width <= 0) return Panels.earbudsAnchor
        const moved = root.x + root.width + bw.width
        return root.mapToItem(bw.contentItem, root.width / 2, 0).x / bw.width
    }

    Binding {
        target: Panels
        property: "earbudsAnchor"
        value: root.anchorFraction
        when: root.barWindow !== null
    }
}
