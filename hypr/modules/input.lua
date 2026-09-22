---------------
---- INPUT ----
---------------

hl.config({
	input = {
		kb_layout = "se",
		kb_variant = "",
		kb_model = "",
		kb_options = "",
		kb_rules = "",

		follow_mouse = 1,

		sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

		touchpad = {
			natural_scroll = true,
		},
	},
})

hl.gesture({
	fingers = 3,
	direction = "horizontal",
	action = "workspace",
})

-- Add real per-device overrides here once you know the device name:
-- run `hyprctl devices` to find it, then:
-- hl.device({ name = "<your-device-name>", sensitivity = -0.3 })
