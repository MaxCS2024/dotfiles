local M = {}

local function readPalette()
	local home = os.getenv("HOME")
	if not home then
		return nil
	end

	local f = io.open(home .. "/.cache/matugen/colors.json", "r")
	if not f then
		return nil
	end

	local text = f:read("*a")
	f:close()

	local palette = {}
	for key, hex in text:gmatch('"([%w_]+)"%s*:%s*"(#%x%x%x%x%x%x)"') do
		palette[key] = hex
	end

	if palette.background and palette.color2 and palette.color4 then
		return palette
	end
	return nil
end

local function rgba(hex, alpha)
	return "rgba(" .. (hex:gsub("#", "")) .. alpha .. ")"
end

local palette = readPalette()

M.matugenActive = palette ~= nil

if palette then
	M.activeBorder = { rgba(palette.color4, "ee"), rgba(palette.color2, "ee") }
	M.inactiveBorder = rgba(palette.color8 or palette.color0, "aa")
else
	M.activeBorder = { "rgba(33ccffee)", "rgba(00ff99ee)" }
	M.inactiveBorder = "rgba(595959aa)"
end

return M
