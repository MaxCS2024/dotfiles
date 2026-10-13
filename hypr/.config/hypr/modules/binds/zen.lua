local vars = require("modules.vars")
local mainMod = vars.mainMod

local TRANSPARENT = { colors = { "0x00000000" } }

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

hl.on("config.reloaded", function()
	saved = nil
end)

return { toggle = toggle }
