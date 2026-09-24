	-- modules/monitors.lua

hl.monitor({
	output = "eDP-1",
	-- The panel's own best mode rather than this laptop's numbers, so the
	-- same line suits a screen with another resolution or refresh rate.
	mode = "preferred",
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
