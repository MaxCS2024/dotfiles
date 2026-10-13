local vars = require("modules.vars")
local mainMod = vars.mainMod

hl.bind(mainMod .. " + W", hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("hyprctl kill"))
hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))

hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

local function siblings(win)
	local out = {}
	for _, other in ipairs(hl.get_workspace_windows(win.workspace)) do
		if other.address ~= win.address and not other.floating then
			out[#out + 1] = other
		end
	end
	return out
end

local function neighbourTowards(win, others, direction)
	for _, other in ipairs(others) do
		if direction == "up" and other.at.y < win.at.y then return true end
		if direction == "down" and other.at.y > win.at.y then return true end
		if direction == "left" and other.at.x < win.at.x then return true end
		if direction == "right" and other.at.x > win.at.x then return true end
	end
	return false
end

local function splitAlong(win, others, direction)
	local vertical = direction == "up" or direction == "down"
	for _, other in ipairs(others) do
		if vertical and other.at.y ~= win.at.y then return true end
		if not vertical and other.at.x ~= win.at.x then return true end
	end
	return false
end

local function moveOrStack(direction)
	return function()
		local win = hl.get_active_window()
		if not win then
			return
		end

		if win.floating then
			hl.dispatch(hl.dsp.window.move({ direction = direction }))
			return
		end

		local others = siblings(win)

		if neighbourTowards(win, others, direction) then
			hl.dispatch(hl.dsp.window.move({ direction = direction }))
			return
		end

		if #others == 0 then
			hl.dispatch(hl.dsp.window.move({ direction = direction }))
			return
		end

		if splitAlong(win, others, direction) then
			return
		end

		hl.dispatch(hl.dsp.layout("togglesplit"))

		local stacked = hl.get_active_window()
		if stacked and neighbourTowards(stacked, siblings(stacked), direction) then
			hl.dispatch(hl.dsp.window.move({ direction = direction }))
		end
	end
end

hl.bind(mainMod .. " + SHIFT + H", moveOrStack("left"))
hl.bind(mainMod .. " + SHIFT + J", moveOrStack("down"))
hl.bind(mainMod .. " + SHIFT + K", moveOrStack("up"))
hl.bind(mainMod .. " + SHIFT + L", moveOrStack("right"))
