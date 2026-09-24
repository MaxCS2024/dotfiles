-- Shared values used across the bind files.
-- Every consumer does: local vars = require("modules.vars")
--
-- The four app roles are whatever modules/defaults.lua resolves them to:
-- the default the user set (SUPER+SPACE > Setup > Defaults, or
-- `relay default set`), else the first candidate this machine has. That
-- file owns the candidates and the order; this one only names the roles
-- the binds use. A bind captures its string here, at config load, which is
-- why setting a default ends in `hyprctl reload`.
local defaults = require("modules.defaults")

return {
	mainMod = "SUPER",
	terminal = defaults.command("terminal"),
	editor = defaults.command("editor"),
	fileManager = defaults.command("file-manager"),
	browser = defaults.command("browser"),
}
