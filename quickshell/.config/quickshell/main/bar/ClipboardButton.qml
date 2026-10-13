import Quickshell
import QtQuick

BarButton {
    id: root

    // No hover dropdown, like the network, volume and battery modules
    // (user request 2026-09-21): it listed eight previews and could show
    // nothing but the first line of each. A click opens the whole
    // history in fuzzel instead, searchable.
    dropdownEnabled: false

    // U+F0214 is nf-md-clipboard_text_outline.
    icon: "\u{F0214}"

    // The clipboard is cliphist in fuzzel (SUPER+C), not part of the shell.
    onTapped: Quickshell.execDetached(["sh", "-c", "cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"])
}
