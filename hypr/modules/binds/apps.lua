local vars = require("modules.vars")
local features = require("modules.features")
local mainMod = vars.mainMod

local defaults = require("modules.defaults")
local function run(role)
	return function()
		hl.exec_cmd(defaults.command(role))
	end
end
hl.bind(mainMod .. " + RETURN", run("terminal"))
hl.bind(mainMod .. " + E", run("file-manager"))
hl.bind(mainMod .. " + B", run("browser"))

hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))

hl.bind(mainMod .. " + SPACE", hl.dsp.global("quickshell:menu-toggle"))
hl.bind(mainMod .. " + P", hl.dsp.global("quickshell:launcher-toggle"))
hl.bind(mainMod .. " + ESCAPE", hl.dsp.global("quickshell:powermenu-toggle"))

hl.bind(mainMod .. " + SHIFT + N", hl.dsp.global("quickshell:notifications-toggle"))
hl.bind(mainMod .. " + CTRL + W", hl.dsp.global("quickshell:network-toggle"))

hl.bind(mainMod .. " + C", hl.dsp.global("quickshell:clipboard-toggle"))

hl.bind(mainMod .. " + COMMA", hl.dsp.global("quickshell:island-settings"))

hl.bind(mainMod .. " + ALT + W", hl.dsp.global("quickshell:island-wallpapers"))

hl.bind(mainMod .. " + SHIFT + T", hl.dsp.global("quickshell:themes-toggle"))

if features.on("dictation") then
	hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("voxtype record toggle"))
end

hl.bind(mainMod .. " + ALT + SPACE", function()
	hl.dispatch(hl.dsp.global("quickshell:bar-toggle"))
	hl.dispatch(hl.dsp.global("quickshell:island-toggle"))
end)
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.global("quickshell:bar-focus"))
