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
accent, plus optional surface, border and status colours, and the
magenta and cyan a terminal needs.
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

**App colours**:
The palette written out as the files other apps read their colours
from — the terminals and GTK — so they match the shell in either mode.
_Avoid_: terminal theme, matugen colours

**Compositor colours**:
The pair of colours Hyprland draws window borders with. They always
come from the wallpaper, even in custom mode, so shell frames match the
window borders around them.
_Avoid_: border tokens, frame colours

## Default apps

**Role**:
A job on this desktop that one app is picked to do: terminal, editor,
browser or file manager.
_Avoid_: app type, category

**Candidate**:
An app that can fill a role, in a fixed ranked order per role.
_Avoid_: option, choice

**Default**:
The app a role resolves to: the one the user set, else the first
installed candidate, else the first candidate. It is what the role's
keybind runs. The user can set a candidate or a custom command.
_Avoid_: current app, preferred app

**Custom command**:
A default the user wrote by hand rather than picked from the
candidates. It runs as written, and nothing about the app it names is
assumed.
_Avoid_: raw command, override

**Handler**:
The app the XDG database opens a role's files or links with. Setting a
default rewrites the handler to match; when the two differ, the default
is the answer.
_Avoid_: XDG default, mime default

## Packages

**Source**:
Where a package comes from: the official repositories (pacman), the AUR,
or Flathub. One package name belongs to one source.
_Avoid_: backend, manager, repo
