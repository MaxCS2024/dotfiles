import QtQuick
import "../services"

// The weather now and four hours from now, each temp after its sky:
// "󰖙 14° → 󰖐 16°" — today's only, so late in the evening the arrow and
// the second half go away. Nothing to show until the first forecast arrives
// (services/Weather.qml).
BarButton {
    id: root

    // No hover dropdown, matching bar/NetworkButton.qml,
    // bar/VolumeButton.qml and bar/BatteryButton.qml (user request
    // 2026-09-23): what it showed is on the rail a click away.
    dropdownEnabled: false

    readonly property bool hasContent: Weather.ready

    icon: Weather.now ? Weather.now.icon : ""
    label: {
        if (!Weather.now) return ""
        const now = Weather.now.temp + "°"
        return Weather.later ? now + " →" : now
    }
    trailingIcon: Weather.later ? Weather.later.icon : ""
    trailingLabel: Weather.later ? Weather.later.temp + "°" : ""

    // Left click opens the right-edge rail (weather/WeatherPanel.qml),
    // which also fetches again as it opens.
    onTapped: Panels.toggle("weather")
}
