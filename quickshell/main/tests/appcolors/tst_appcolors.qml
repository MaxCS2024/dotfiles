import QtQuick
import QtTest
import "../../theme/palette.js" as Palette
import "../../theme/appcolors.js" as AppColors

// Tests the app colours through their interface: a derived palette in,
// each app's file text out. Runs under qmltestrunner (tests/run
// appcolors), so no Wayland or Hyprland session is needed.
TestCase {
    name: "AppColors"

    // Tokyo Night as Palettes.qml publishes it, magenta and cyan included,
    // and Catppuccin Latte for a light palette.
    readonly property var night: Palette.derive(Palette.fromCustom({
        bg: "#1a1b26", surface: "#24283b", fg: "#c0caf5", accent: "#7aa2f7",
        border: "#3b4261", green: "#9ece6a", orange: "#e0af68", red: "#f7768e",
        magenta: "#bb9af7", cyan: "#7dcfff" }))
    readonly property var latte: Palette.derive(Palette.fromCustom({
        bg: "#eff1f5", surface: "#ccd0da", fg: "#4c4f69", accent: "#8839ef",
        border: "#9ca0b0", green: "#40a02b", orange: "#fe640b", red: "#d20f39",
        magenta: "#ea76cb", cyan: "#179299" }))

    // "key<sep>value" lines of a file, as a map.
    function pairs(text, pattern) {
        const out = ({})
        for (const line of text.split("\n")) {
            const m = line.match(pattern)
            if (m) out[m[1]] = m[2].toLowerCase()
        }
        return out
    }

    // ── The ANSI slots ───────────────────────────────────

    function test_slots_come_from_the_palette() {
        const p = AppColors.ansi(night)
        compare(p.slots.length, 16)
        compare(p.fg, "#c0caf5")
        compare(p.bg, "#1a1b26")
        compare(p.slots[1], "#f7768e", "red")
        compare(p.slots[2], "#9ece6a", "green")
        compare(p.slots[3], "#e0af68", "yellow is the palette's orange")
        compare(p.slots[4], "#7aa2f7", "blue is the accent")
        compare(p.slots[5], "#bb9af7", "magenta")
        compare(p.slots[6], "#7dcfff", "cyan")
        compare(p.slots[15], "#c0caf5", "bright white is the strongest text")
    }

    function test_bright_hues_repeat_the_regular_ones() {
        const s = AppColors.ansi(night).slots
        for (let i = 1; i <= 6; i++) compare(s[i + 8], s[i], "slot " + (i + 8))
    }

    function test_hues_a_palette_leaves_unset_are_filled() {
        const t = Palette.derive(Palette.fromCustom({ bg: "#263238", fg: "#eeffff", accent: "#80cbc4" }))
        const s = AppColors.ansi(t).slots
        verify(/^#[0-9a-f]{6}$/.test(s[5]), s[5])
        verify(s[5] !== s[4] && s[6] !== s[4], "not just the accent again")
    }

    // ── Every terminal, the same palette ─────────────────

    function test_three_terminals_agree() {
        const foot = pairs(AppColors.foot(night), /^(regular\d|bright\d|foreground|background)=([0-9a-f]{6})$/)
        const kitty = pairs(AppColors.kitty(night), /^(color\d+|foreground|background)\s+(#[0-9a-f]{6})$/)
        const ghostty = pairs(AppColors.ghostty(night), /^palette = (\d+)=(#[0-9a-f]{6})$/)
        const p = AppColors.ansi(night)
        for (let i = 0; i < 16; i++) {
            const footKey = i < 8 ? "regular" + i : "bright" + (i - 8)
            compare("#" + foot[footKey], p.slots[i], "foot " + footKey)
            compare(kitty["color" + i], p.slots[i], "kitty color" + i)
            compare(ghostty[String(i)], p.slots[i], "ghostty " + i)
        }
        compare("#" + foot.foreground, p.fg)
        compare(kitty.background, p.bg)
    }

    function test_foot_is_colors_dark_even_when_light() {
        // foot only reads [colors-dark]; see appcolors.js.
        verify(AppColors.foot(latte).indexOf("\n[colors-dark]\n") !== -1)
        verify(AppColors.foot(latte).indexOf("background=eff1f5") !== -1)
    }

    function test_every_file_says_where_it_comes_from() {
        for (const text of [AppColors.foot(night), AppColors.kitty(night),
                            AppColors.ghostty(night), AppColors.gtk(night)])
            verify(text.indexOf("theme/AppColors.qml") !== -1, text.substring(0, 40))
    }

    // ── GTK ──────────────────────────────────────────────

    function test_gtk_names_both_vocabularies() {
        const g = pairs(AppColors.gtk(night), /^@define-color (\w+) (#[0-9a-f]{6});$/)
        compare(g.theme_bg_color, "#1a1b26", "GTK3 window")
        compare(g.window_bg_color, "#1a1b26", "GTK4 window")
        compare(g.accent_bg_color, "#7aa2f7")
        compare(g.accent_fg_color, "#1a1b26", "text on accent is the bar colour")
        compare(g.error_color, "#f7768e")
    }

    function test_gtk_surfaces_are_the_shells() {
        const g = pairs(AppColors.gtk(night), /^@define-color (\w+) (#[0-9a-f]{6});$/)
        compare(g.view_bg_color, AppColors.hex(night.surface))
        compare(g.card_bg_color, AppColors.hex(night.surfaceAlt))
        compare(g.secondary_sidebar_bg_color, AppColors.hex(night.sunken))
    }

    function test_gtk_follows_a_light_palette() {
        const g = pairs(AppColors.gtk(latte), /^@define-color (\w+) (#[0-9a-f]{6});$/)
        compare(g.window_bg_color, "#eff1f5")
        compare(g.window_fg_color, "#4c4f69")
    }

    function test_color_scheme_follows_the_palette() {
        compare(AppColors.colorScheme(night), "prefer-dark")
        compare(AppColors.colorScheme(latte), "prefer-light")
    }

    function test_hex() {
        compare(AppColors.hex("#ABCDEF"), "#abcdef")
        compare(AppColors.hex(Qt.rgba(1, 0, 0.5, 1)), "#ff0080")
    }
}
