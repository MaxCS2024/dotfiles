-- Snap layouts, as on Windows 11: drag a window to the bottom edge of a
-- screen and a bar of layouts slides up (the `snap` Quickshell config); let go
-- over a zone and the window floats into that part of the screen.
--
-- Hyprland has no drag event, so a timer looks for one: a mouse button held
-- while the active window moves exactly as far as the cursor, two ticks in
-- a row, at the same size (a resize moves it too, but grows it). While the
-- drag lasts the cursor goes to socket2 as `custom>>snap drag X Y`, and the
-- release as `custom>>snap drop ADDRESS`. The bar picks the zone and calls
-- snap_place() back through `hyprctl eval`.

local TICK_MS = 30

local prev = nil -- the last sample while a button is held
local steps = 0 -- ticks in a row the window followed the cursor
local dragging = nil -- address of the window being dragged
local lastX, lastY

local function send(msg)
	hl.dispatch(hl.dsp.event("snap " .. msg))
end

local function tick()
	-- Mouse buttons sit in Hyprland's pressed keys with keycode 0; keyboard
	-- keys always have a real one.
	if not hl.is_key_down(0) then
		if dragging then
			send("drop " .. dragging)
			dragging = nil
		end
		prev, steps = nil, 0
		return
	end

	local c = hl.get_cursor_pos()
	if not c then
		return
	end

	if dragging then
		local x, y = math.floor(c.x), math.floor(c.y)
		if x ~= lastX or y ~= lastY then
			lastX, lastY = x, y
			send("drag " .. x .. " " .. y)
		end
		return
	end

	local w = hl.get_active_window()
	if not w then
		prev, steps = nil, 0
		return
	end

	local s = { addr = w.address, wx = w.at.x, wy = w.at.y, ww = w.size.x, wh = w.size.y, cx = c.x, cy = c.y }
	if prev and prev.addr == s.addr and prev.ww == s.ww and prev.wh == s.wh then
		local dx, dy = s.cx - prev.cx, s.cy - prev.cy
		local follows = math.abs(dx) + math.abs(dy) >= 2
			and math.abs(s.wx - prev.wx - dx) <= 2
			and math.abs(s.wy - prev.wy - dy) <= 2
		steps = follows and steps + 1 or 0
	else
		steps = 0
	end
	prev = s

	if steps >= 2 then
		dragging, steps = s.addr, 0
		lastX, lastY = nil, nil
	end
end

-- Puts a window into a zone of a monitor, given as fractions of the area
-- windows tile in. The gaps match tiling: gaps_out at the screen's edges,
-- gaps_in on each side between two zones, and the border inside that.
function snap_place(address, monitor, fx, fy, fw, fh)
	local m = hl.get_monitor(monitor)
	if not m or not hl.get_window("address:" .. address) then
		return
	end

	local r = m.reserved
	local out = hl.get_config("general.gaps_out")
	local inner = hl.get_config("general.gaps_in")
	local border = hl.get_config("general.border_size")

	local ax = m.x + r.left + out.left
	local ay = m.y + r.top + out.top
	local aw = m.width / m.scale - r.left - r.right - out.left - out.right
	local ah = m.height / m.scale - r.top - r.bottom - out.top - out.bottom

	local x0, x1 = ax + fx * aw, ax + (fx + fw) * aw
	local y0, y1 = ay + fy * ah, ay + (fy + fh) * ah
	if fx > 0.001 then x0 = x0 + inner.left end
	if fx + fw < 0.999 then x1 = x1 - inner.right end
	if fy > 0.001 then y0 = y0 + inner.top end
	if fy + fh < 0.999 then y1 = y1 - inner.bottom end

	x0, y0 = math.floor(x0 + border), math.floor(y0 + border)
	x1, y1 = math.floor(x1 - border), math.floor(y1 - border)

	local window = "address:" .. address
	hl.dispatch(hl.dsp.window.float({ window = window, action = "enable" }))
	hl.dispatch(hl.dsp.window.resize({ window = window, x = x1 - x0, y = y1 - y0 }))
	hl.dispatch(hl.dsp.window.move({ window = window, x = x0, y = y0 }))
end

-- Kept in the module (and so in package.loaded), so it lives on.
return { timer = hl.timer(tick, { timeout = TICK_MS, type = "repeat" }) }
