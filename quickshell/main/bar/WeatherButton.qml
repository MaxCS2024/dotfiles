import QtQuick
import "../services"

// The weather now and four hours from now: the current sky as the icon,
// then "14° → 16°" — today's only, so late in the evening the arrow goes
// away. Nothing to show until the first forecast arrives
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
        return Weather.later ? now + " → " + Weather.later.temp + "°" : now
    }

    // Left click opens the right-edge rail (weather/WeatherPanel.qml),
    // which also fetches again as it opens.
    onTapped: Panels.toggle("weather")
}
