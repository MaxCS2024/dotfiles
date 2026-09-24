import QtQuick
import QtTest
import "../../theme/palette.js" as Palette

// Tests the palette derivation through its interface: base palette in,
// tokens out. Runs under qmltestrunner (tests/run palette), so no
// Wayland or Hyprland session is needed.
TestCase {
    name: "Palette"

    // Two presets' published values (theme/Palettes.qml): one dark, the
    // one light palette. Inlined because Palettes is a Quickshell
    // singleton, which qmltestrunner can't load.
    readonly property var tokyoNight: ({
        bg: "#1a1b26", surface: "#24283b", fg: "#c0caf5", accent: "#7aa2f7",
        border: "#3b4261", green: "#9ece6a", orange: "#e0af68", red: "#f7768e"
    })
    readonly property var latte: ({
        bg: "#eff1f5", surface: "#ccd0da", fg: "#4c4f69", accent: "#8839ef",
        border: "#9ca0b0", green: "#40a02b", orange: "#fe640b", red: "#d20f39"
    })
    readonly property string matugenJson: JSON.stringify({
        special: { background: "#111418", foreground: "#e1e2e8" },
        colors: { color0: "#111418", color1: "#ffb1c2", color2: "#8bd6b5",
                  color3: "#ffb599", color4: "#a0cafd", color8: "#8d9199" }
    })
    // A palette with barely any contrast between text and ground: the
    // case fgMuted's contrast floor exists for.
    readonly property var murky: ({ bg: "#24283b", fg: "#3a3f58", accent: "#7aa2f7" })

    function lum(c) { return Palette.luminance(c) }

    function sources() {
        return [
            { tag: "default", base: Palette.DEFAULT },
            { tag: "dark preset", base: tokyoNight },
            { tag: "light preset", base: latte },
            { tag: "wallpaper", base: Palette.fromMatugen(matugenJson).base },
            { tag: "hand-edited, only required keys",
              base: Palette.fromCustom({ bg: "#263238", fg: "#eeffff", accent: "#80cbc4",
                                         surface: "", border: "", green: "", orange: "", red: "" }) },
            { tag: "low contrast", base: murky }
        ]
    }

    function test_every_source_gives_every_token_data() { return sources() }
    function test_every_source_gives_every_token(data) {
        const t = Palette.derive(data.base)
        for (const name of Palette.TOKENS)
            verify(t[name] !== undefined && t[name].a !== undefined, name + " missing")
        compare(Object.keys(t).length, Palette.TOKENS.length, "no tokens beyond TOKENS")
    }

    function test_dark_ladder_rises_and_text_recedes() {
        const t = Palette.derive(tokyoNight)
        verify(lum(t.surface) > lum(t.bar))
        verify(lum(t.surfaceAlt) > lum(t.surface))
        verify(lum(t.hover) > lum(t.surfaceAlt))
        verify(lum(t.hoverStrong) > lum(t.hover))
        verify(lum(t.selected) > lum(t.hoverStrong))
        verify(lum(t.fg) < lum(t.fgStrong))
        verify(lum(t.fgSoft) < lum(t.fg))
        verify(lum(t.fgDim) < lum(t.fgFaint))
    }

    function test_light_ladder_falls_and_text_recedes() {
        const t = Palette.derive(latte)
        verify(lum(t.surface) < lum(t.bar))
        verify(lum(t.surfaceAlt) < lum(t.surface))
        verify(lum(t.hover) < lum(t.surfaceAlt))
        verify(lum(t.fg) > lum(t.fgStrong))
        verify(lum(t.fgSoft) > lum(t.fg))
        verify(lum(t.fgDim) > lum(t.fgFaint))
    }

    function test_sunken_sits_below_the_bar() {
        const dark = Palette.derive(tokyoNight)
        verify(lum(dark.sunken) < lum(dark.bar))
        const light = Palette.derive(latte)
        verify(lum(light.sunken) > lum(light.bar))
        const def = Palette.derive(Palette.DEFAULT)
        verify(!Qt.colorEqual(def.sunken, def.bar))
    }

    function test_default_ladder_does_not_collapse() {
        const t = Palette.derive(Palette.DEFAULT)
        verify(!Qt.colorEqual(t.surface, t.bar))
        verify(!Qt.colorEqual(t.surfaceAlt, t.surface))
    }

    function test_explicit_surface_keeps_steps_above_it() {
        const t = Palette.derive(tokyoNight)
        verify(lum(t.surfaceAlt) > lum(t.surface))
        verify(lum(t.hover) > lum(t.surfaceAlt))
    }

    function test_muted_text_stays_readable_data() { return sources() }
    function test_muted_text_stays_readable(data) {
        const t = Palette.derive(data.base)
        // Either it clears 3:1, or it has backed off all the way to the
        // palette's own foreground, the most contrast there is.
        verify(Palette.contrastRatio(t.fgMuted, t.surface) >= 3.0
               || Qt.colorEqual(t.fgMuted, t.fgStrong),
               "fgMuted at " + Palette.contrastRatio(t.fgMuted, t.surface).toFixed(2) + ":1")
    }

    function test_unset_status_colours_come_from_default() {
        const base = Palette.fromCustom({ bg: "#263238", fg: "#eeffff", accent: "#80cbc4",
                                          surface: "", border: "", green: "", orange: "#ffcb6b", red: "" })
        const t = Palette.derive(base)
        verify(Qt.colorEqual(t.green, Palette.DEFAULT.green))
        verify(Qt.colorEqual(t.red, Palette.DEFAULT.red))
        verify(Qt.colorEqual(t.orange, "#ffcb6b"))
    }

    function test_wallpaper_accent_is_matugen_primary() {
        const w = Palette.fromMatugen(matugenJson)
        verify(Qt.colorEqual(Palette.derive(w.base).accent, "#a0cafd"))
        verify(Qt.colorEqual(w.compositor.start, "#a0cafd"))
        verify(Qt.colorEqual(w.compositor.end, "#8bd6b5"))
    }

    function test_unusable_matugen_file_is_rejected_data() {
        return [
            { tag: "malformed", text: "{ not json" },
            { tag: "empty", text: "" },
            { tag: "missing primary", text: JSON.stringify({
                special: { background: "#111418", foreground: "#e1e2e8" },
                colors: { color1: "#ffb1c2", color2: "#8bd6b5", color3: "#ffb599" } }) }
        ]
    }
    function test_unusable_matugen_file_is_rejected(data) {
        compare(Palette.fromMatugen(data.text), null)
    }

    // ── The terminal hues ────────────────────────────────

    function test_a_palette_that_names_its_hues_keeps_them() {
        const t = Palette.derive(Palette.fromCustom({
            bg: "#1a1b26", fg: "#c0caf5", accent: "#7aa2f7",
            magenta: "#bb9af7", cyan: "#7dcfff" }))
        verify(Qt.colorEqual(t.magenta, "#bb9af7"))
        verify(Qt.colorEqual(t.cyan, "#7dcfff"))
    }

    function test_unset_hues_come_from_the_accent() {
        // Canonical hues at the accent's own saturation and lightness.
        const t = Palette.derive(tokyoNight)
        const accent = Qt.color(tokyoNight.accent)
        fuzzyCompare(t.magenta.hslHue, 300 / 360, 0.01)
        fuzzyCompare(t.cyan.hslHue, 180 / 360, 0.01)
        fuzzyCompare(t.magenta.hslSaturation, accent.hslSaturation, 0.01)
        fuzzyCompare(t.cyan.hslLightness, accent.hslLightness, 0.01)
    }

    function test_matugen_hues_are_read_when_present() {
        const w = Palette.fromMatugen(JSON.stringify({
            special: { background: "#111418", foreground: "#e1e2e8" },
            colors: { color1: "#ffb1c2", color2: "#8bd6b5", color3: "#ffb599",
                      color4: "#a0cafd", color5: "#d9bde3", color6: "#9ad0e8" } }))
        const t = Palette.derive(w.base)
        verify(Qt.colorEqual(t.magenta, "#d9bde3"))
        verify(Qt.colorEqual(t.cyan, "#9ad0e8"))
    }

    function test_matugen_without_hues_still_makes_a_palette() {
        // A colors.json from before color5/color6 were templated.
        const w = Palette.fromMatugen(matugenJson)
        verify(w !== null)
        fuzzyCompare(Palette.derive(w.base).magenta.hslHue, 300 / 360, 0.01)
    }
}
