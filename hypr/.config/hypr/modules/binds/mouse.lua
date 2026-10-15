local vars = require("modules.vars")
local mainMod = vars.mainMod

-- A tiled window picked up with SUPER+drag shrinks to this share of its
-- tile, centred on the cursor, and tiles again where it's let go (next to
-- the window under the cursor, as a plain drop does). Hyprland on its own
-- carries it at full size.
local LIFT_SCALE = 0.6

-- The tiled window under the cursor, or nil when a floating or fullscreen
-- window is in the way, or a special workspace is open: those drag as usual.
local function tiledUnderCursor()
	local c = hl.get_cursor_pos()
	local m = hl.get_monitor_at_cursor()
	if not c or not m or m.active_special_workspace or not m.active_workspace then
		return nil
	end

	local found = nil
	for _, w in ipairs(hl.get_windows()) do
		if w.mapped and not w.hidden and w.workspace and w.workspace.id == m.active_workspace.id
			and c.x >= w.at.x and c.x < w.at.x + w.size.x
			and c.y >= w.at.y and c.y < w.at.y + w.size.y then
			if w.floating or w.fullscreen ~= 0 or w.group then
				return nil
			end
			found = w
		end
	end
	return found
end

-- The drag dispatcher runs this bind again on release, so each call
-- alternates between press and release.
local pressed = false
local lifted = nil -- address of the window floated for this drag

hl.bind(mainMod .. " + mouse:272", function()
	pressed = not pressed

	if pressed then
		local w = tiledUnderCursor()
		if w then
			local c = hl.get_cursor_pos()
			local window = "address:" .. w.address
			local width = math.floor(w.size.x * LIFT_SCALE)
			local height = math.floor(w.size.y * LIFT_SCALE)
			hl.dispatch(hl.dsp.window.float({ window = window, action = "enable" }))
			hl.dispatch(hl.dsp.window.resize({ window = window, x = width, y = height }))
			hl.dispatch(hl.dsp.window.move({ window = window, x = math.floor(c.x - width / 2), y = math.floor(c.y - height / 2) }))
			lifted = w.address
		end
		-- Returned, so the click is consumed or passed on as before.
		return hl.dispatch(hl.dsp.window.drag())
	end

	local result = hl.dispatch(hl.dsp.window.drag())
	if lifted then
		local w = hl.get_window("address:" .. lifted)
		if w and w.floating then
			hl.dispatch(hl.dsp.window.float({ window = "address:" .. lifted, action = "disable" }))
		end
		lifted = nil
	end
	return result
end)

hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
