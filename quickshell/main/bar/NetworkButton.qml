import QtQuick
import "../services"

BarButton {
    id: root

    // No hover dropdown (user request 2026-09-21). It listed the signal,
    // interface, IP, throughput and the count of visible networks — every
    // one of which the rail a click away now shows, larger and without
    // having to keep the pointer still. bar/LauncherButton.qml is off for
    // the same reason: a module whose click opens a surface doesn't also
    // need a card that opens itself.
    dropdownEnabled: false

    icon: Network.icon

    // Left click opens the right-edge rail (network/NetworkPanel.qml),
    // and that is the whole module now: the right click went to a quick
    // settings tab that was deleted on 2026-09-21, by which time the
    // rail had taken over everything it held, DNS included.
    onTapped: Panels.toggle("network")
}
