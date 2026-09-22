	-- modules/monitors.lua

hl.monitor({
	output = "eDP-1",
	mode = "1920x1080@60",
	position = "0x0",
	scale = 1,
})

-- Fallback so an unplugged-and-replugged or unknown display still comes up.
hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = 1,
})
