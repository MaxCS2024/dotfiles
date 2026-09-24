--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

local suppressMaximizeRule = hl.window_rule({
	-- Ignore maximize requests from all apps. You'll probably like this.
	name = "suppress-maximize-events",
	match = { class = ".*" },

	suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
	-- Fix some dragging issues with XWayland
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},

	no_focus = true,
})

-- Quickshell's panels are layer surfaces, and Hyprland doesn't blur those
-- by default the way it does windows — they need an explicit rule. The
-- namespaces are set per-window in QML via WlrLayershell.namespace
-- ("quickshell:bar", "quickshell:launcher", ...).
--
-- Opt-in rather than opt-out: only the bar gets compositor blur. This
-- used to be a "^quickshell:.*" catch-all with a growing pile of
-- noblur-* rules bolted on for every panel that read wrong blurred
-- (quicksettings, powermenu, launcher, osd-wallpaper, osd-volume,
-- osd-brightness, systemsettings — and still missing several more, like
-- osd-mic, that nobody had gotten around to excluding yet). Scoping the
-- rule to just the bar means a brand-new panel is blurless by default
-- and has to opt in, instead of silently inheriting blur until someone
-- notices and adds another noblur-* entry here.
--
-- ignore_alpha skips blur behind pixels at or below this alpha, so that
-- the transparent margins around rounded popups don't render as blurry
-- rectangles. Keep it well under Theme.alphaBar/alphaPanel rather than
-- just below them, or compositing can push a panel's effective alpha
-- under the threshold and drop blur for the whole surface.
hl.layer_rule({
	name = "blur-bar",
	match = { namespace = "^quickshell:bar$" },
	blur = true,
	ignore_alpha = 0.2,
})

-- Note that blur-bar above does nothing at all as things stand:
-- decoration.blur.enabled is false in decorations.lua, and a per-layer
-- blur rule can only opt a surface into a blur the compositor is
-- actually doing. It is kept for the moment that setting is turned on.
--
-- A second rule sat here for the dashboard (SUPER+Q), a translucent slab
-- that wanted blur behind it. Both the panel and its keybind were
-- deleted on 2026-09-21 -- every card in it had a surface of its own
-- elsewhere, bar the two toggles that moved to the network rail.

-- The terminal (the default one, see defaults.lua) isn't a quickshell
-- layer surface — it's a normal toplevel, so it gets blur "for free" from
-- decoration.blur.enabled in decorations.lua (a compositor-wide setting,
-- no per-window rule needed) behind whatever transparency its own config
-- sets.

-- Hyprland-run windowrule
hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },

	move = "20 monitor_h-120",
	float = true,
})

-- Transient task windows: anything opened to be watched and then closed
-- — a package upgrade, `rack setup`, a one-off command from the Conf
-- menu — floats in the middle of the screen instead of being tiled into
-- the layout you were working in.
--
-- Keyed on app-id rather than on the terminal's class, so it isn't a
-- rule about foot: whatever is spawned asks for this id (quickshell's
-- side is Theme.floatAppId + services/Terminal.qml, which passes it with
-- whichever flag the chosen terminal takes), and anything else that can
-- name its own app-id gets the same treatment for free. Swapping the
-- terminal in Setup › Defaults changes nothing here.
--
-- Sized off the monitor rather than in pixels so it lands the same on
-- any screen. Note the arithmetic form: a plain `size = "60% 65%"` is
-- accepted here without complaint and then quietly does nothing — the
-- window keeps whatever size the client asked for (foot's own default,
-- 700x500). `monitor_w*0.6 monitor_h*0.65` is what actually applies,
-- the same dialect as move-hyprland-run's `monitor_h-120` above.
-- Verified on screen: 1152x702 at [384,207] on this 1920x1080 monitor.
--
-- `center` respects the reserved area, so it clears the bar on its own.
hl.window_rule({
	name = "float-task-window",
	match = { class = "^quickshell\\.float$" },

	float = true,
	center = true,
	size = "monitor_w*0.6 monitor_h*0.65",
})

-- TODO: quickshell launcher/quicksettings panels probably want to float.
-- Run `hyprctl clients` with the panel open to find its real class, then:
-- hl.window_rule({
-- 	name = "float-qs-launcher",
-- 	match = { class = "<real-class-here>" },
-- 	float = true,
-- })

-- Center dialogs that open already-floating, instead of letting them
-- land wherever the client asked for.
--
-- Wayland clients can't request a position at all, so Hyprland places
-- their floating windows itself — centered inside the monitor's
-- reserved area, which is already what we want. XWayland clients *can*,
-- and plenty of them ask for something useless: a plain X11 dialog here
-- opens at [0,0], i.e. tucked under the bar in the top-left corner.
-- This rule re-centers those.
--
-- The three match keys are all load-bearing:
--
--   float    — only windows the compositor has ALREADY floated by the
--              time map-time rules run, which is what "a popup" means
--              here. Note this never matches a window floated later by
--              SUPER+T; that one keeps its tiled geometry, which is
--              already clear of the bar, so it needs no help.
--   xwayland — Wayland floats are placed correctly already (see above),
--              so there's nothing to fix and no reason to risk it.
--   modal    — the one that keeps menus and tooltips out. Those are
--              override-redirect X11 surfaces that position themselves
--              deliberately and DO get matched by float+xwayland alone;
--              centering them would drag every dropdown to the middle
--              of the screen. They don't set the modal hint, so this
--              excludes them. Verified with an override-redirect probe
--              at +300+800: untouched with `modal`, yanked to the
--              center without it.
--
-- `center` respects the reserved area (a 300x225 dialog lands at
-- [810,445], not [810,427]), so dialogs clear the bar on their own.
--
-- This replaces a "float-below-bar" rule that used to live here:
-- `match = { float = true }`, `move = "window_x 27"`, `size =
-- "window_w*0.5 window_h*0.5"`. It was written for the SUPER+T case,
-- which as noted above it could never match; what it actually hit was
-- exactly these XWayland popups, keeping the x the client asked for and
-- slamming y to 27 — pinning every dialog to the top of the screen and
-- 8px INTO the bar, since the bar is 35px tall (bar.barHeight in
-- main/bar/Bar.qml; the 27 was a stale copy of Theme.barHeight, which
-- the bar itself no longer uses) — and halving its size on top of that.
--
-- If some specific popup still lands wrong, it's probably not modal:
-- run `hyprctl clients` with it open and add a class-scoped rule.
hl.window_rule({
	name = "center-floating-dialogs",
	match = { float = true, xwayland = true, modal = true },

	center = true,
})
