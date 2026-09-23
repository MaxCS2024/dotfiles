import Quickshell
import Quickshell.Io
import QtQuick

// Writes the active palette out as terminal colours — foot's, kitty's and
// ghostty's, one file each — whenever it changes. Reads Appearance like
// any other surface; built once, in shell.qml.
//
// Each terminal's config includes the file written here *after* the one
// matugen writes, so these keys win whenever custom mode is on — see
// ../../foot/foot.ini, ../../kitty/kitty.conf and
// ../../ghostty/config.ghostty. Writing separate files rather than
// matugen's own keeps the two from clobbering each other: matugen
// rewrites its files on every wallpaper change, whichever mode is on.
//
// In wallpaper mode each file is written with no keys in it at all,
// rather than removed: foot and kitty log an error for a missing
// include on every startup (though both go on to start), and a file with
// nothing in it leaves matugen's colors showing through untouched.
//
// foot's colours all go in [colors-dark], even for a light theme like
// Catppuccin Latte — foot.ini never sets initial-color-theme and foot's
// default is dark, so [colors-light] would simply never be read. The
// roles mirror ../../matugen/templates/foot-colors.ini (and its kitty and
// ghostty siblings) so both sources produce the same shaped palette.
//
// foot reads its config once at startup: a theme change lands in the
// next terminal opened, not the ones already running. There's no reload
// to poke it with — foot's SIGUSR1/SIGUSR2 switch between the two color
// sections it parsed at startup, they don't re-read a file. kitty
// (SIGUSR1) and ghostty (SIGUSR2) do re-read theirs, so they get told
// after every write and open windows change along with the shell.
//
// Fixed paths rather than Quickshell.dataPath(): that resolves per shell
// id, and the terminal configs have no way to know which one is running.
// The flip side is that two quickshell configs both building this would
// write over each other here.
Scope {
    id: root

    readonly property string _dir: Quickshell.env("HOME") + "/.cache/quickshell"
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

    // The sixteen ANSI slots plus foreground and background, as "#rrggbb",
    // or null in wallpaper mode. bright1-6 repeat their regular
    // counterparts, exactly as the matugen templates do: one named hue
    // per slot, not a second lighter invention of it.
    readonly property var _palette: {
        if (!Appearance.active) return null
        const hex = Appearance.toHex
        const black = hex(Appearance.surface), red = hex(Appearance.red),
              green = hex(Appearance.green), yellow = hex(Appearance.orange),
              blue = hex(Appearance.accent), magenta = hex(root._magenta),
              cyan = hex(root._cyan), fg = hex(Appearance.fgStrong)
        return {
            fg: fg, bg: hex(Appearance.bar),
            ansi: [black, red, green, yellow, blue, magenta, cyan, hex(Appearance.fgSoft),
                   hex(Appearance.border), red, green, yellow, blue, magenta, cyan, fg]
        }
    }

    function _head(config) {
        return "# Written by quickshell (theme/TerminalTheme.qml) — do not edit by hand.\n"
             + "# Included from " + config + " after matugen's colors, so anything set\n"
             + "# here overrides the wallpaper palette.\n"
             + (root._palette ? "#\n"
                : "#\n# No theme picked — following the wallpaper (matugen) colors.\n")
    }

    // foot wants bare RRGGBB, no leading '#'.
    readonly property string _footIni: {
        const p = root._palette
        const head = root._head("foot.ini")
        if (!p) return head
        const bare = c => c.substring(1)
        const slots = i => (i < 8 ? "regular" + i : "bright" + (i - 8)) + "=" + bare(p.ansi[i]) + "\n"
        let body = "[colors-dark]\nforeground=" + bare(p.fg) + "\nbackground=" + bare(p.bg) + "\n\n"
        for (let i = 0; i < 16; i++) body += (i === 8 ? "\n" : "") + slots(i)
        return head + body
    }

    readonly property string _kittyConf: {
        const p = root._palette
        const head = root._head("kitty.conf")
        if (!p) return head
        let body = "foreground " + p.fg + "\nbackground " + p.bg + "\n\n"
        for (let i = 0; i < 16; i++) body += (i === 8 ? "\n" : "") + "color" + i + " " + p.ansi[i] + "\n"
        return head + body
    }

    readonly property string _ghosttyConf: {
        const p = root._palette
        const head = root._head("config.ghostty")
        if (!p) return head
        let body = "foreground = " + p.fg + "\nbackground = " + p.bg + "\n\n"
        for (let i = 0; i < 16; i++) body += (i === 8 ? "\n" : "") + "palette = " + i + "=" + p.ansi[i] + "\n"
        return head + body
    }

    // Debounced: editing a hex field changes the palette on every
    // keystroke, and the saved palette arrives a moment after startup,
    // so this waits for the palette to settle before writing.
    on_PaletteChanged: writeTimer.restart()
    Timer {
        id: writeTimer
        interval: 300
        onTriggered: {
            if (!root._dirReady) return
            footFile.setText(root._footIni)
            kittyFile.setText(root._kittyConf)
            ghosttyFile.setText(root._ghosttyConf)
            reload.running = false
            reload.running = true
        }
    }

    // After the writes, not alongside them: a reload that lands before
    // the file does re-reads the old colours. pkill exits 1 when there is
    // no kitty or ghostty running, which is fine and says nothing.
    Process {
        id: reload
        command: ["sh", "-c", "pkill -USR1 -x kitty; pkill -USR2 -x ghostty; true"]
    }

    // FileView writes atomically through a temp file alongside the
    // target, which fails outright if ~/.cache/quickshell doesn't exist
    // yet — hence the mkdir before the first write.
    //
    // matugen's two include targets get an empty placeholder here too,
    // when missing. Until the first wallpaper change nothing writes them,
    // and foot (which has no optional include) and kitty both log an
    // error for every terminal opened meanwhile. Empty reads exactly as
    // missing would, and matugen overwrites it. `set -C` makes the
    // create fail rather than truncate if matugen got there first.
    // ghostty's includes are `?`-optional and need nothing.
    Process {
        running: true
        command: ["sh", "-c",
            'mkdir -p "$1" "$2" && set -C && for f in foot-colors.ini kitty-colors.conf; do'
            + ' [ -e "$2/$f" ] || : > "$2/$f" 2>/dev/null; done; true',
            "sh", root._dir, Quickshell.env("HOME") + "/.cache/matugen"]
        onExited: {
            root._dirReady = true
            footFile.path = root._dir + "/foot-theme.ini"
            kittyFile.path = root._dir + "/kitty-theme.conf"
            ghosttyFile.path = root._dir + "/ghostty-theme"
            writeTimer.restart()
        }
    }

    FileView {
        id: footFile
        printErrors: false
    }
    FileView {
        id: kittyFile
        printErrors: false
    }
    FileView {
        id: ghosttyFile
        printErrors: false
    }
}
