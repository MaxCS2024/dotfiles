# Quickshell style guide

Read this before creating or changing anything visual under `quickshell/`.
These rules are binding. If a design you're about to write breaks one, change
the design, not the rule. If you think a rule is wrong, ask the user first.

Each config's own brief can override a rule here (the dynamic island's
white-on-black look, its round pills); its `AGENTS.md` says where. The old
bar these rules grew up on (`quickshell/main`) was removed on 2026-10-13;
the lessons it taught stay below.

## 1. Borders

This is the most-repeated mistake in this repo, so it comes first.

- **Don't show state with a border.** Active, occupied, selected, focused and
  urgent are shown with **fill** or **text colour**, never a ring or outline.
- **Never use a coloured border**, solid or translucent. It always ends up
  brighter than the fill it surrounds and brighter than every other edge on
  screen, so the item looks like it's glowing.
- A border is allowed only as a neutral structural edge (a panel, a dropdown,
  an "off" toggle): 1px, in the config's quietest edge colour. Nothing else.
- A border must never be more visible than the fill inside it, or than the
  borders already used elsewhere on screen. If you have to check, it's too
  bright; remove it.
- Don't combine a fill *and* a border to mean the same thing. Pick one
  (almost always the fill).
- No focus rings. A click gives a control focus, and a ring on every click
  was rejected (2026-09-24); keyboard focus shows as a fill.

## 2. Colour

- Colours come from the config's own named set (the island's white at fixed
  opacities, a theme file), never ad-hoc literals scattered through a file.
- **Don't mix an accent into a surface**, and don't lay a translucent accent
  over one. It turns muddy. To show a secondary state, move one step up in
  lightness instead (a hover fill, then a selected fill), and don't invent
  in-between shades.
- **An accent marks one thing per group**: the current or selected item. If
  several items in a cluster are accented, none of them stands out.

## 3. Text contrast

- Anything the user needs to read uses a full or near-full text colour.
- Faint and dim colours are **only** for disabled or placeholder content.
  Using them for an ordinary resting state makes it look switched off.

## 4. Showing states in a group of items

For a cluster (tabs, segments, a list), each state needs its own look at a
glance, and colour alone isn't enough: current/selected gets the strongest
fill, content a quieter one, empty none, and hover a light layer that
leaves the rest alone. Leave at least 8px between neighbours.

## 5. Shape and size

- **Everything sits on a 4px grid.** Spacing, margins, padding, and the
  heights and widths of controls, rows and icon buttons are multiples of 4
  (24, 28, 32, 40, …). If a value falls between two steps, take the nearer.
- Allowed off-grid values: 1–2px hairlines, a radius of `height / 2` on a
  dot, badge or pill, and negative margins that only enlarge an invisible
  hit area.
- One corner radius per kind of thing; no other literal radii.
- A part doesn't draw its own plate behind itself when its container
  already is one.

## 6. Type

- One font family and a small set of sizes per config, named once. No
  scattered literal pixel sizes.

## 7. Motion

- An animated colour that fades to or from nothing fades to the same colour
  at zero opacity, never `"transparent"`: that is transparent *black*, so
  the fade passes through a dark grey and the item dips darker than where it
  started.
- **Never animate a size inside a layout** (`implicitWidth` in a RowLayout,
  etc.). It re-lays out the row every frame, and pixel rounding makes the
  neighbours jitter. Animate `x`/`y`/`opacity`/`scale` of a single item.
- Movement uses decelerating easing and stays short (≈ 120–160ms). An
  ease-in-out start reads as lag. Where a short ease looks stiff, a spring
  with a slight overshoot, started per item rather than all on one frame,
  reads as natural (learnt on the old bar's power menu).
- A moving highlight goes **on top** of the items and carries a clipped copy
  of their labels. Don't time label colour changes to match the slide; they
  never line up, and labels vanish mid-slide.
- To check an animation, record it instead of taking screenshots:
  `wf-recorder -o <mon> -g "0,0 WxH" -r 60 -f rec.mp4`, then
  `ffmpeg -i rec.mp4 -vf mpdecimate -fps_mode vfr fr%02d.png`.
  A screenshot takes about as long as a whole 140ms animation.
- Any looping animation must stop while its window is hidden.

## 8. Don't add decoration

No glows, gradients, drop shadows, outline rings or double indicators (a
fill *plus* a dot *plus* a border for one state). One visual signal per state.

## 9. Check before reporting

- Quickshell hot-reloads on save. **Don't** launch a second copy of a
  running config (`qs -n` refuses one); check the log with
  `qs -c <config> log`.
- Edit files in place. `sed -i` replaces the file, and the reload watcher
  stops seeing it; after a failed load it may stop reloading at all, so
  restart the config once (`qs kill -c <config>`, then start it the way
  autostart does). Afterwards `qs list --all` must show exactly one copy.
- Take a screenshot and look at the result before calling it done:
  `grim -o "$(hyprctl monitors -j | jq -r '.[0].name')" out.png` then crop
  with `magick out.png -crop WxH+X+Y -scale 400% crop.png`.
- Compare the new element against its neighbours: similar weight, no
  brighter edges, same corner rounding.

## Mistakes seen so far

Add to this list whenever the user rejects a visual pattern. (The early
ones were on the old bar.)

- 2026-09-23: an accent-tinted 1px outline on occupied workspace chips
  looked brighter than every other border (see §1).
- 2026-09-23: empty workspaces in a dim colour looked switched off (see §3).
- 2026-09-23: 40% accent mixed into the surface came out muddy brown (§2).
- 2026-09-23: widening the current workspace pill with an animation made the
  slide choppy (whole row re-laid out every frame) and slow (ease-in-out).
  See §7.
- 2026-09-23: a ring on the calendar's today cell when it was also the
  selection. A state that "has no fill left" doesn't get a border; drop the
  extra mark (see §1).
- 2026-09-23: a hover layer faded from `"transparent"`, so hovering went
  fill → darker → hover colour (see §7).
- 2026-09-24: a click drew an accent focus ring on sliders; the user had
  focus rings removed everywhere, along with accent borders on focused text
  fields (see §1).
- 2026-09-24: accent borders on "on" toggle tiles and tone-coloured borders
  on hovered menu tiles; state goes in fill and text colour only (see §1).
- 2026-09-27: an accent-over-surface "selected" tint in ~20 places, plus
  coloured rules and a scale-up on menu tiles; replaced by plain lighter
  fills, the accent kept to text and glyphs (see §2, §8).
- 2026-10-02: square (0px) outer corners on dropdown cards to match the
  windows; the user kept one shared small radius (see §5).
- 2026-10-02 and 2026-10-06: menu tiles sliding on a short ease, then on one
  shared spring, both looked stiff; one spring per tile, started 40ms apart
  outward from the selection, felt right (see §7).
- 2026-10-06: a sunken slab behind menu tiles, and per-tile distance
  shading; both removed for one shared resting fill (see §8).
