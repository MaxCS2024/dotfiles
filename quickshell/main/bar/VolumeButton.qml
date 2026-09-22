import QtQuick
import "../theme"
import "../services"

BarButton {
    id: root

    // No hover dropdown (user request 2026-09-21), the same call
    // bar/NetworkButton.qml made in the same breath: it listed the level,
    // the output device and whether that device was Bluetooth, and the
    // rail a click away says all three on a card you can actually reach
    // into.
    dropdownEnabled: false

    icon: Volume.icon
    iconColor: Volume.muted ? Appearance.red : Appearance.icon
    labelColor: Volume.muted ? Appearance.red : Appearance.icon

    // Left click opens the right-edge rail (volume/VolumePanel.qml) — the
    // sliders, the output device and the per-app mixer on one card. The
    // quick settings tab it used to open is one row further away now, in
    // that card's footer, which is exactly the handoff bar/NetworkButton
    // .qml made when its own rail arrived.
    //
    // Right click stays on mute rather than following NetworkButton and
    // going to the tab: it is the one thing on this module worth a click
    // with no surface in between, the wheel beside it is already the other
    // half of that pair, and the rail's footer covers the tab.
    onTapped: Panels.toggle("volume")
    onRightTapped: Volume.toggleMute()

    property real _lastWheelTime: 0

    onScrolled: (delta) => {
        const now = Date.now()
        if (now - root._lastWheelTime < 40) return
        root._lastWheelTime = now

        const step = 0.02
        Volume.adjustBy(delta > 0 ? step : -step)
    }
}
