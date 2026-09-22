pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "../services"

// Lets the shell pick between following Theme's live wallpaper-derived
// palette (matugen, or its hardcoded fallback when matugen isn't
// running) and a fixed custom palette instead.
//
// Started as an experiment in a second config named Fall, scoped narrow
// rather than editing config/Theme.qml directly because config/ was
// symlinked shared with quickshell/main and a toggle there would have
// repainted main too. Both that config and the shared symlink are gone;
// this is main's own file now, and the surfaces it named —
// quicksettings/, systemsettings/ — were deleted with them.
//
// What the narrow scoping left behind is still true, for a smaller
// reason: only the tokens actually rewired read from here. Nine common/
// files (Toast, Tile, PasswordPrompt, Tooltip, ...) still read Theme.*
// colours directly and so don't follow this toggle, which is the whole
// of why "Custom" mode isn't perfectly consistent everywhere.
Singleton {
    id: root

    readonly property string _path: Quickshell.dataPath("fall-appearance.json")

    property bool useCustom: false

    // The three the rest of the custom palette is built out of — always
    // an explicit color, nothing to fall back to.
    property color customBg: "#3a3542"
    property color customFg: "#e6e2ee"
    property color customAccent: "#a99bd1"

    // Optional per-token overrides, editable from
    // systemsettings/SettingsAppearanceTab.qml. Empty string means "no
    // override" — the token keeps deriving itself exactly the way it did
    // before it was editable, so an untouched palette behaves as before.
    // Strings rather than colors precisely so "unset" is representable.
    property string customSurface: ""
    property string customBorder: ""
    property string customGreen: ""
    property string customOrange: ""
    property string customRed: ""

    readonly property bool _surfaceSet: root.customSurface !== ""
    readonly property bool _borderSet: root.customBorder !== ""
    readonly property bool _greenSet: root.customGreen !== ""
    readonly property bool _orangeSet: root.customOrange !== ""
    readonly property bool _redSet: root.customRed !== ""

    // ── Named palettes ─────────────────────────────────────
    // Applying one pins all eight rows (see theme/Palettes.qml for why).
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

    // Shared with SettingsAppearanceTab.qml's hex fields so the editor
    // and the file on disk spell a color the same way.
    function toHex(c) {
        const hex = v => Math.max(0, Math.min(255, Math.round(v * 255))).toString(16).padStart(2, "0")
        return "#" + hex(c.r) + hex(c.g) + hex(c.b)
    }

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
    // two hazards they answer. What is left here is what is this file's
    // own: which keys to read back, and the foot palette that has to be
    // rewritten whenever this one changes.
    JsonStore {
        id: appearanceStore
        path: root._path
        snapshot: () => root._snapshot()
        onRestored: (data) => {
            if (data && typeof data === "object") root._apply(data)
            root._writeFoot()
        }
        onSaved: root._writeFoot()
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

    // ── Terminal palette ───────────────────────
    // foot.ini includes the file written here *after* the one matugen
    // writes, so these keys win for as long as a theme is active — see
    // the two include lines in ../../foot/foot.ini. Writing a separate
    // file rather than matugen's own keeps the two from clobbering each
    // other: matugen rewrites its file on every wallpaper change,
    // whether or not a theme is pinned here.
    //
    // In wallpaper mode the file is written with no keys in it at all,
    // rather than removed: the include still has to resolve (foot logs
    // an error for a missing one on every startup, though it does go on
    // to start), and a file with nothing in it leaves matugen's colors
    // showing through untouched.
    //
    // Everything goes in [colors-dark] even for a light theme like
    // Catppuccin Latte — foot.ini never sets initial-color-theme and
    // foot's default is dark, so [colors-light] would simply never be
    // read. The roles mirror ../../matugen/templates/foot-colors.ini so
    // both sources produce the same shaped palette.
    //
    // foot reads its config once at startup: a theme change lands in the
    // next terminal opened, not the ones already running. There's no
    // reload to poke it with — foot's SIGUSR1/SIGUSR2 switch between the
    // two color sections it parsed at startup, they don't re-read a file.
    //
    // A fixed path rather than Quickshell.dataPath() like _path above:
    // that resolves per shell id, and foot.ini has no way to know which
    // one is running. The flip side is that two quickshell configs both
    // running this file would write over each other here — only main
    // has theme/ today.
    readonly property string _footPath: Quickshell.env("HOME") + "/.cache/quickshell/foot-theme.ini"
    property bool _footDirReady: false

    // A named theme brings its own magenta and cyan (Palettes.qml). A
    // hand-edited palette has neither, so those two slots take the
    // canonical hues at the accent's own saturation and lightness:
    // recognizably magenta and cyan, but belonging to this palette
    // rather than to whatever the last wallpaper produced.
    function _matchedPalette() {
        for (const p of Palettes.list)
            if (root.matchesPalette(p)) return p
        return null
    }
    function _atHue(c, h) { return Qt.hsla(h, c.hslSaturation, c.hslLightness, 1) }
    readonly property color termMagenta: {
        const p = root._matchedPalette()
        return p ? p.magenta : root._atHue(root.accent, 300 / 360)
    }
    readonly property color termCyan: {
        const p = root._matchedPalette()
        return p ? p.cyan : root._atHue(root.accent, 180 / 360)
    }

    // foot wants bare RRGGBB, no leading '#'.
    function _ansi(c) { return root.toHex(c).substring(1) }
    function _footIni() {
        const head = "# Written by quickshell (theme/Appearance.qml) — do not edit by hand.\n"
                   + "# Included from foot.ini after matugen's colors, so anything set\n"
                   + "# here overrides the wallpaper palette.\n"
        if (!root.active)
            return head + "#\n# No theme picked — following the wallpaper (matugen) colors.\n"

        // bright1-6 repeat their regular counterparts, exactly as the
        // matugen template does: one named hue per slot, not a second
        // lighter invention of it.
        const c = {
            fg: root._ansi(root.customFg), bg: root._ansi(root.customBg),
            black: root._ansi(root.surface), brightBlack: root._ansi(root.border),
            red: root._ansi(root.red), green: root._ansi(root.green),
            yellow: root._ansi(root.orange), blue: root._ansi(root.accent),
            magenta: root._ansi(root.termMagenta), cyan: root._ansi(root.termCyan),
            white: root._ansi(root.fgSoft)
        }
        return head
            + "#\n"
            + "[colors-dark]\n"
            + "foreground=" + c.fg + "\n"
            + "background=" + c.bg + "\n"
            + "\n"
            + "regular0=" + c.black + "\n"
            + "regular1=" + c.red + "\n"
            + "regular2=" + c.green + "\n"
            + "regular3=" + c.yellow + "\n"
            + "regular4=" + c.blue + "\n"
            + "regular5=" + c.magenta + "\n"
            + "regular6=" + c.cyan + "\n"
            + "regular7=" + c.white + "\n"
            + "\n"
            + "bright0=" + c.brightBlack + "\n"
            + "bright1=" + c.red + "\n"
            + "bright2=" + c.green + "\n"
            + "bright3=" + c.yellow + "\n"
            + "bright4=" + c.blue + "\n"
            + "bright5=" + c.magenta + "\n"
            + "bright6=" + c.cyan + "\n"
            + "bright7=" + c.fg + "\n"
    }

    // Guarded on the mkdir below rather than assuming the directory is
    // there: FileView writes atomically through a temp file alongside
    // the target, which fails outright if ~/.cache/quickshell doesn't
    // exist yet.
    function _writeFoot() {
        if (!root._footDirReady) return
        footFile.setText(root._footIni())
    }

    // Whichever of these two finishes last is the one that writes the
    // loaded palette: the saved file can't write before the directory is
    // ready, and the directory can't write anything but defaults before
    // the file has loaded. Both paths end at the same content.
    Process {
        running: true
        command: ["mkdir", "-p", root._footPath.substring(0, root._footPath.lastIndexOf("/"))]
        onExited: {
            root._footDirReady = true
            footFile.path = root._footPath
            root._writeFoot()
        }
    }

    FileView {
        id: footFile
        printErrors: false
    }

    // ── Custom-palette derivation ──────────────────────────
    // Mirrors Theme.qml's luminance-aware elevate()/recede() approach,
    // just measured against customBg/customFg instead of the matugen
    // palette — so "Custom" mode gets the same light/dark-aware
    // elevation and text-recession behavior as wallpaper mode does.
    readonly property real _bgLuminance: 0.2126 * customBg.r + 0.7152 * customBg.g + 0.0722 * customBg.b
    readonly property bool _isDark: _bgLuminance < 0.5
    function _elevate(c, n) { return root._isDark ? Qt.lighter(c, n) : Qt.darker(c, n) }
    function _recede(c, n) { return root._isDark ? Qt.darker(c, n) : Qt.lighter(c, n) }
    function _luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    function _contrastRatio(c1, c2) {
        const l1 = root._luminance(c1) + 0.05
        const l2 = root._luminance(c2) + 0.05
        return l1 > l2 ? l1 / l2 : l2 / l1
    }
    // An overridden surface has to carry the hover/selected/track ladder
    // that sits on top of it, or an explicit surface ends up darker than
    // the surfaceAlt above it. _elevate is multiplicative on value, so
    // re-basing each step on the override at n/1.15 preserves exactly
    // the spacing the bg-derived ladder had. Same idea for the two line
    // tones, based on border's own 1.7.
    function _lift(n) {
        return root._surfaceSet ? root._elevate(root.customSurface, n / 1.15)
                                : root._elevate(root.customBg, n)
    }
    function _line(n) {
        return root._borderSet ? root._elevate(root.customBorder, n / 1.7)
                               : root._elevate(root.customBg, n)
    }

    readonly property color _customSurface: root._lift(1.15)
    // Theme's _fgMutedColor for a pinned palette, and it carried the same
    // inverted loop until 2026-09-18 — see that function for what the
    // direction was doing. This is the copy that was actually visible:
    // a custom palette is what `active` means, so every fgMuted on
    // screen came through here.
    function _fgMutedColor() {
        let n = 1.55
        let c = root._recede(root.customFg, n)
        while (root._contrastRatio(c, root._customSurface) < 3.0 && n > 1.0) {
            n = Math.max(1.0, n - 0.05)
            c = root._recede(root.customFg, n)
        }
        return c
    }

    readonly property bool active: root.useCustom

    // ── Surfaces ─────────────────────────────────────────
    readonly property color bar: active ? customBg : Theme.bar
    readonly property color surface: active ? _customSurface : Theme.surface
    readonly property color surfaceAlt: active ? _lift(1.25) : Theme.surfaceAlt
    readonly property color hover: active ? _lift(1.35) : Theme.hover
    readonly property color hoverStrong: active ? _lift(1.45) : Theme.hoverStrong
    readonly property color selected: active ? _lift(1.55) : Theme.selected
    readonly property color trackBg: active ? _lift(1.3) : Theme.trackBg
    readonly property color wsOccupied: active ? _lift(1.25) : Theme.wsOccupied
    readonly property color settingsSidebarBg: active ? _lift(1.1) : Theme.settingsSidebarBg

    // The scroll rail's two tones, at the same factors Theme derives
    // its own from. Only reachable by handing them to
    // common/ListScrollBar.qml site by site: that file is symlinked
    // shared with the old config, which has no theme/ of its own to
    // import, so its defaults have to stay on Theme.
    readonly property color scrollTrack: active ? _lift(1.1) : Theme.scrollTrack
    readonly property color scrollThumb: active ? _lift(1.8) : Theme.scrollThumb

    // ── Lines ────────────────────────────────────────────
    readonly property color border: active ? _line(1.7) : Theme.border
    readonly property color separator: active ? _line(1.5) : Theme.separator

    // ── Text ─────────────────────────────────────────────
    readonly property color fgStrong: active ? customFg : Theme.fgStrong
    readonly property color fg: active ? _recede(customFg, 1.03) : Theme.fg
    readonly property color fgSoft: active ? _recede(customFg, 1.15) : Theme.fgSoft
    readonly property color fgMuted: active ? _fgMutedColor() : Theme.fgMuted
    readonly property color fgFaint: active ? _recede(customFg, 1.7) : Theme.fgFaint
    readonly property color fgDim: active ? _recede(customFg, 2.1) : Theme.fgDim
    readonly property color placeholder: active ? _recede(customFg, 1.9) : Theme.placeholder
    readonly property color icon: active ? _recede(customFg, 1.02) : Theme.icon
    readonly property color disabled: active ? _recede(customFg, 2.5) : Theme.disabled

    // ── Accent ───────────────────────────────────────────
    readonly property color accent: active ? customAccent : Theme.accent
    readonly property color accentText: root.accent

    // ── Status/semantic colors ───────────────────────────
    // These stay on Theme's values by default, and are deliberately not
    // derived from customAccent: one accent doesn't carry enough hue
    // information to invent a whole badge set, and re-tinting green/red/
    // orange away from success/danger/warning would be actively wrong.
    // Naming them outright is the one thing that *does* work, so each is
    // separately settable — with Theme's value as the fallback whenever
    // it isn't set.
    readonly property color green: active && _greenSet ? customGreen : Theme.green
    readonly property color orange: active && _orangeSet ? customOrange : Theme.orange
    readonly property color red: active && _redSet ? customRed : Theme.red

    // The tinted badge/background pairs Theme derives off the same three
    // hues, at Theme.qml's own factors — so a named status color drags
    // its washes along instead of leaving them on the old hue. Left on
    // Theme when unset, since Theme's non-matugen fallbacks are
    // hand-picked rather than derived.
    readonly property color dangerBg: active && _redSet ? Qt.darker(root.red, 2.2) : Theme.dangerBg
    readonly property color dangerBorder: active && _redSet ? Qt.darker(root.red, 1.3) : Theme.dangerBorder
    readonly property color badgeAur: active && _orangeSet ? Qt.darker(root.orange, 1.8) : Theme.badgeAur
    readonly property color badgeFlatpak: active && _greenSet ? Qt.darker(root.green, 1.8) : Theme.badgeFlatpak
    readonly property color installedBg: active && _greenSet ? Qt.darker(root.green, 2.2) : Theme.installedBg
    // No custom counterpart — pacman's badge is keyed off Theme's blue.
    readonly property color badgePacman: Theme.badgePacman

    readonly property color barGlass: Qt.rgba(root.bar.r, root.bar.g, root.bar.b, Theme.alphaBar)
}
