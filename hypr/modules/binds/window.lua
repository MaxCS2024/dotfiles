local vars = require("modules.vars")
local mainMod = vars.mainMod

hl.bind(mainMod .. " + W", hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("hyprctl kill")) -- force-kill an unresponsive window
hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))

-- Move focus with mainMod + hjkl
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

-- Super+SHIFT+H/J/K/L move the focused window, and re-split the pair when it
-- is not arranged along the axis asked for.
--
-- dwindle splits a fresh pair along the wider axis, so on a 16:9 screen two
-- windows open side by side and up/down had nothing to act on: J and K were
-- dead keys until a third window arrived. They now flip the split first, so
-- Super+SHIFT+J puts the window under its neighbour and +K puts it over. H
-- and L do the same in reverse, which is what takes a stacked pair back to
-- side by side.
--
-- Each key only ever moves the window towards its own direction, never away.
-- That is the reason for the splitAlong check rather than just trying the
-- move: dwindle answers a move off the far end of a split by undoing the
-- split, so an unguarded J at the bottom of a stack would unstack the pair
-- it had just stacked, and the key would flip between the two arrangements
-- rather than mean one thing.
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

-- Is the pair already split along the axis this direction runs on? If it is,
-- and nothing lies that way, the window is simply at the far end.
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

		-- A floating window is not in the tiling tree: the move nudges it
		-- across the screen, and there is no split to flip.
		if win.floating then
			hl.dispatch(hl.dsp.window.move({ direction = direction }))
			return
		end

		local others = siblings(win)

		-- Something is already there, so the plain move is the whole gesture.
		if neighbourTowards(win, others, direction) then
			hl.dispatch(hl.dsp.window.move({ direction = direction }))
			return
		end

		-- Alone on the workspace: there is no split to flip, and asking for
		-- one only makes Hyprland warn. Hand the move over anyway, since on a
		-- multi-monitor setup it may still have somewhere to go.
		if #others == 0 then
			hl.dispatch(hl.dsp.window.move({ direction = direction }))
			return
		end

		-- Nothing that way, and the pair is already split along this axis:
		-- we are at the far end and there is nowhere further to go.
		if splitAlong(win, others, direction) then
			return
		end

		-- The neighbour is beside us rather than across this axis. Flip the
		-- split so that it is, then take the near end if that is where the
		-- flip left us; togglesplit keeps the pair in its existing order.
		hl.dispatch(hl.dsp.layout("togglesplit"))

		-- Re-read rather than reuse: the flip has moved everything.
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
