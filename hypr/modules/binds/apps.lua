-- What opens things: the three launch binds, and the keys that drive
-- Quickshell's surfaces.
--
-- `global` is Hyprland's dispatcher for its own global-shortcuts-v1
-- protocol extension, so those binds press a shortcut the shell
-- registered rather than spawning a `qs ipc call` per keypress. The
-- string after the colon is an `appid:name` pair and must match the
-- shell's registration exactly (quickshell/main/services/Panels.qml);
-- a name nothing registered dispatches into nowhere, silently.
--
-- SUPER+Q and SUPER+COMMA are free: the dashboard and the settings
-- window that held them are gone, each replaced by a surface below.

local vars = require("modules.vars")
local features = require("modules.features")
local mainMod = vars.mainMod

-- Apps. What each one runs is the role's default (modules/defaults.lua):
-- the one set from Conf > Apps > Defaults or `relay default set`, else
-- the first candidate this machine has installed.
--
-- Asked on each press rather than captured at config load, so a default
-- that is uninstalled — from the app manager, say — hands over to the
-- next installed candidate straight away instead of at the next reload.
-- Answering is a few file opens and no process (see defaults.lua).
local defaults = require("modules.defaults")
local function run(role)
	return function()
		hl.exec_cmd(defaults.command(role))
	end
end
hl.bind(mainMod .. " + RETURN", run("terminal"))
hl.bind(mainMod .. " + E", run("file-manager"))
hl.bind(mainMod .. " + B", run("browser"))

-- hyprshutdown leaves the session the way the power menu does; Hyprland's
-- own exit is the fallback for a machine that has not installed it. Not
-- `uwsm stop`: that only ends a session uwsm started, and ly starts this
-- one. The same line as Hyprland's default config, and Theme.logoutCmd.
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))

-- Conf, the nested menu over everything this config can do
-- (quickshell/main/menu/ConfMenu.qml). omarchy puts its own menu on
-- SUPER+ALT+SPACE; that combo already toggles the bar here, and SPACE
-- alone was free.
hl.bind(mainMod .. " + SPACE", hl.dsp.global("quickshell:menu-toggle"))
hl.bind(mainMod .. " + P", hl.dsp.global("quickshell:launcher-toggle"))
hl.bind(mainMod .. " + ESCAPE", hl.dsp.global("quickshell:powermenu-toggle"))

-- The two right-edge rails are siblings in every sense -- same corner,
-- same geometry, same motion -- so notifications take the network rail's
-- letter with SHIFT on it rather than a free letter of its own. N is
-- where a rail lives here. Both are still a left click on the bar's own
-- module, and a right click there is still DND.
hl.bind(mainMod .. " + N", hl.dsp.global("quickshell:network-toggle"))
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.global("quickshell:notifications-toggle"))

-- cliphist's history with a search field over it. C is the letter every
-- other desktop spends on copy, which is the one thing this window is
-- for.
hl.bind(mainMod .. " + C", hl.dsp.global("quickshell:clipboard-toggle"))

-- Shifted, because plain SUPER+T is the float toggle in
-- modules/binds/window.lua and T is still the letter this is about.
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.global("quickshell:themes-toggle"))

-- Dictation: press once to start recording, again to stop, and voxtype
-- types what it heard into the focused window (through wtype). The daemon
-- is voxtype's own systemd user unit (`voxtype setup systemd`); the shell
-- shows a pill at the bottom of the screen while it is recording or
-- transcribing (quickshell/main/osd/VoxtypeOsd.qml). V for voice, and it
-- was free. Only while the dictation feature is on (`rack features`).
if features.on("dictation") then
	hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("voxtype record toggle"))
end

-- The bar itself: hide it, or focus it for arrow-key navigation
-- (Left/Right to move, Enter to activate, Escape to release). Focus is
-- shifted to leave plain SUPER+B to the browser.
hl.bind(mainMod .. " + ALT + SPACE", hl.dsp.global("quickshell:bar-toggle"))
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.global("quickshell:bar-focus"))
