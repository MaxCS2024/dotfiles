local suppressMaximizeRule = hl.window_rule({
	name = "suppress-maximize-events",
	match = { class = ".*" },

	suppress_event = "maximize",
})

hl.window_rule({
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},

	no_focus = true,
})

hl.layer_rule({
	name = "blur-bar",
	match = { namespace = "^quickshell:bar$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },

	move = "20 monitor_h-120",
	float = true,
})

hl.window_rule({
	name = "float-task-window",
	match = { class = "^quickshell\\.float$" },

	float = true,
	center = true,
	size = "monitor_w*0.6 monitor_h*0.65",
})

hl.window_rule({
	name = "float-island-settings",
	match = { class = "^org\\.quickshell$", title = "^Settings$" },

	float = true,
	center = true,
})

hl.window_rule({
	name = "center-floating-dialogs",
	match = { float = true, xwayland = true, modal = true },

	center = true,
})

hl.window_rule({
	name = "float-calculator",
	match = { class = "^org\\.gnome\\.Calculator$" },

	float = true,
	center = true,
	size = "1 1",
})
