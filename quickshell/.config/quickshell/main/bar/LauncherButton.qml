import Quickshell
import QtQuick

BarButton {
    id: root

    dropdownEnabled: false

    icon: "󰍉"

    // The launcher is fuzzel (SUPER+P), not part of the shell: a tap opens
    // it, or closes it when it is already open.
    onTapped: Quickshell.execDetached(["sh", "-c", "pkill -x fuzzel || fuzzel"])
}
