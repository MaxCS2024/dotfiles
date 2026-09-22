-- Zen toggle: collapse the desktop's chrome to nothing and back.
--
-- On: gaps_in/gaps_out go to zero, borders go to zero width, and both border
-- gradients go fully transparent (so anything that forces a border_size of its
-- own -- a window or workspace rule -- still draws nothing visible).
-- Off: every value is put back exactly as it was.
--
-- The previous values are read from the live config at toggle time rather than
-- hardcoded, because modules/colors.lua derives the border gradients from
-- matugen and they change with the wallpaper.

local vars = require("modules.vars")
local mainMod = vars.mainMod

local TRANSPARENT = { colors = { "0x00000000" } }

-- nil while chrome is showing; the captured values while zen is on.
local saved = nil

local function capture()
	return {
		gaps_in = hl.get_config("general.gaps_in"),
		gaps_out = hl.get_config("general.gaps_out"),
		border_size = hl.get_config("general.border_size"),
		active_border = hl.get_config("general.col.active_border"),
		inactive_border = hl.get_config("general.col.inactive_border"),
	}
end

local function apply(state)
	hl.config({
		general = {
			gaps_in = state.gaps_in,
			gaps_out = state.gaps_out,
			border_size = state.border_size,
			col = {
				active_border = state.active_border,
				inactive_border = state.inactive_border,
			},
		},
	})
end

-- Shown as an OSD rather than a notification: this is a transient state
-- readout like volume or caps lock, not something worth a popup that waits to
-- be dismissed. It is the same bottom-rise box those use --
-- quickshell/main/osd/ZenOsd.qml, which owns nothing but the drawing; zen's
-- state lives here, so the toggle pushes it over IPC on every press.
--
-- `qs` needs no PATH fixup, and since modules/env.lua puts ~/.local/bin on
-- the bind PATH neither does `relay`: qs is
-- in /usr/bin, which is on the PATH Hyprland hands to `sh -c` already.
local function osd(state)
	hl.exec_cmd("qs -c main ipc call osd-zen " .. state)
end

local function toggle()
	if saved then
		apply(saved)
		saved = nil
		osd("off")
		return
	end

	saved = capture()
	apply({
		gaps_in = 0,
		gaps_out = 0,
		border_size = 0,
		active_border = TRANSPARENT,
		inactive_border = TRANSPARENT,
	})
	osd("on")
end

hl.bind(mainMod .. " + SHIFT + F", toggle)

-- A reload re-reads decorations.lua, which restores the chrome behind our back.
-- Theme.qml fires `hyprctl reload` on every wallpaper change, so this is a
-- normal occurrence, not an edge case: drop the stale snapshot so the next
-- press turns zen on rather than "restoring" values that are already live.
hl.on("config.reloaded", function()
	saved = nil
end)

-- Returned so the toggle can be driven from outside a keypress, e.g.
-- `hyprctl eval 'require("modules.binds.zen").toggle()'`.
return { toggle = toggle }
