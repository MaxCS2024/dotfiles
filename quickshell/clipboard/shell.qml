import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// The clipboard window on its own, so it opens with or without the bar
// (`qs -c clipboard`, started from hypr/modules/autostart.lua). It reads
// the bar's palette and corner radius but writes nothing of the bar's;
// see ../shared.
//
// Built at startup rather than on first use: it runs no cliphist process
// until it is opened, so waiting would save nothing.
Scope {
    ClipboardPanel { id: panel }

    // `qs -c clipboard ipc call clipboard open|close|toggle`. The bar's
    // clipboard button calls toggle.
    IpcHandler {
        target: "clipboard"
        function open(): void { panel.open(undefined) }
        function close(): void { panel.close() }
        function toggle(): void { panel.toggle() }
    }

    // SUPER+C (hypr/modules/binds/apps.lua). Moved here from the bar with
    // its name unchanged, so the bind still reads
    // quickshell:clipboard-toggle.
    GlobalShortcut {
        appid: "quickshell"
        name: "clipboard-toggle"
        description: "Toggle the clipboard window"
        onPressed: panel.toggle()
    }
}
