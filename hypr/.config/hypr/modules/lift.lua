-- A tiled window picked up by a drag (SUPER+drag or its own title bar)
-- shrinks to LIFT_SCALE of its tile, centred on the cursor, and tiles again
-- where it's let go. Hyprland on its own carries it at full size.
--
-- Hyprland lifts a tiled window by floating it, centred on the cursor, and
-- only then records that box as the drag's start; the drag keeps whatever
-- size it finds. Floating fires window.update_rules in between, so
-- resizing the window there makes the drag carry the smaller box. On
-- release Hyprland tiles it again by itself.

local LIFT_SCALE = 0.5

local floating = {} -- address → floating, as last seen
local lifted = nil -- the window shrunk for the drag in progress

for _, w in ipairs(hl.get_windows()) do
	floating[w.address] = w.floating
end

hl.on("window.open", function(w)
	floating[w.address] = w.floating
end)

hl.on("window.close", function(w)
	floating[w.address] = nil
end)

hl.on("window.update_rules", function(w)
	local address = w.address
	local was = floating[address]
	floating[address] = w.floating

	if not w.floating then
		if lifted == address then
			lifted = nil
		end
		return
	end

	-- Only a tiled window turning floating while a mouse button is held
	-- (keycode 0: see snap.lua).
	if was ~= false or lifted == address or not hl.is_key_down(0) then
		return
	end

	-- Hyprland centres a lifted window on the cursor; nothing else that
	-- floats a window does.
	local c = hl.get_cursor_pos()
	if not c or math.abs(w.at.x + w.size.x / 2 - c.x) > 2 or math.abs(w.at.y + w.size.y / 2 - c.y) > 2 then
		return
	end

	lifted = address
	local window = "address:" .. address
	local width = math.floor(w.size.x * LIFT_SCALE)
	local height = math.floor(w.size.y * LIFT_SCALE)
	hl.dispatch(hl.dsp.window.resize({ window = window, x = width, y = height }))
	hl.dispatch(hl.dsp.window.move({ window = window, x = math.floor(c.x - width / 2), y = math.floor(c.y - height / 2) }))
end)
