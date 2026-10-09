import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// The app launcher on its own, so it opens with or without the bar
// (`qs -c launcher`, started from hypr/modules/autostart.lua). It reads
// the bar's palette and corner radius but writes nothing of the bar's;
// see theme/Appearance.qml.
//
// Built at startup rather than on first use: this process is the
// launcher and nothing else, so there is nothing to save by waiting.
Scope {
    Launcher { id: launcher }

    // `qs -c launcher ipc call launcher open|close|toggle`. The bar's
    // search button calls toggle.
    IpcHandler {
        target: "launcher"
        function open(): void { launcher.open() }
        function close(): void { launcher.close() }
        function toggle(): void { launcher.toggle() }    }

    // SUPER+P (hypr/modules/binds/apps.lua). Moved here from the bar with
    // its name unchanged, so the bind still reads
    // quickshell:launcher-toggle.
    GlobalShortcut {
        appid: "quickshell"
        name: "launcher-toggle"
        description: "Toggle the app launcher"
        onPressed: launcher.toggle()
    }
}
