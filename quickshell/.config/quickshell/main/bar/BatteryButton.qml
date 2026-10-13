import QtQuick
import "../theme"
import "../services"

BarButton {
    id: root

    // No hover dropdown, matching bar/NetworkButton.qml and
    // bar/VolumeButton.qml (user request 2026-09-21): it listed charge,
    // status, time, rate and health — the five readings the rail a click
    // away now shows, with the per-pack breakdown underneath that a card
    // that size never had room for.
    dropdownEnabled: false
    panelShown: Panels.batteryShown

    icon: Battery.icon
    iconColor: Battery.fillColor
    // Above 20%, the icon alone is enough — the exact number matters
    // most once battery is getting low.
    label: Battery.percentage < 20 ? Math.round(Battery.percentage) + "%" : ""

    // Left click opens the right-edge rail (battery/BatteryPanel.qml).
    // No right click: it opened a quick settings tab that was deleted on
    // 2026-09-21 and that the rail already said everything of. (The
    // volume module spends its right click on mute instead — there is no
    // equivalent here; the one thing to set, the power profile, is on
    // the rail.)
    onTapped: Panels.toggle("battery")
}
