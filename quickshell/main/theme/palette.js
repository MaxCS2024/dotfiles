.pragma library

// The one place a palette is derived. Every palette source — the
// wallpaper, a preset, a hand-edited palette — first becomes a *base
// palette* (bg, fg, accent, plus optional surface, border, green,
// orange, red), and derive() turns that into every token the shell
// draws with. theme/Appearance.qml is the only caller; tests/palette
// tests this file directly, so it has no QML or I/O in it.
//
// Colours may be passed as "#rrggbb" strings or Qt colours. Everything
// returned is a Qt colour.

// Used when the wallpaper has produced no colours yet (matugen never
// run, or its file unreadable), and for any status colour a
// hand-edited palette leaves unset. Not pure black: Qt.lighter() can't
// lift a colour whose HSV value is 0, so a #000000 ground would
// collapse the whole surface ladder onto itself.
var DEFAULT = {
    name: "Default",
    bg: "#111111", fg: "#eeeeee", accent: "#60a5fa",
    green: "#4ade80", orange: "#fb923c", red: "#f87171"
}

// Hyprland's own no-matugen border colours (hypr/modules/colors.lua),
// so a frame still matches the window edges before matugen has run.
var COMPOSITOR_FALLBACK = { start: "#33ccff", end: "#00ff99" }

// Every token derive() returns, in one list, so tests can check that
// each source produces all of them.
var TOKENS = [
    "sunken", "bar", "surface", "surfaceAlt", "hover", "hoverStrong", "selected",
    "trackBg", "scrollTrack", "scrollThumb",
    "border", "separator",
    "fgStrong", "fg", "fgSoft", "fgMuted", "fgFaint", "fgDim",
    "placeholder", "icon", "disabled",
    "accent", "green", "orange", "red",
    "dangerBg", "dangerBorder", "badgePacman", "badgeAur", "badgeFlatpak", "installedBg"
]

// Qt.color, not Qt.lighter(v, 1.0): lighter() round-trips through HSV
// and can move a channel by a rounding step, so the base colours would
// no longer be exactly the ones the palette names.
function _col(v) { return typeof v === "string" ? Qt.color(v) : v }
function _set(v) { return v !== undefined && v !== null && v !== "" }

// WCAG relative luminance, on the unlinearised channels — the same
// approximation the shell has always used; it only has to rank colours.
function luminance(c) {
    c = _col(c)
    return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
}

function contrastRatio(c1, c2) {
    var l1 = luminance(c1) + 0.05
    var l2 = luminance(c2) + 0.05
    return l1 > l2 ? l1 / l2 : l2 / l1
}

function isDark(bg) { return luminance(bg) < 0.5 }

// A hand-edited palette's fields as Appearance stores them: bg/fg/accent
// always set, the rest "" when unset. Unset status colours come from
// DEFAULT, never from the wallpaper, so a custom palette doesn't change
// when the wallpaper does.
function fromCustom(f) {
    return {
        bg: f.bg, fg: f.fg, accent: f.accent,
        surface: _set(f.surface) ? f.surface : undefined,
        border: _set(f.border) ? f.border : undefined,
        green: _set(f.green) ? f.green : DEFAULT.green,
        orange: _set(f.orange) ? f.orange : DEFAULT.orange,
        red: _set(f.red) ? f.red : DEFAULT.red
    }
}

// matugen's colors.json (matugen/templates/colors.json) as text. Returns
// { base, compositor } or null when the file is unusable, in which case
// the caller keeps DEFAULT rather than half-applying it.
function fromMatugen(text) {
    var parsed
    try { parsed = JSON.parse(text) } catch (e) { return null }
    var s = parsed && parsed.special
    var c = parsed && parsed.colors
    var required = [s && s.background, s && s.foreground,
        c && c.color1, c && c.color2, c && c.color3, c && c.color4]
    for (var i = 0; i < required.length; i++)
        if (typeof required[i] !== "string" || required[i].length === 0) return null
    return {
        base: {
            bg: s.background, fg: s.foreground, accent: c.color4,
            green: c.color2, orange: c.color3, red: c.color1
        },
        // The pair hypr/modules/colors.lua gives col.active_border.
        compositor: { start: c.color4, end: c.color2 }
    }
}

// Base palette in, every token out.
//
// Surfaces move away from bg and text recedes towards it, in whichever
// direction bg's luminance calls for: on a light palette Qt.lighter()
// would saturate to white after a step or two and every surface would
// collapse into one.
//
// An explicit surface (or border) carries the steps above it: the
// ladder re-bases on it at n / 1.15 (or n / 1.7), which keeps exactly
// the spacing a bg-derived ladder has, so an override can never end up
// darker than the step above it.
function derive(base) {
    var bg = _col(base.bg)
    var fg = _col(base.fg)
    var accent = _col(base.accent)
    var dark = isDark(bg)
    var hasSurface = _set(base.surface)
    var hasBorder = _set(base.border)

    function elevate(c, n) { return dark ? Qt.lighter(c, n) : Qt.darker(c, n) }
    function recede(c, n) { return dark ? Qt.darker(c, n) : Qt.lighter(c, n) }
    function lift(n) { return hasSurface ? elevate(_col(base.surface), n / 1.15) : elevate(bg, n) }
    function line(n) { return hasBorder ? elevate(_col(base.border), n / 1.7) : elevate(bg, n) }

    var surface = lift(1.15)

    // The second-most-receded text tone, so the first to disappear on a
    // low-contrast palette. Backs the recede factor off until it clears
    // 3:1 against surface; n = 1.0 is fg itself, the most contrast the
    // palette has, so the loop always ends.
    function muted() {
        var n = 1.55
        var c = recede(fg, n)
        while (contrastRatio(c, surface) < 3.0 && n > 1.0) {
            n = Math.max(1.0, n - 0.05)
            c = recede(fg, n)
        }
        return c
    }

    var green = _col(_set(base.green) ? base.green : DEFAULT.green)
    var orange = _col(_set(base.orange) ? base.orange : DEFAULT.orange)
    var red = _col(_set(base.red) ? base.red : DEFAULT.red)

    return {
        // One step *below* the bar: a recessed track set into it (the
        // workspace strip). Moves the opposite way from the surface
        // ladder, so it reads as sunken on light palettes too.
        sunken: recede(bg, 1.35),
        bar: bg,
        surface: surface,
        surfaceAlt: lift(1.25),
        hover: lift(1.35),
        hoverStrong: lift(1.45),
        selected: lift(1.55),
        trackBg: lift(1.3),
        scrollTrack: lift(1.1),
        scrollThumb: lift(1.8),

        border: line(1.7),
        separator: line(1.5),

        fgStrong: fg,
        fg: recede(fg, 1.03),
        fgSoft: recede(fg, 1.15),
        fgMuted: muted(),
        fgFaint: recede(fg, 1.7),
        fgDim: recede(fg, 2.1),
        placeholder: recede(fg, 1.9),
        icon: recede(fg, 1.02),
        disabled: recede(fg, 2.5),

        accent: accent,
        green: green,
        orange: orange,
        red: red,

        // Washes of the status colours, so a palette's red drags its
        // danger background along with it.
        dangerBg: Qt.darker(red, 2.2),
        dangerBorder: Qt.darker(red, 1.3),
        badgePacman: Qt.darker(accent, 1.8),
        badgeAur: Qt.darker(orange, 1.8),
        badgeFlatpak: Qt.darker(green, 1.8),
        installedBg: Qt.darker(green, 2.2)
    }
}
