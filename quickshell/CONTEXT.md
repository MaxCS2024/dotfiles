# Quickshell

The desktop shell: the bar, its cards and rails, popups, and the colours
they all share.

## Colour

**Palette**:
The complete set of named colours the shell draws with at any moment.
There is exactly one active palette.
_Avoid_: theme (that also covers sizes, fonts and motion), colour scheme

**Base palette**:
The few colours a palette is built from: background, foreground and
accent, plus optional surface, border and status colours.
_Avoid_: seed colours, custom colours

**Palette source**:
Where the base palette comes from: the wallpaper, a preset, or a
hand-edited palette.
_Avoid_: mode, provider

**Wallpaper mode**:
The palette source is the current wallpaper, via matugen, so the
palette changes when the wallpaper does.
_Avoid_: matugen mode, dynamic theme

**Custom mode**:
The palette source is a preset or a hand-edited palette, fixed
whatever the wallpaper.
_Avoid_: pinned theme, Fall

**Preset**:
A named, complete base palette the user can pick, such as Default or
Catppuccin Latte.
_Avoid_: theme, named palette

**Default preset**:
The preset used when wallpaper mode has no wallpaper colours yet. It
also fills any status colour a hand-edited palette leaves unset.
_Avoid_: fallback palette

**Ladder**:
The ordered steps of surface, line and text colours derived from a base
palette, moving away from the background for surfaces and towards it
for text.
_Avoid_: shades, scale

**Token**:
One named colour in the palette that a surface draws with, such as
`surface`, `fgMuted` or `accent`.
_Avoid_: variable, swatch

**Compositor colours**:
The pair of colours Hyprland draws window borders with. They always
come from the wallpaper, even in custom mode, so shell frames match the
window borders around them.
_Avoid_: border tokens, frame colours
