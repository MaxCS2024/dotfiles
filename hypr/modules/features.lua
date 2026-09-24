-- Which optional features this machine has turned on.
--
-- `rack features` (rack/lib/features.sh) writes the choices to
-- ~/.config/rack/features.conf, one "name on|off" per line, and reloads
-- Hyprland afterwards, so a bind that belongs to a feature comes or goes
-- with it. quickshell/main/services/Features.qml reads the same file.
--
-- A feature with no line, or no file at all, is on: a machine that has
-- never run the picker keeps every bind it had before features existed.
--
-- Read on every call rather than once at require time, so nothing cached
-- can outlive the file; it is a handful of lines, read a handful of times
-- per config load.

local M = {}

local function path()
	local base = os.getenv("XDG_CONFIG_HOME")
	if not base or base == "" then
		base = (os.getenv("HOME") or "") .. "/.config"
	end
	return base .. "/rack/features.conf"
end

function M.on(name)
	local f = io.open(path(), "r")
	if not f then
		return true
	end
	local state = nil
	for line in f:lines() do
		local key, value = line:match("^(%S+)%s+(%S+)")
		if key == name then
			state = value
		end
	end
	f:close()
	return state ~= "off"
end

return M
