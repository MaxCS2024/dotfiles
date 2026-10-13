local defaults = require("modules.defaults")

return {
	mainMod = "SUPER",
	terminal = defaults.command("terminal"),
	editor = defaults.command("editor"),
	fileManager = defaults.command("file-manager"),
	browser = defaults.command("browser"),
}
