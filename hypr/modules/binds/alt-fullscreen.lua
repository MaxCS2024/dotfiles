-- Floating "zoom" toggle: pull the active window out of the layout, size it to
-- most of the monitor, and center it. Unlike real fullscreen this keeps the
-- window decorated and floating, so it stays reachable over other floaters.

local vars = require("modules.vars")
local mainMod = vars.mainMod

local ZOOM = 0.92

local function focused_monitor()
	for _, m in pairs(hl.get_monitors()) do
		if m.focused then
			return m
		end
	end
end

-- Monitor geometry is in physical pixels; dividing by scale gives the logical
-- size the compositor actually lays windows out in.
local function usable_area(m)
	local w = m.width / m.scale
	local h = m.height / m.scale

	-- reserved is the space claimed by bars and other layer surfaces.
	-- Subtracting it keeps the centered window from sliding under them.
	local r = m.reserved
	if type(r) == "table" and #r == 4 then
		w = w - r[1] - r[3]
		h = h - r[2] - r[4]
	end

	return w, h
end

hl.bind(mainMod .. " + F", function()
	local w = hl.get_active_window()
	if w == nil then
		return
	end

	if w.floating then
		hl.dispatch(hl.dsp.window.float({ action = "unset" }))
		return
	end

	local m = focused_monitor()
	if m == nil then
		return
	end

	local avail_w, avail_h = usable_area(m)

	hl.dispatch(hl.dsp.window.float({ action = "set" }))
	hl.dispatch(hl.dsp.window.resize({
		x = math.floor(avail_w * ZOOM),
		y = math.floor(avail_h * ZOOM),
	}))
	hl.dispatch(hl.dsp.window.center())
end)
