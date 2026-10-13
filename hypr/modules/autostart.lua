local features = require("modules.features")
local defaults = require("modules.defaults")

hl.on("hyprland.start", function ()
	hl.exec_cmd("qs -n -c dynamic-island")
	hl.exec_cmd("env QT_QPA_PLATFORMTHEME=gtk3 qs -c launcher")
	hl.exec_cmd("qs -c clipboard")
	hl.exec_cmd("qs -c settings")

	hl.exec_cmd("awww-daemon")
	hl.exec_cmd("wl-paste --watch cliphist store")
	hl.exec_cmd("hypridle")
	hl.exec_cmd("systemctl --user start hyprpolkitagent")
	hl.exec_cmd("hyprsunset")

	if features.on("dictation") then
		hl.exec_cmd("systemctl --user start voxtype.service")
	end

	local preload = defaults.preloadArgv()
	if preload ~= nil then
		hl.exec_cmd(table.concat(preload, " "))
	end
end)
