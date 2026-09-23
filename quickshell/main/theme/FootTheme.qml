import Quickshell
import Quickshell.Io
import QtQuick

// Writes the active palette out as foot's terminal colours, whenever it
// changes. Reads Appearance like any other surface; built once, in
// shell.qml.
//
// foot.ini includes the file written here *after* the one matugen
// writes, so these keys win whenever custom mode is on — see the two
// include lines in ../../foot/foot.ini. Writing a separate file rather
// than matugen's own keeps the two from clobbering each other: matugen
// rewrites its file on every wallpaper change, whichever mode is on.
//
// In wallpaper mode the file is written with no keys in it at all,
// rather than removed: the include still has to resolve (foot logs an
// error for a missing one on every startup, though it does go on to
// start), and a file with nothing in it leaves matugen's colors showing
// through untouched.
//
// Everything goes in [colors-dark] even for a light theme like
// Catppuccin Latte — foot.ini never sets initial-color-theme and foot's
// default is dark, so [colors-light] would simply never be read. The
// roles mirror ../../matugen/templates/foot-colors.ini so both sources
// produce the same shaped palette.
//
// foot reads its config once at startup: a theme change lands in the
// next terminal opened, not the ones already running. There's no reload
// to poke it with — foot's SIGUSR1/SIGUSR2 switch between the two color
// sections it parsed at startup, they don't re-read a file.
//
// A fixed path rather than Quickshell.dataPath(): that resolves per
// shell id, and foot.ini has no way to know which one is running. The
// flip side is that two quickshell configs both building this would
// write over each other here.
Scope {
    id: root

    readonly property string _path: Quickshell.env("HOME") + "/.cache/quickshell/foot-theme.ini"
    property bool _dirReady: false

    // A named theme brings its own magenta and cyan (Palettes.qml). A
    // hand-edited palette has neither, so those two slots take the
    // canonical hues at the accent's own saturation and lightness:
    // recognizably magenta and cyan, but belonging to this palette
    // rather than to whatever the last wallpaper produced.
    readonly property var _preset: {
        for (const p of Palettes.list)
            if (Appearance.matchesPalette(p)) return p
        return null
    }
    function _atHue(c, h) { return Qt.hsla(h, c.hslSaturation, c.hslLightness, 1) }
    readonly property color _magenta: root._preset && root._preset.magenta
        ? root._preset.magenta : root._atHue(Appearance.accent, 300 / 360)
    readonly property color _cyan: root._preset && root._preset.cyan
        ? root._preset.cyan : root._atHue(Appearance.accent, 180 / 360)

    // foot wants bare RRGGBB, no leading '#'.
    function _ansi(c) { return Appearance.toHex(c).substring(1) }

    readonly property string _ini: {
        const head = "# Written by quickshell (theme/FootTheme.qml) — do not edit by hand.\n"
                   + "# Included from foot.ini after matugen's colors, so anything set\n"
                   + "# here overrides the wallpaper palette.\n"
        if (!Appearance.active)
            return head + "#\n# No theme picked — following the wallpaper (matugen) colors.\n"

        // bright1-6 repeat their regular counterparts, exactly as the
        // matugen template does: one named hue per slot, not a second
        // lighter invention of it.
        const c = {
            fg: _ansi(Appearance.fgStrong), bg: _ansi(Appearance.bar),
            black: _ansi(Appearance.surface), brightBlack: _ansi(Appearance.border),
            red: _ansi(Appearance.red), green: _ansi(Appearance.green),
            yellow: _ansi(Appearance.orange), blue: _ansi(Appearance.accent),
            magenta: _ansi(root._magenta), cyan: _ansi(root._cyan),
            white: _ansi(Appearance.fgSoft)
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

    // Debounced: editing a hex field changes the palette on every
    // keystroke, and the saved palette arrives a moment after startup,
    // so this waits for the palette to settle before writing.
    on_IniChanged: writeTimer.restart()
    Timer {
        id: writeTimer
        interval: 300
        onTriggered: if (root._dirReady) footFile.setText(root._ini)
    }

    // FileView writes atomically through a temp file alongside the
    // target, which fails outright if ~/.cache/quickshell doesn't exist
    // yet — hence the mkdir before the first write.
    Process {
        running: true
        command: ["mkdir", "-p", root._path.substring(0, root._path.lastIndexOf("/"))]
        onExited: {
            root._dirReady = true
            footFile.path = root._path
            writeTimer.restart()
        }
    }

    FileView {
        id: footFile
        printErrors: false
    }
}
