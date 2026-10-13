local vars = require("modules.vars")
local mainMod = vars.mainMod

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
