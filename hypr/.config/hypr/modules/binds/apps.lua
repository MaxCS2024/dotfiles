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

-- fuzzel: a second press closes it.
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("pkill -x fuzzel || fuzzel"))

-- cliphist's history in fuzzel; the pick goes back on the clipboard.
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"))
hl.bind(mainMod .. " + COMMA", hl.dsp.global("quickshell:island-settings"))
hl.bind(mainMod .. " + ALT + W", hl.dsp.global("quickshell:island-wallpapers"))

if features.on("dictation") then
	hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("voxtype record toggle"))
end

hl.bind(mainMod .. " + ALT + SPACE", hl.dsp.global("quickshell:island-toggle"))
