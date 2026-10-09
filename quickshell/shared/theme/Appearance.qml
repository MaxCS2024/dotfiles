pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "../services"
import "palette.js" as Palette

// The bar's palette, read-only, for the configs that run beside it
// (../launcher, ../clipboard; symlinked into each). main/theme/
// Appearance.qml decides which palette is active and saves it; this reads
// the same two files (the themes menu's fall-appearance.json and
// matugen's colors.json) and derives the same tokens with the same
// palette.js, so these windows change with the bar. It never writes
// either file, and never sends `hyprctl reload` on a new wallpaper: the
// bar already does both.
//
// A preset's magenta and cyan are left to palette.js to derive from the
// accent; nothing outside the bar draws with them.
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

    // The same tokens as main/theme/Appearance.qml, under the same names.
    readonly property color sunken: root._t.sunken
    readonly property color bar: root._t.bar
    readonly property color surface: root._t.surface
    readonly property color surfaceAlt: root._t.surfaceAlt
    readonly property color hover: root._t.hover
    readonly property color hoverStrong: root._t.hoverStrong
    readonly property color selected: root._t.selected
    readonly property color trackBg: root._t.trackBg
    readonly property color scrollTrack: root._t.scrollTrack
    readonly property color scrollThumb: root._t.scrollThumb
    readonly property color barGlass: Qt.rgba(root.bar.r, root.bar.g, root.bar.b, Theme.alphaBar)

    readonly property color border: root._t.border
    readonly property color separator: root._t.separator

    readonly property color fgStrong: root._t.fgStrong
    readonly property color fg: root._t.fg
    readonly property color fgSoft: root._t.fgSoft
    readonly property color fgMuted: root._t.fgMuted
    readonly property color fgFaint: root._t.fgFaint
    readonly property color fgDim: root._t.fgDim
    readonly property color placeholder: root._t.placeholder
    readonly property color icon: root._t.icon
    readonly property color disabled: root._t.disabled

    readonly property color accent: root._t.accent
    readonly property color green: root._t.green
    readonly property color orange: root._t.orange
    readonly property color red: root._t.red

    readonly property color dangerBg: root._t.dangerBg
    readonly property color dangerBorder: root._t.dangerBorder

    readonly property color compositorStart: root._wallpaper && root._wallpaper.compositor
        ? root._wallpaper.compositor.start : Palette.COMPOSITOR_FALLBACK.start
    readonly property color compositorEnd: root._wallpaper && root._wallpaper.compositor
        ? root._wallpaper.compositor.end : Palette.COMPOSITOR_FALLBACK.end

    readonly property color shadow: "#99000000"

    FileView {
        path: Settings.mainDataDir + "/fall-appearance.json"
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
