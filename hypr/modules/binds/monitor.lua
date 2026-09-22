-- Rotate the focused monitor a quarter turn per press, wrapping back to
-- upright on the fourth.
--
-- hl.monitor identifies a display by `output` -- the same key
-- modules/monitors.lua sets one up with -- and the spec it takes is a
-- patch, so naming transform alone leaves mode, position and scale as
-- they were.

local vars = require("modules.vars")
local mainMod = vars.mainMod

-- Transforms 0-3 are the quarter turns: 0 upright, 1 = 90°, 2 = 180°,
-- 3 = 270°. 4-7 are the flipped variants of the same four, which nothing
-- here sets; landing on one puts the next press back at upright.
local ROTATIONS = { 0, 1, 2, 3 }

local function focused_monitor()
	for _, m in pairs(hl.get_monitors()) do
		if m.focused then
			return m
		end
	end
end

hl.bind(mainMod .. " + R", function()
	local m = focused_monitor()
	if m == nil then
		return
	end

	local next_index = (m.transform % #ROTATIONS) + 1
	hl.monitor({ output = m.name, transform = ROTATIONS[next_index] })
end)
