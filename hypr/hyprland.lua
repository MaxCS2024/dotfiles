require("modules.monitors")
require("modules.binds")
require("modules.autostart")
require("modules.env")
require("modules.decorations")
require("modules.layout")
require("modules.misc")
require("modules.input")
require("modules.windowrules")

-- This machine's own overrides, last so they win: monitors and input as
-- set in the island's settings window, which writes the file. Ignored by
-- git, since each laptop has its own screens and touchpad.
if package.searchpath("local", package.path) then
	require("local")
end

