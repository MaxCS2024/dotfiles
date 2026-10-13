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
