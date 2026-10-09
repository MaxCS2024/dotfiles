import Quickshell
import QtQuick

BarButton {
    id: root

    dropdownEnabled: false

    icon: "󰍉"

    // The launcher is its own config (../launcher), so it is asked over
    // IPC like the dynamic island is. Nothing happens if it isn't running.
    onTapped: Quickshell.execDetached(["qs", "-c", "launcher", "ipc", "call", "launcher", "toggle"])
}
