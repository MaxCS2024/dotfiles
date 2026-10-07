# Quickshell style guide

Read this before creating or changing anything visual under `quickshell/`.
These rules are binding. If a design you're about to write breaks one, change
the design, not the rule. If you think a rule is wrong, ask the user first.

Colour tokens live only in `main/theme/Appearance.qml`; `main/config/Theme.qml`
holds sizes, fonts, radii and motion and has no colours at all. The ladder is
derived in `main/theme/palette.js` (tested by `main/tests/run palette`). The
vocabulary (palette, base palette, ladder, token, …) is in `CONTEXT.md`.

## 1. Borders

This is the most-repeated mistake in this repo, so it comes first.

- **Don't show state with a border.** Active, occupied, selected, focused and
  urgent are shown with **fill** or **text colour**, never a ring or outline.
- **Never use a coloured border.** No `accent`, `fg*`, `green`/`orange`/`red`,
  and no `Qt.rgba(accent…, 0.5)`-style translucent accent ring. These always
  end up brighter than the fill they surround and brighter than every other
  border on the bar, so the item looks like it's glowing.
- A border is allowed only as a neutral structural edge (panels, dropdowns,
  an "off" toggle): `border.width: 1`, `border.color: Appearance.border` (or
  `Appearance.separator` for dividers). Nothing else.
- A border must never be more visible than the fill inside it, or than the
  borders already used elsewhere on screen. If you have to check, it's too
  bright; remove it.
- Don't combine a fill *and* a border to mean the same thing. Pick one
  (almost always the fill).

## 2. Colour

- Colours come from `Appearance.*` only. No hex literals, no `Qt.lighter`/
  `Qt.darker` of your own when a token exists. A colour the palette lacks is
  added as a token in `palette.js` (with a test), not derived at the call
  site.
- **Don't hand-mix accent into a surface** (e.g. 40% accent + 60% surface),
  and don't lay a translucent accent over one either. It turns muddy on warm
  accents. To show a secondary state, move one step up the elevation ladder
  instead. A selected row, chip or button is `Appearance.selected`.
- Elevation ladder, lowest to highest:
  `sunken` → `bar` → `surface` → `surfaceAlt` → `hover` → `hoverStrong` →
  `selected`. `sunken` is for a track set into a surface.
  Move by steps; don't invent in-between shades.
- **Accent marks one thing per group**: the current or selected item. If
  several items in a cluster are accent-coloured, none of them stands out.
- Text on an accent fill uses `Appearance.bar`.

## 3. Text contrast

- Anything the user needs to read uses `fgStrong`, `fg`, `fgSoft` or `fgMuted`.
- `fgFaint`, `fgDim` and `disabled` are **only** for disabled or placeholder
  content. Using `fgDim` for an ordinary resting state (e.g. empty
  workspaces) makes it look switched off.

## 4. Showing states in a group of items

For clusters like workspaces or tabs, each state needs its own look at a
glance, and colour alone isn't enough:

| State              | Fill            | Text/glyph        | Shape            |
|--------------------|-----------------|-------------------|------------------|
| current / selected | `accent`        | `Appearance.bar`  | normal           |
| has content        | `surfaceAlt`    | `accent` or `fg`  | normal           |
| empty / resting    | none            | `fgMuted`         | normal           |
| urgent             | unchanged       | `red` (pulsing)   | normal           |
| hover              | HoverPill layer | unchanged         | unchanged        |

Leave enough space between neighbours to tell them apart (`Theme.space2`,
8px, on the bar).

## 5. Shape and size

- Bar items: `Theme.barItemHeight` (24px) tall, a fixed height rather than
  the content's plus a margin, padded `Theme.barItemPadX` (12px) each side,
  near-square corners (`radius: Theme.radius`, the 2px corner-radius
  setting; fully round pills were dropped 2026-10-02), glyphs at
  `Theme.iconSize`. Only dots and badges stay round.
- The bar is a row of floating islands (`main/bar/BarIsland.qml`), not
  one strip: each island is 32px (24 + `space1` each side) in
  `Appearance.bar` with `Theme.radius` corners, `space2` from the screen
  edge, `space4` from its sides, and `space2` from the next island.
  Modules get an island each unless `islandGroups` in `Bar.qml` puts
  them together (volume, network, battery); that island is always
  the last in the right row, nearest the screen edge. The window between
  islands is clear. Rows are centred exactly; don't nudge them with an
  offset. A module doesn't draw its own track or plate behind itself;
  the island is that.
- Buttons, cards and panels inside dropdowns: `Theme.radius`
  (`radiusMedium`/`radiusLarge` where already in use). No other literal radii.
- New bar items build on `BarButton.qml` and `HoverPill.qml` instead of
  drawing their own background.
- **Everything sits on a 4px grid.** Spacing, margins and padding use the
  scale in `Theme.qml` (`space1` = 4, `space2` = 8, `space3` = 12,
  `space4` = 16, `space5` = 20, `space6` = 24, `space8` = 32,
  `space10` = 40), never a literal. Card padding inside a bar dropdown is
  `Theme.cardPadding`. Heights and widths of controls, rows and icon
  buttons are multiples of 4 (24, 28, 32, 40, …). If a value falls between
  two steps, take the nearer step; don't add in-between tokens.
- Allowed off-grid values: 1–2px hairlines (borders, dividers), a radius of `height / 2` on a dot or badge, and negative margins that only enlarge
  an invisible hit area. A repeating grid may use a hairline gap if the
  cell plus the gap is a multiple of 4 (the calendar's 34 + 2).

## 6. Type

- `font.family: Theme.font` and sizes from `Theme.font*`
  (`fontSmall`, `fontMedium`, …). No literal pixel sizes.

## 7. Motion

- Colour/size changes: `Behavior` with `Theme.animFast` and
  `Theme.easingStandard`. Panels use `Theme.animPanel`.
- An animated colour that fades to or from nothing uses
  `Appearance.clear(<the other colour>)`, never `"transparent"`.
  `"transparent"` is transparent *black*, so the fade passes through a dark
  grey and the item dips darker than where it started.
- **Never animate a size inside a layout** (`implicitWidth` in a
  RowLayout, etc.). It re-lays out the row every frame, and pixel rounding
  makes the neighbours jitter. Animate `x`/`y`/`opacity`/`scale` of a single
  item instead.
- Movement uses decelerating easing (`Theme.easingDecel`) and stays short
  (≈ 120–160ms). An ease-in-out start reads as lag. Exception: the power
  menu's tiles each use a `SpringAnimation` (≈ 300ms, slight overshoot)
  on their own copy of the selection, which drives their height. The
  springs start one after another, 40ms per place outward from the new
  selection. A short ease there looked stiff, and so did one shared
  spring that moved every tile on the same frame.
- A moving highlight (e.g. the sliding workspace indicator) goes **on top**
  of the items and carries a clipped copy of their labels in the on-accent
  colour (see `main/bar/Workspaces.qml`). Don't time label colour changes to
  match the slide; they never line up, and labels vanish mid-slide.
- To check an animation, record it instead of taking screenshots:
  `wf-recorder -o <mon> -g "0,0 WxH" -r 60 -f rec.mp4`, then
  `ffmpeg -i rec.mp4 -vf mpdecimate -fps_mode vfr fr%02d.png`.
  A screenshot takes about as long as a whole 140ms animation.
- Any looping animation must stop while the bar is hidden
  (`running: … && (!barWindow || barWindow.shown)`).

## 8. Don't add decoration

No glows, gradients, drop shadows, outline rings or double indicators (a
fill *plus* a dot *plus* a border for one state). One visual signal per state.

## 9. Check before reporting

- Quickshell hot-reloads on save. **Don't** launch another `qs -c main`;
  it puts a second bar on screen. Check the log with `qs -c main log`.
- Edit files in place (Edit tool, or rewrite the file). `sed -i` replaces
  the file, and the reload watcher stops seeing it. After a failed load,
  the watcher may stop reloading at all; restart the shell once with
  `kill <pid>` then `hyprctl dispatch 'hl.dsp.exec_cmd("env QT_QPA_PLATFORMTHEME=gtk3 qs -c main")'`
  (the same command autostart uses). Afterwards, `qs list --all` must show
  exactly one instance.
- Take a screenshot and look at the result before calling it done:
  `grim -o "$(hyprctl monitors -j | jq -r '.[0].name')" out.png` then crop
  with `magick out.png -crop WxH+X+Y -scale 400% crop.png`.
- Compare the new element against its neighbours on the bar: similar weight,
  no brighter edges, same corner rounding.

## Mistakes seen so far

Add to this list whenever the user rejects a visual pattern.

- 2026-09-23: accent-tinted 1px outline on occupied workspace chips looked
  brighter than every other border on the bar (see §1).
- 2026-09-23: empty workspaces in `fgDim` looked switched off (see §3).
- 2026-09-23: 40% accent mixed into the surface for occupied chips came out
  muddy brown (see §2).
- 2026-09-23: widening the current workspace pill with an animation made the
  slide choppy (whole row re-laid out every frame) and slow (ease-in-out).
  See §7.
- 2026-09-23: a `fgStrong` ring on the calendar's today cell when it was
  also the selection (i.e. every time the calendar opened). A state that
  "has no fill left" doesn't get a border; drop the extra mark (see §1).
- 2026-09-23: hovering an occupied workspace chip went fill → darker →
  hover colour, because HoverPill faded from `"transparent"` (see §7).
- 2026-09-24: clicking a volume/mic slider drew the accent focus ring,
  because a click gives the slider focus. Hiding it only for clicks wasn't
  enough, and the user then had focus rings removed everywhere (sliders,
  tiles, power menu, lock screen) along with accent borders on focused
  text fields. There is no focus ring component; don't add one back (see §1).
- 2026-09-24: accent border on "on" quick-settings tiles and a tone-coloured
  border on hovered/selected power menu tiles; both now keep their neutral
  edge and show state with fill and text colour only (see §1).
- 2026-09-27: `SlabStyle.tintSelected` (accent at 45% over the surface) was
  the shell's selected fill in ~20 places, and the power menu tiles mixed
  accent/red into theirs plus a coloured rule and a scale-up. All replaced
  by ladder steps (`selected`, `hover`, `hoverStrong`); the accent stays in
  text and glyphs (see §2, §8).
- 2026-10-02: square (0px) outer corners on the dropdown cards, to match
  the Hyprland windows. The user kept the 2px `Theme.radius` cards
  instead; the cards and the bar's pills share one radius (see §5).
- 2026-10-02: the power menu's portrait tiles slid in 120ms OutCubic with
  fill/glyph colours on their own 120ms fade. The user found it stiff and
  said it "ruins the look". Now a spring drives the slide and the colours
  follow the same value (see §7).
- 2026-10-06: the power menu's slab (the sunken panel behind the tiles)
  and its sliding scale, where every tile shrank with its distance from
  the selection. The tiles now stand on the dimmed backdrop at one size
  in one row, and the selected or hovered tile grows taller, centred on
  the row's line. Its neighbours grow a little too, so the row swells
  like a wave. The distance shading (each tile one ladder step darker
  per place from the selection) went the same day; resting tiles share
  one fill.
- 2026-10-06: the power menu's wave on one shared spring. Every tile
  reacted on the same frame, which the user found stiff and unnatural.
  Each tile now has its own spring, started with a 40ms-per-place
  ripple outward from the new selection (see §7).
