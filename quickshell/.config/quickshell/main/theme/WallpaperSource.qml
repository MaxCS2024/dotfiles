import Quickshell
import Quickshell.Io
import QtQuick
import "palette.js" as Palette

// The wallpaper palette source, private to Appearance.qml.
//
// Reads ~/.cache/matugen/colors.json (written by matugen/config.toml's
// `[templates.quickshell]` template) and watches it, so running
// `matugen image <image>` re-themes the shell live. `base` stays null
// until the file has produced a usable palette; Appearance falls back
// to the Default preset meanwhile.
Scope {
    id: root

    // null until colors.json has been read and passed validation.
    property var base: null
    // Hyprland's window-border pair from the same file.
    property var compositor: null

    property bool _firstLoad: true

    Process {
        running: true
        command: ["sh", "-c", "printf '%s' \"$HOME/.cache/matugen/colors.json\""]
        stdout: StdioCollector {
            onStreamFinished: colorsFile.path = text
        }
    }

    FileView {
        id: colorsFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const w = Palette.fromMatugen(text())
            root.base = w ? w.base : null
            root.compositor = w ? w.compositor : null

            // Hyprland derives its border colours from this same file
            // (hypr/modules/colors.lua) but only reads it at config load,
            // so it needs a nudge. Skipped on the first load, which
            // happens on every shell start and would reload for nothing.
            // Sent even when the file didn't validate here: the Lua side
            // does its own read and has its own fallback.
            if (root._firstLoad)
                root._firstLoad = false
            else
                Quickshell.execDetached(["hyprctl", "reload"])
        }
    }
}
