import Quickshell
import Quickshell.Io
import QtQuick
import "appcolors.js" as Format

// Writes the app colours — the active palette as the files the terminals
// and GTK read their colours from — whenever the palette changes, in
// wallpaper mode and custom mode alike. Built once, in shell.qml. The
// formats and the ANSI slot mapping are appcolors.js's, tested by
// tests/appcolors; this file only writes them and tells the apps.
//
// The only writer, since 2026-09-24. matugen used to render the same
// files from its own templates in wallpaper mode while this shell
// rendered a second set for custom mode, which each terminal included
// after matugen's; GTK never followed custom mode at all. matugen now
// writes only ~/.cache/matugen/colors.json, which is a palette source
// (theme/WallpaperSource.qml) and what Hyprland's borders read
// (hypr/modules/colors.lua) — the compositor colours stay the
// wallpaper's even in custom mode.
//
//   ~/.cache/quickshell/foot-colors.ini    included by foot/foot.ini
//   ~/.cache/quickshell/kitty-colors.conf  included by kitty/kitty.conf
//   ~/.cache/quickshell/ghostty-colors     included by ghostty/config.ghostty
//   ~/.config/gtk-{3,4}.0/gtk-colors.css   imported by the gtk.css beside it
//
// GTK's has to sit beside gtk.css: GTK's CSS @import expands neither ~
// nor $HOME, so only a relative import works. It is written only into a
// GTK directory that already exists — creating one would put a real
// directory where `rack deploy` means to put a link — and it is
// gitignored, because a deployed one can be a link back into this repo.
//
// After a write, kitty (SIGUSR1) and ghostty (SIGUSR2) re-read their
// config, so open windows change with the shell. foot reads its config
// once at startup, so a change lands in the next foot opened. GTK apps
// pick up their colours as they open windows, and the portal's
// color-scheme is set to match the palette's lightness, so libadwaita
// loads the stylesheet the rest of the colours come from.
//
// Fixed paths rather than Quickshell.dataPath(): that resolves per shell
// id, and the apps' configs have no way to know which one is running.
// The flip side is that two quickshell configs both building this would
// write over each other.
Scope {
    id: root

    readonly property string _home: Quickshell.env("HOME")
    readonly property string _cache: root._home + "/.cache/quickshell"
    property bool _ready: false

    readonly property var _texts: {
        const t = Appearance.tokens
        return {
            foot: Format.foot(t),
            kitty: Format.kitty(t),
            ghostty: Format.ghostty(t),
            gtk: Format.gtk(t),
            scheme: Format.colorScheme(t)
        }
    }

    // Debounced: editing a hex field changes the palette on every
    // keystroke, and the saved palette arrives a moment after startup.
    on_TextsChanged: writeTimer.restart()

    Timer {
        id: writeTimer
        interval: 300
        onTriggered: {
            if (!root._ready) return
            const texts = root._texts
            footFile.setText(texts.foot)
            kittyFile.setText(texts.kitty)
            ghosttyFile.setText(texts.ghostty)
            if (gtk3File.path !== "") gtk3File.setText(texts.gtk)
            if (gtk4File.path !== "") gtk4File.setText(texts.gtk)
            tell.command = ["sh", "-c", root._tellScript, "sh", texts.scheme]
            tell.running = false
            tell.running = true
        }
    }

    // After the writes, not alongside them: a reload that lands before
    // the file does re-reads the old colours. pkill exits 1 with no kitty
    // or ghostty running, and gsettings may not be here at all; neither
    // says anything worth hearing. color-scheme is only set when it
    // differs, since every set wakes each GTK app listening for it.
    readonly property string _tellScript: [
        "pkill -USR1 -x kitty",
        "pkill -USR2 -x ghostty",
        'if command -v gsettings >/dev/null 2>&1; then',
        '  [ "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)" = "\'$1\'" ] ||',
        '    gsettings set org.gnome.desktop.interface color-scheme "$1" 2>/dev/null',
        'fi',
        "true"
    ].join("\n")

    Process { id: tell }

    // FileView writes atomically through a temp file beside the target,
    // which fails outright if the directory is missing — hence the mkdir
    // before the first write, and the check for which GTK directories are
    // there to write into.
    Process {
        running: true
        command: ["sh", "-c",
            'mkdir -p "$1"; for d in gtk-3.0 gtk-4.0; do [ -d "$2/$d" ] && echo "$d"; done; true',
            "sh", root._cache, root._home + "/.config"]
        stdout: StdioCollector {
            id: prepared
            onStreamFinished: {
                const gtk = prepared.text.split("\n")
                footFile.path = root._cache + "/foot-colors.ini"
                kittyFile.path = root._cache + "/kitty-colors.conf"
                ghosttyFile.path = root._cache + "/ghostty-colors"
                if (gtk.indexOf("gtk-3.0") !== -1)
                    gtk3File.path = root._home + "/.config/gtk-3.0/gtk-colors.css"
                if (gtk.indexOf("gtk-4.0") !== -1)
                    gtk4File.path = root._home + "/.config/gtk-4.0/gtk-colors.css"
                root._ready = true
                writeTimer.restart()
            }
        }
    }

    FileView { id: footFile; printErrors: false }
    FileView { id: kittyFile; printErrors: false }
    FileView { id: ghosttyFile; printErrors: false }
    FileView { id: gtk3File; printErrors: false }
    FileView { id: gtk4File; printErrors: false }
}
