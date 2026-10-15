# Snap layouts

Windows 11's snap layouts for Hyprland. Drag a window to the top edge of a
screen and a bar of six layouts drops down under the island. Let go over a
zone and the window floats into that part of the screen.

Read `../STYLE.md` before any visual change. Record every new user decision
under Decisions.

## Scope

- Independent of the dynamic island: its own config (`qs -c snap`, started
  at login by `hypr/modules/autostart.lua`), and it works with the island
  stopped. It only sits under the island's pill.
- It places the one window being dragged. No snap assist (filling the other
  zones with other windows) and no edge or corner snapping yet.

## How it works

- `hypr/.config/hypr/modules/snap.lua` finds the drag, because Hyprland has
  no drag event. A 30ms timer checks `hl.is_key_down(0)`: mouse buttons sit
  in Hyprland's pressed keys with keycode 0, keyboard keys never do. While
  a button is held, the active window moving exactly as far as the cursor
  for two ticks in a row, at the same size, counts as a drag. This covers
  SUPER+drag and dragging a client-side title bar, for tiled and floating
  windows alike.
- During the drag it sends `custom>>snap drag X Y` (global logical
  coordinates) on socket2 whenever the cursor moves, and on release
  `custom>>snap drop ADDRESS`. `WindowDrag.qml` reads them.
- `SnapBar.qml` (one per screen) opens when the cursor is within 4px of the
  top edge, stays while it is no more than 32px below the bar, and closes
  when the cursor leaves that or the screen. The bar never takes input; the
  hovered zone comes from the cursor position.
- On a drop over a zone, the bar runs `hyprctl eval 'snap_place(...)'`.
  `snap_place` (in snap.lua) floats the window and sets its size and
  position from the monitor's reserved area, `gaps_out` at the screen's
  edges, `gaps_in` between zones and the border inside that, so a snapped
  window lines up with tiled ones. A tiled window dropped this way is
  re-tiled by Hyprland first, then floated.

## Look

- The island's look: a black plate, zones white at 24%, the hovered zone
  solid white (120ms colour ease). No text, no borders.
- Plate: 12px padding, radius 16 (the zones' 4 plus the padding), under the
  island's pill (top margin 31) and slid down 8px as it opens (140ms,
  OutCubic, with a fade).
- Tiles: 96 × 56, 12px apart, zones 4px apart. The gaps between tiles count
  towards the nearer tile, so the bar has no dead spots.
- Layouts, in Windows 11's order: halves; 2/3 + 1/3; thirds; half + two
  quarters; quarters; 1/4 + 1/2 + 1/4.

## Testing

`wtype` can't drag, so the drag watcher needs a real mouse. The bar and the
placement can be driven by hand with the same events:

```sh
hyprctl dispatch 'hl.dsp.event("snap drag 960 2")'     # opens the bar
hyprctl dispatch 'hl.dsp.event("snap drag 1144 61")'   # hovers a zone
hyprctl dispatch 'hl.dsp.event("snap drop 0x…")'       # places that window
```

## Decisions

- 2026-10-15: built as its own config, independent of the island (the
  user's request). Dropping places the window by floating it; the bar sits
  under the island's pill rather than over it.
