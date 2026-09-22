-- Palette shared by the Hyprland side of the desktop.
--
-- Reads the same ~/.cache/matugen/colors.json that quickshell/config/Theme.qml
-- watches, so borders and shell surfaces are always derived from one
-- source. Anything that writes that file (matugen) re-themes both.
--
-- Hyprland only re-reads its config on reload, so a fresh wallpaper needs
-- `hyprctl reload` afterwards — Theme.qml fires that when the file changes.
--
-- If the file is missing or unparseable, `matugenActive` stays false and the
-- literals below are used, mirroring Theme.qml's fallback behaviour.

local M = {}

-- matugen's quickshell template (matugen/config.toml) writes a flat
-- "key": "#rrggbb" map, and every key we care about (background,
-- color2, color4, color8) is unique across the file, so a single
-- pattern sweep is enough — no JSON parser needed.
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

-- "#0d0e14" + "ee" -> "rgba(0d0e14ee)"
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
