pragma Singleton
import Quickshell
import "palette.js" as Palette

// The named palettes offered by SettingsAppearanceTab's preset menu.
//
// Each entry names all eight colors the custom palette can hold, so
// picking one pins every row rather than leaving half of them derived —
// these themes choose their own surface and border tones, and letting
// Appearance.qml elevate() its own would be the one thing that stops a
// palette looking like itself. Individual rows can still be cleared back
// to derived afterwards with the row's own "reset".
//
// magenta and cyan are the exception to that: they are not editable
// rows and matchesPalette() ignores them. They exist because the
// terminal palette written from theme/Appearance.qml needs all sixteen
// ANSI slots, and the eight rows have no opinion about those two hues —
// a hand-edited palette gets them derived from its accent instead.
//
// Colors are the upstream projects' published values, lowercase so
// Appearance.matchesPalette() can compare them as plain strings. Where a
// theme publishes more than one variant, this takes the one it is
// usually meant by (Tokyo Night's "night", Catppuccin's mocha) and names
// the variant when both are worth having.
Singleton {
    readonly property var list: [
        // The neutral dark palette wallpaper mode also uses until matugen
        // has produced colours (palette.js's DEFAULT, so the two can't
        // drift). Unlike the others it leaves surface and border to be
        // derived, and has no terminal hues of its own.
        Object.assign({ surface: "", border: "" }, Palette.DEFAULT),
        {
            name: "Tokyo Night",
            bg: "#1a1b26", surface: "#24283b", fg: "#c0caf5",
            accent: "#7aa2f7", border: "#3b4261",
            green: "#9ece6a", orange: "#e0af68", red: "#f7768e",
            magenta: "#bb9af7", cyan: "#7dcfff"
        },
        {
            name: "Catppuccin Mocha",
            bg: "#1e1e2e", surface: "#313244", fg: "#cdd6f4",
            accent: "#cba6f7", border: "#6c7086",
            green: "#a6e3a1", orange: "#fab387", red: "#f38ba8",
            magenta: "#f5c2e7", cyan: "#94e2d5"
        },
        {
            // The one light palette here, and worth keeping for that
            // alone — it's what exercises Appearance.qml's _isDark
            // branch, where elevate()/recede() swap directions.
            name: "Catppuccin Latte",
            bg: "#eff1f5", surface: "#ccd0da", fg: "#4c4f69",
            accent: "#8839ef", border: "#9ca0b0",
            green: "#40a02b", orange: "#fe640b", red: "#d20f39",
            magenta: "#ea76cb", cyan: "#179299"
        },
        {
            // Gruvbox's bright variants throughout, including the two
            // terminal hues, so the ANSI colors match the red/green/
            // yellow the rows above already picked.
            name: "Gruvbox Dark",
            bg: "#282828", surface: "#3c3836", fg: "#ebdbb2",
            accent: "#fabd2f", border: "#504945",
            green: "#b8bb26", orange: "#fe8019", red: "#fb4934",
            magenta: "#d3869b", cyan: "#8ec07c"
        },
        {
            // ANSI cyan is nord7 rather than the nord8 the spec names,
            // because nord8 is already this palette's accent — and two
            // identical slots would flatten anything that colors with
            // both blue and cyan.
            name: "Nord",
            bg: "#2e3440", surface: "#3b4252", fg: "#d8dee9",
            accent: "#88c0d0", border: "#4c566a",
            green: "#a3be8c", orange: "#d08770", red: "#bf616a",
            magenta: "#b48ead", cyan: "#8fbcbb"
        },
        {
            name: "Dracula",
            bg: "#282a36", surface: "#44475a", fg: "#f8f8f2",
            accent: "#bd93f9", border: "#6272a4",
            green: "#50fa7b", orange: "#ffb86c", red: "#ff5555",
            magenta: "#ff79c6", cyan: "#8be9fd"
        },
        {
            name: "Material",
            bg: "#263238", surface: "#314549", fg: "#eeffff",
            accent: "#80cbc4", border: "#37474f",
            green: "#c3e88d", orange: "#ffcb6b", red: "#f07178",
            magenta: "#c792ea", cyan: "#89ddff"
        },
        {
            // base1 for text rather than the spec's base0 body tone:
            // fgStrong is customFg here and everything else recedes from
            // it, so starting at #839496 leaves the whole scale dim.
            name: "Solarized Dark",
            bg: "#002b36", surface: "#073642", fg: "#93a1a1",
            accent: "#268bd2", border: "#586e75",
            green: "#859900", orange: "#cb4b16", red: "#dc322f",
            magenta: "#d33682", cyan: "#2aa198"
        },
    ]
}
