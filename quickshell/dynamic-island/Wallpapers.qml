pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// The wallpaper gallery's side (AGENTS.md, Wallpaper gallery): the
// images in ~/Pictures/Wallpapers, the one showing now, and setting one
// with awww on every screen. Wallpaper only: no colours follow it (themes
// are out of scope). SUPER+ALT+W (hypr/modules/binds/apps.lua) presses
// the global shortcut below, which the focused screen's island answers.
Singleton {
    id: root

    readonly property string folder: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    // Absolute paths, by name.
    property var images: []
    // The image on the first screen awww reports, or "".
    property string current: ""

    signal toggleRequested()

    GlobalShortcut {
        appid: "quickshell"
        name: "island-wallpapers"
        description: "Open or close the dynamic island's wallpaper gallery"
        onPressed: root.toggleRequested()
    }

    // The folder's images, then "@@", then `awww query`'s answer.
    Process {
        id: query
        command: ["sh", "-c", 'find "$1" -maxdepth 1 -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \\) | sort; echo @@; awww query 2>/dev/null', "sh", root.folder]
        stdout: StdioCollector {
            onStreamFinished: {
                const [list, query] = text.split("@@\n")
                root.images = list.split("\n").filter(l => l !== "")
                const m = /currently displaying: image: (.+)$/m.exec(query || "")
                root.current = m ? m[1].trim() : ""
            }
        }
    }

    function refresh() {
        query.running = true
    }

    // On every output: awww img without -o.
    function apply(path) {
        if (!path)
            return
        Quickshell.execDetached(["awww", "img", path, "--transition-type", "wipe"])
        current = path
    }

    Component.onCompleted: refresh()
}
