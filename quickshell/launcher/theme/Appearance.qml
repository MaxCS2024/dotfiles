pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "palette.js" as Palette

// The bar's palette, read-only. main/theme/Appearance.qml decides which
// palette is active and saves it; this reads the same two files (the
// themes menu's fall-appearance.json and matugen's colors.json) and
// derives the tokens with the same palette.js, so the launcher changes
// with the bar. It never writes either file, and never sends
// `hyprctl reload` on a new wallpaper: the bar already does both.
//
// A preset's magenta and cyan are left to palette.js to derive, since
// nothing here draws with them.
Singleton {
    id: root

    property var _saved: ({})
    property var _wallpaper: null

    readonly property bool _custom: root._saved.useCustom === true

    readonly property var base: root._custom
        ? Palette.fromCustom({
            // Appearance's own defaults, for a file that predates a field.
            bg: root._saved.customBg || "#3a3542", fg: root._saved.customFg || "#e6e2ee",
            accent: root._saved.customAccent || "#a99bd1",
            surface: root._saved.customSurface || "", border: root._saved.customBorder || "",
            green: root._saved.customGreen || "", orange: root._saved.customOrange || "",
            red: root._saved.customRed || "", magenta: "", cyan: ""
          })
        : (root._wallpaper ? root._wallpaper.base : Palette.DEFAULT)

    readonly property var _t: Palette.derive(root.base)

    function clear(c) { return Qt.rgba(c.r, c.g, c.b, 0) }

    readonly property color surface: root._t.surface
    readonly property color selected: root._t.selected
    readonly property color scrollTrack: root._t.scrollTrack
    readonly property color scrollThumb: root._t.scrollThumb
    readonly property color border: root._t.border
    readonly property color separator: root._t.separator
    readonly property color fg: root._t.fg
    readonly property color fgMuted: root._t.fgMuted
    readonly property color fgFaint: root._t.fgFaint
    readonly property color placeholder: root._t.placeholder

    readonly property color compositorStart: root._wallpaper && root._wallpaper.compositor
        ? root._wallpaper.compositor.start : Palette.COMPOSITOR_FALLBACK.start
    readonly property color compositorEnd: root._wallpaper && root._wallpaper.compositor
        ? root._wallpaper.compositor.end : Palette.COMPOSITOR_FALLBACK.end

    readonly property color shadow: "#99000000"

    FileView {
        path: Theme.mainDataDir + "/fall-appearance.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root._saved = JSON.parse(text()) || ({}) } catch (e) {}
        }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/matugen/colors.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._wallpaper = Palette.fromMatugen(text())
    }
}
