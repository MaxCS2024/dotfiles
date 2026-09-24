.pragma library
.import "palette.js" as Palette

// App colours: the active palette written out as the files other apps
// read their colours from, so the terminals and GTK match the shell in
// either mode. See ../../CONTEXT.md.
//
// Pure: the tokens palette.js derives go in, each file's text comes out.
// theme/AppColors.qml writes them and tells the apps; tests/appcolors
// checks this file directly, with no session.
//
// One mapping per kind of app, which is the point of this file. Until
// 2026-09-24 the sixteen ANSI slots were chosen twice — once in matugen's
// templates from Material roles for wallpaper mode, once in the shell for
// custom mode — and kept in step by hand, and GTK only ever saw the
// wallpaper's colours. Now every palette source takes the same road.

// "#rrggbb" for a Qt colour or a colour string.
function hex(c) {
    c = typeof c === "string" ? Qt.color(c) : c
    function two(v) {
        var n = Math.max(0, Math.min(255, Math.round(v * 255))).toString(16)
        return n.length === 1 ? "0" + n : n
    }
    return "#" + two(c.r) + two(c.g) + two(c.b)
}

// The terminal palette: foreground, background and the sixteen ANSI
// slots, as "#rrggbb". The bright half repeats the regular one for the
// six hues — one named colour per slot, not a second lighter invention
// of it — and takes a step up the ladder for black and white.
function ansi(t) {
    var black = hex(t.surface), red = hex(t.red), green = hex(t.green),
        yellow = hex(t.orange), blue = hex(t.accent), magenta = hex(t.magenta),
        cyan = hex(t.cyan), fg = hex(t.fgStrong)
    return {
        fg: fg,
        bg: hex(t.bar),
        slots: [black, red, green, yellow, blue, magenta, cyan, hex(t.fgSoft),
                hex(t.border), red, green, yellow, blue, magenta, cyan, fg]
    }
}

function _head(comment, config) {
    return comment + " Written by quickshell (theme/AppColors.qml) from the active palette —\n"
         + comment + " do not edit by hand. " + config + " includes this file.\n"
}

// foot wants bare RRGGBB. Everything goes in [colors-dark], a light
// palette included: foot.ini never sets initial-color-theme and foot's
// default is dark, so [colors-light] would never be read.
function foot(t) {
    var p = ansi(t)
    function bare(c) { return c.substring(1) }
    var out = _head("#", "foot.ini") + "\n[colors-dark]\n"
        + "foreground=" + bare(p.fg) + "\nbackground=" + bare(p.bg) + "\n\n"
    for (var i = 0; i < 16; i++)
        out += (i === 8 ? "\n" : "") + (i < 8 ? "regular" + i : "bright" + (i - 8)) + "=" + bare(p.slots[i]) + "\n"
    return out
}

function kitty(t) {
    var p = ansi(t)
    var out = _head("#", "kitty.conf") + "\nforeground " + p.fg + "\nbackground " + p.bg + "\n\n"
    for (var i = 0; i < 16; i++)
        out += (i === 8 ? "\n" : "") + "color" + i + " " + p.slots[i] + "\n"
    return out
}

function ghostty(t) {
    var p = ansi(t)
    var out = _head("#", "config.ghostty") + "\nforeground = " + p.fg + "\nbackground = " + p.bg + "\n\n"
    for (var i = 0; i < 16; i++)
        out += (i === 8 ? "\n" : "") + "palette = " + i + "=" + p.slots[i] + "\n"
    return out
}

// GTK's named colours, from the shell's own ladder so a GTK window's
// headerbar, sidebar and cards are the surfaces the bar and panels use.
// Both vocabularies in one file: GTK3's Adwaita theme_* names and
// libadwaita's, and each ignores the other's. Text on the accent is the
// bar colour, the rule the shell's own style guide sets.
//
// Every libadwaita colour left out keeps its stock value from whichever
// stylesheet is loaded, and that comes from the portal's color-scheme,
// which AppColors.qml sets from colorScheme() below: a light palette on
// the dark stylesheet would leave half a window dark.
function gtk(t) {
    var names = [
        // GTK3 (Adwaita)
        ["theme_bg_color", t.bar], ["theme_fg_color", t.fgStrong],
        ["theme_base_color", t.surface], ["theme_text_color", t.fgStrong],
        ["theme_selected_bg_color", t.accent], ["theme_selected_fg_color", t.bar],
        ["borders", t.border],
        null,
        // GTK4 (libadwaita)
        ["accent_color", t.accent], ["accent_bg_color", t.accent], ["accent_fg_color", t.bar],
        ["window_bg_color", t.bar], ["window_fg_color", t.fgStrong],
        ["view_bg_color", t.surface], ["view_fg_color", t.fgStrong],
        ["headerbar_bg_color", t.surface], ["headerbar_fg_color", t.fgStrong],
        ["card_bg_color", t.surfaceAlt], ["card_fg_color", t.fgStrong],
        ["popover_bg_color", t.surfaceAlt], ["popover_fg_color", t.fgStrong],
        ["sidebar_bg_color", t.surface], ["sidebar_fg_color", t.fgStrong],
        ["sidebar_backdrop_color", t.bar],
        ["secondary_sidebar_bg_color", t.sunken], ["secondary_sidebar_fg_color", t.fgStrong],
        ["secondary_sidebar_backdrop_color", t.bar],
        ["dialog_bg_color", t.bar], ["dialog_fg_color", t.fgStrong],
        ["success_color", t.green], ["warning_color", t.orange], ["error_color", t.red],
        ["destructive_color", t.red], ["destructive_bg_color", t.red],
        ["destructive_fg_color", t.bar]
    ]
    var out = "/* Written by quickshell (theme/AppColors.qml) from the active palette —\n"
            + " * do not edit by hand. gtk.css in this directory imports it. */\n\n"
    for (var i = 0; i < names.length; i++)
        out += names[i] === null ? "\n" : "@define-color " + names[i][0] + " " + hex(names[i][1]) + ";\n"
    return out
}

// The value for org.gnome.desktop.interface color-scheme.
function colorScheme(t) {
    return Palette.isDark(t.bar) ? "prefer-dark" : "prefer-light"
}
