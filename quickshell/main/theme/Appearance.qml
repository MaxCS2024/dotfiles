pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "../services"
import "palette.js" as Palette

// The palette: every colour the shell draws with. See ../CONTEXT.md for
// the vocabulary (palette, base palette, palette source, ladder, token).
//
// One palette is active at a time. Its base palette comes from one of
// three palette sources:
//   - wallpaper mode (useCustom false): matugen's colours for the
//     current wallpaper, via WallpaperSource.qml, or the Default preset
//     until matugen has produced any;
//   - custom mode (useCustom true): a preset applied with applyPalette(),
//     or a hand-edited palette in the custom* fields.
// palette.js derives every token from that base palette, the same way
// for every source; that file and tests/palette are where the ladder
// maths lives.
//
// config/Theme.qml holds no colours. Sizes, fonts, motion and radii live
// there; colours live only here.
Singleton {
    id: root

    readonly property string _path: Quickshell.dataPath("fall-appearance.json")

    property bool useCustom: false

    // The three the custom palette is built out of — always an explicit
    // color, nothing to fall back to.
    property color customBg: "#3a3542"
    property color customFg: "#e6e2ee"
    property color customAccent: "#a99bd1"

    // Optional per-token overrides, edited from the themes menu
    // (ThemesPanel.qml). Empty string means "no override": surface and
    // border derive from customBg, and an unset status colour takes the
    // Default preset's. Strings rather than colors precisely so "unset"
    // is representable.
    property string customSurface: ""
    property string customBorder: ""
    property string customGreen: ""
    property string customOrange: ""
    property string customRed: ""

    // ── Named palettes ─────────────────────────────────────
    // Applying one pins all eight rows (see Palettes.qml for why).
    // Nothing records *which* preset is showing: matchesPalette() reads
    // it back off the colors themselves, so editing any row after
    // picking one drops the menu's highlight on its own, with no stored
    // name to go stale against the palette it claims to describe.
    function applyPalette(p) {
        root.customBg = p.bg
        root.customFg = p.fg
        root.customAccent = p.accent
        root.customSurface = p.surface
        root.customBorder = p.border
        root.customGreen = p.green
        root.customOrange = p.orange
        root.customRed = p.red
    }
    function matchesPalette(p) {
        return Qt.colorEqual(root.customBg, p.bg)
            && Qt.colorEqual(root.customFg, p.fg)
            && Qt.colorEqual(root.customAccent, p.accent)
            && root.customSurface.toLowerCase() === p.surface
            && root.customBorder.toLowerCase() === p.border
            && root.customGreen.toLowerCase() === p.green
            && root.customOrange.toLowerCase() === p.orange
            && root.customRed.toLowerCase() === p.red
    }

    // Shared with the themes menu's hex fields so the editor and the
    // file on disk spell a color the same way.
    function toHex(c) {
        const hex = v => Math.max(0, Math.min(255, Math.round(v * 255))).toString(16).padStart(2, "0")
        return "#" + hex(c.r) + hex(c.g) + hex(c.b)
    }

    // `c` at zero alpha — the resting colour for a hover fill that
    // animates. "transparent" is transparent *black*, so a ColorAnimation
    // out of it passes through a dark half-alpha tint before it reaches
    // the hover colour; fading from `c` itself changes only the alpha.
    function clear(c) { return Qt.rgba(c.r, c.g, c.b, 0) }

    // ── Persistence ────────────────────────────────────────
    // Colors are written as "#rrggbb", not handed to JSON.stringify raw:
    // reading a `color` property from JavaScript yields a QColor, which
    // stringifies to an {r,g,b,hsvHue,...} object that _apply's string
    // check then rejected on load — so a saved palette never came back.
    function _snapshot() {
        return {
            useCustom: root.useCustom,
            customBg: root.toHex(root.customBg),
            customFg: root.toHex(root.customFg),
            customAccent: root.toHex(root.customAccent),
            customSurface: root.customSurface,
            customBorder: root.customBorder,
            customGreen: root.customGreen,
            customOrange: root.customOrange,
            customRed: root.customRed
        }
    }
    // Takes either spelling, so palettes saved by the object-writing
    // version above are recovered rather than silently reset.
    function _readColor(v) {
        if (typeof v === "string" && v !== "") return v
        if (v && typeof v === "object" && typeof v.r === "number") return Qt.rgba(v.r, v.g, v.b, 1)
        return undefined
    }
    function _apply(o) {
        if (typeof o.useCustom === "boolean") root.useCustom = o.useCustom

        const bg = root._readColor(o.customBg)
        const fg = root._readColor(o.customFg)
        const accent = root._readColor(o.customAccent)
        if (bg !== undefined) root.customBg = bg
        if (fg !== undefined) root.customFg = fg
        if (accent !== undefined) root.customAccent = accent

        if (typeof o.customSurface === "string") root.customSurface = o.customSurface
        if (typeof o.customBorder === "string") root.customBorder = o.customBorder
        if (typeof o.customGreen === "string") root.customGreen = o.customGreen
        if (typeof o.customOrange === "string") root.customOrange = o.customOrange
        if (typeof o.customRed === "string") root.customRed = o.customRed
    }

    // The probe, the guarded first write, the corrupt-file fallback and
    // the debounce are services/JsonStore.qml's — see its header for the
    // two hazards they answer.
    JsonStore {
        id: appearanceStore
        path: root._path
        snapshot: () => root._snapshot()
        onRestored: (data) => {
            if (data && typeof data === "object") root._apply(data)
        }
    }

    function _save() { appearanceStore.save() }
    onUseCustomChanged: root._save()
    onCustomBgChanged: root._save()
    onCustomFgChanged: root._save()
    onCustomAccentChanged: root._save()
    onCustomSurfaceChanged: root._save()
    onCustomBorderChanged: root._save()
    onCustomGreenChanged: root._save()
    onCustomOrangeChanged: root._save()
    onCustomRedChanged: root._save()

    // ── The active palette ─────────────────────────────────
    WallpaperSource { id: wallpaper }

    readonly property bool active: root.useCustom

    // The wallpaper's base palette, whichever mode is active — the themes
    // menu previews it on its "Wallpaper" row.
    readonly property var wallpaperBase: wallpaper.base || Palette.DEFAULT

    readonly property var base: root.active
        ? Palette.fromCustom({
            bg: root.customBg, fg: root.customFg, accent: root.customAccent,
            surface: root.customSurface, border: root.customBorder,
            green: root.customGreen, orange: root.customOrange, red: root.customRed
          })
        : root.wallpaperBase

    readonly property var _t: Palette.derive(root.base)

    // ── Surfaces ─────────────────────────────────────────
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

    // ── Lines ────────────────────────────────────────────
    readonly property color border: root._t.border
    readonly property color separator: root._t.separator

    // ── Text ─────────────────────────────────────────────
    readonly property color fgStrong: root._t.fgStrong
    readonly property color fg: root._t.fg
    readonly property color fgSoft: root._t.fgSoft
    readonly property color fgMuted: root._t.fgMuted
    readonly property color fgFaint: root._t.fgFaint
    readonly property color fgDim: root._t.fgDim
    readonly property color placeholder: root._t.placeholder
    readonly property color icon: root._t.icon
    readonly property color disabled: root._t.disabled

    // ── Accent and status ────────────────────────────────
    readonly property color accent: root._t.accent
    readonly property color green: root._t.green
    readonly property color orange: root._t.orange
    readonly property color red: root._t.red

    readonly property color dangerBg: root._t.dangerBg
    readonly property color dangerBorder: root._t.dangerBorder
    readonly property color badgePacman: root._t.badgePacman
    readonly property color badgeAur: root._t.badgeAur
    readonly property color badgeFlatpak: root._t.badgeFlatpak
    readonly property color installedBg: root._t.installedBg

    // ── Compositor colours ───────────────────────────────
    // Hyprland's window-border pair (hypr/modules/colors.lua reads the
    // same matugen file), for common/HyprFrame.qml. Always the
    // wallpaper's, even in custom mode: Hyprland doesn't follow a custom
    // palette, and a frame is only worth drawing if it matches the window
    // edges around it.
    readonly property color compositorStart: wallpaper.compositor
        ? wallpaper.compositor.start : Palette.COMPOSITOR_FALLBACK.start
    readonly property color compositorEnd: wallpaper.compositor
        ? wallpaper.compositor.end : Palette.COMPOSITOR_FALLBACK.end

    // ── Shadow ───────────────────────────────────────────
    // Not from any palette: a fixed translucent black reads correctly
    // under light and dark palettes alike.
    readonly property color shadow: "#99000000"
}
