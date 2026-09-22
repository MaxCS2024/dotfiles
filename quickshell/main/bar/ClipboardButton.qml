import QtQuick
import "../services"

BarButton {
    id: root

    // No hover dropdown, like the network, volume and battery modules
    // (user request 2026-09-21): it listed eight previews and could show
    // nothing but the first line of each. The window a click away lists
    // the whole history, searches it, and shows the selected entry in
    // full — see clipboard/ClipboardPanel.qml.
    dropdownEnabled: false

    // U+F0214 is nf-md-clipboard_text_outline.
    icon: "\u{F0214}"

    // Left click opens that window, and it is the only click this module
    // has: the right one went to the quick settings tab where Wipe lived
    // until that panel was deleted (2026-09-21). Wipe came across with
    // it, into the window's own header.
    onTapped: Panels.toggle("clipboard")
}
