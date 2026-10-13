local M = {}

local function env(name, fallback)
	local value = os.getenv(name)
	if value == nil or value == "" then
		return fallback
	end

	return value
end

local HOME = env("HOME", "")
local STATE = env("XDG_STATE_HOME", HOME .. "/.local/state") .. "/rack/defaults/"
local DATA_HOME = env("XDG_DATA_HOME", HOME .. "/.local/share")

local FLATPAK_SYSTEM = env("FLATPAK_SYSTEM_DIR", "/var/lib/flatpak")
local FLATPAK_USER = env("FLATPAK_USER_DIR", DATA_HOME .. "/flatpak")

local ROLES = {
	{
		name = "terminal",
		handler = "terminals-list",
		candidates = {
			{ name = "kitty", label = "Kitty", bin = "kitty",
				desktop = { "kitty.desktop" },
				terminal = { appId = "--app-id=", exec = false } },
			{ name = "foot", label = "Foot", bin = "foot",
				desktop = { "foot.desktop" },
				terminal = { appId = "--app-id=", exec = "-e" } },
			{ name = "ghostty", label = "Ghostty", bin = "ghostty", flatpak = "com.mitchellh.ghostty",
				desktop = { "com.mitchellh.ghostty.desktop", "ghostty.desktop" },
				terminal = { appId = "--class=", exec = "-e" } },
			{ name = "alacritty", label = "Alacritty", bin = "alacritty",
				desktop = { "Alacritty.desktop", "alacritty.desktop" },
				terminal = { appId = "--class=", exec = "-e" } },
		},
	},
	{
		name = "editor",
		handler = "mime",
		mimes = { "text/plain" },
		candidates = {
			{ name = "nvim", label = "Neovim", bin = "nvim", wrap = false, desktop = { "nvim.desktop" } },
			{ name = "vim", label = "Vim", bin = "vim", wrap = false, desktop = { "vim.desktop" } },
			{ name = "helix", label = "Helix", bin = "hx", wrap = false,
				desktop = { "helix.desktop", "Helix.desktop" } },
			{ name = "code", label = "VS Code", bin = "code", desktop = { "code.desktop" } },
			{ name = "zed", label = "Zed", bin = "zeditor", flatpak = "dev.zed.Zed",
				desktop = { "dev.zed.Zed.desktop" } },
		},
	},
	{
		name = "browser",
		handler = "web-browser",
		candidates = {
			{ name = "brave", label = "Brave", bin = "brave", flatpak = "com.brave.Browser",
				args = { "--password-store=basic" },
				desktop = { "brave-browser.desktop", "brave.desktop" }, appMode = true, preload = true },
			{ name = "firefox", label = "Firefox", bin = "firefox", flatpak = "org.mozilla.firefox",
				desktop = { "firefox.desktop" } },
			{ name = "chromium", label = "Chromium", bin = "chromium", flatpak = "org.chromium.Chromium",
				desktop = { "chromium.desktop" }, appMode = true, preload = true },
			{ name = "chrome", label = "Google Chrome", bin = "google-chrome-stable", flatpak = "com.google.Chrome",
				desktop = { "google-chrome.desktop" }, appMode = true, preload = true },
			{ name = "zen", label = "Zen", bin = "zen-browser", flatpak = "app.zen_browser.zen",
				desktop = { "zen.desktop", "app.zen_browser.zen.desktop" } },
		},
	},
	{
		name = "file-manager",
		handler = "mime",
		mimes = { "inode/directory" },
		candidates = {
			{ name = "nautilus", label = "Files", bin = "nautilus", desktop = { "org.gnome.Nautilus.desktop" } },
			{ name = "thunar", label = "Thunar", bin = "thunar", desktop = { "thunar.desktop" } },
			{ name = "dolphin", label = "Dolphin", bin = "dolphin", desktop = { "org.kde.dolphin.desktop" } },
			{ name = "nemo", label = "Nemo", bin = "nemo", desktop = { "nemo.desktop" } },
		},
	},
}

local BY_NAME = {}
for _, role in ipairs(ROLES) do
	BY_NAME[role.name] = role
end

local function present(path)
	local handle = io.open(path, "r")
	if handle == nil then
		return false
	end

	handle:close()
	return true
end

local function whereOnPath(bin)
	for dir in env("PATH", ""):gmatch("[^:]+") do
		if present(dir .. "/" .. bin) then
			return dir .. "/" .. bin
		end
	end

	return nil
end

local function onPath(bin)
	return whereOnPath(bin) ~= nil
end

local function exported(ref)
	return present(FLATPAK_SYSTEM .. "/exports/bin/" .. ref) or present(FLATPAK_USER .. "/exports/bin/" .. ref)
end

local UWSM = onPath("uwsm-app")

local function installedVia(app)
	if onPath(app.bin) then
		return "native"
	end

	if app.flatpak ~= nil and exported(app.flatpak) then
		return "flatpak"
	end

	return nil
end

local unpack = table.unpack or unpack

local function append(list, ...)
	for _, value in ipairs({ ... }) do
		list[#list + 1] = value
	end

	return list
end

local function copy(list)
	return append({}, unpack(list))
end

local function launcher()
	if UWSM then
		return { "uwsm-app", "--" }
	end

	return {}
end

local function argvFor(app, via)
	local argv = app.wrap == false and {} or launcher()
	if via == "flatpak" then
		append(argv, "flatpak", "run", app.flatpak)
	else
		append(argv, app.bin)
	end

	return append(argv, unpack(app.args or {}))
end

local function applicationDirs()
	local dirs = {
		DATA_HOME .. "/applications",
		FLATPAK_USER .. "/exports/share/applications",
		FLATPAK_SYSTEM .. "/exports/share/applications",
	}
	for dir in env("XDG_DATA_DIRS", "/usr/local/share:/usr/share"):gmatch("[^:]+") do
		dirs[#dirs + 1] = dir .. "/applications"
	end

	return dirs
end

local function desktopFor(app, via)
	if via == "flatpak" then
		return app.flatpak .. ".desktop"
	end

	if via ~= "native" then
		return nil
	end

	local dirs = applicationDirs()
	for _, id in ipairs(app.desktop) do
		for _, dir in ipairs(dirs) do
			if present(dir .. "/" .. id) then
				return id
			end
		end
	end

	return nil
end

local function stateValue(role)
	local file = io.open(STATE .. role, "r")
	if file == nil then
		return nil
	end

	local value = file:read("*l")
	file:close()

	if value == nil then
		return nil
	end

	value = value:match("^%s*(.-)%s*$")
	if value == "" then
		return nil
	end

	return value
end

local function candidateNamed(role, name)
	for _, app in ipairs(role.candidates) do
		if app.name == name then
			return app
		end
	end

	return nil
end

local function firstInstalled(role)
	for _, candidate in ipairs(role.candidates) do
		if installedVia(candidate) then
			return candidate
		end
	end

	return nil
end

function M.roles()
	local names = {}
	for _, role in ipairs(ROLES) do
		names[#names + 1] = role.name
	end

	return names
end

function M.describe(roleName, stored)
	local role = BY_NAME[roleName]
	if role == nil then
		return nil
	end

	if stored == nil then
		stored = stateValue(roleName)
	end

	local found = { role = roleName, handler = role.handler, mimes = role.mimes or {} }
	local app

	if stored then
		app = candidateNamed(role, stored)
		if app == nil then
			found.resolvedBy = "custom"
			found.command = stored
			return found
		end
		found.resolvedBy = "set"
		if installedVia(app) == nil then
			local standIn = firstInstalled(role)
			if standIn ~= nil then
				found.resolvedBy = "missing"
				found.wanted = app.name
				found.wantedLabel = app.label
				app = standIn
			end
		end
	else
		found.resolvedBy = "fallback"
		app = firstInstalled(role) or role.candidates[1]
	end

	local via = installedVia(app)
	found.app = app
	found.name = app.name
	found.label = app.label
	found.via = via
	found.installed = via ~= nil
	found.argv = argvFor(app, via)
	found.command = table.concat(found.argv, " ")
	found.desktop = desktopFor(app, via)
	return found
end

function M.command(roleName)
	return M.describe(roleName).command
end

function M.candidates(roleName)
	local default = M.describe(roleName)
	local list = {}
	for _, app in ipairs(BY_NAME[roleName].candidates) do
		local via = installedVia(app)
		list[#list + 1] = {
			name = app.name,
			label = app.label,
			via = via,
			installed = via ~= nil,
			command = table.concat(argvFor(app, via), " "),
			default = default.resolvedBy ~= "custom" and default.name == app.name,
		}
	end

	return list
end

local function customArgv(command, extra, ...)
	if extra == nil then
		return { "sh", "-c", command }
	end

	return append({ "sh", "-c", "exec " .. command .. " " .. extra .. ' "$@"', "sh" }, ...)
end

function M.terminalArgv(command, appId, title)
	local found = M.describe("terminal")
	if found.resolvedBy == "custom" then
		if command == nil then
			return customArgv(found.command)
		end
		return customArgv(found.command, "-e", "sh", "-c", command)
	end

	local how = found.app.terminal
	local argv = copy(found.argv)
	if appId ~= nil and appId ~= "" then
		append(argv, how.appId .. appId)
	end
	if title ~= nil and title ~= "" then
		append(argv, "--title=" .. title)
	end
	if command ~= nil then
		if how.exec then
			append(argv, how.exec)
		end
		append(argv, "sh", "-c", command)
	end

	return argv
end

function M.webAppArgv(url)
	local found = M.describe("browser")
	if found.resolvedBy ~= "custom" and found.installed and found.app.appMode then
		return append(copy(found.argv), "--app=" .. url)
	end

	return append(launcher(), "xdg-open", url)
end

function M.preloadArgv()
	local found = M.describe("browser")
	if found.resolvedBy == "custom" or not found.installed or not found.app.preload then
		return nil
	end

	return append(copy(found.argv), "--no-startup-window")
end

function M.argv(roleName)
	local found = M.describe(roleName)
	if found.resolvedBy == "custom" then
		return customArgv(found.command)
	end

	return copy(found.argv)
end

local function jsonString(value)
	local escaped = value:gsub('[%c"\\]', function(char)
		local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
		return named[char] or string.format("\\u%04x", char:byte())
	end)
	return '"' .. escaped .. '"'
end

local function json(value)
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" or kind == "number" then
		return tostring(value)
	elseif kind == "string" then
		return jsonString(value)
	elseif value[1] ~= nil or value.__array then
		local parts = {}
		for _, item in ipairs(value) do
			parts[#parts + 1] = json(item)
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end

	local keys = {}
	for key in pairs(value) do
		if key ~= "__array" then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)

	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = jsonString(key) .. ":" .. json(value[key])
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function emptyArray()
	return { __array = true }
end

local function public(found)
	local out = {
		role = found.role,
		resolvedBy = found.resolvedBy,
		wanted = found.wanted,
		wantedLabel = found.wantedLabel,
		command = found.command,
		path = found.via == "native" and whereOnPath(found.app.bin) or nil,
		flatpak = found.via == "flatpak" and found.app.flatpak or nil,
		name = found.name,
		label = found.label,
		installed = found.installed,
		via = found.via,
		desktop = found.desktop,
		candidates = M.candidates(found.role),
	}
	if #out.candidates == 0 then
		out.candidates = emptyArray()
	end

	return out
end

local function fail(message)
	io.stderr:write(message, "\n")
	os.exit(2)
end

local function roleOrFail(name)
	local found = M.describe(name)
	if found == nil then
		fail("no role '" .. tostring(name) .. "' (roles: " .. table.concat(M.roles(), ", ") .. ")")
	end

	return found
end

local function writeArgv(argv)
	for _, word in ipairs(argv) do
		io.write(word, "\0")
	end
end

local function listText()
	for _, name in ipairs(M.roles()) do
		local found = M.describe(name)
		local shown, why
		if found.resolvedBy == "custom" then
			shown, why = found.command, "custom command"
		else
			shown = found.label
			why = found.resolvedBy == "set" and "set" or "first installed"
			if found.resolvedBy == "missing" then
				why = found.wantedLabel .. " is set, not installed"
			elseif not found.installed then
				why = found.resolvedBy == "set" and "set, not installed" or "nothing installed"
			end
		end
		io.write(string.format("%-13s %-16s %s\n", name, shown, why))
	end
end

local function candidatesText(name)
	roleOrFail(name)
	for _, app in ipairs(M.candidates(name)) do
		io.write(string.format("%s %-10s %-16s %s\n", app.default and "*" or " ", app.name, app.label,
			app.via or "not installed"))
	end
end

local function describeText(found)
	local candidates = {}
	for _, app in ipairs(BY_NAME[found.role].candidates) do
		candidates[#candidates + 1] = app.name
	end

	local function line(key, value)
		if value == nil then
			value = ""
		elseif type(value) == "boolean" then
			value = value and "1" or "0"
		end
		io.write(key, "\t", (tostring(value):gsub("[\t\n]", " ")), "\n")
	end

	line("role", found.role)
	line("resolvedBy", found.resolvedBy)
	line("wanted", found.wanted)
	line("wantedLabel", found.wantedLabel)
	line("name", found.name)
	line("label", found.label)
	line("installed", found.installed)
	line("command", found.command)
	line("desktop", found.desktop)
	line("handler", found.handler)
	line("mimes", table.concat(found.mimes, " "))
	line("candidates", table.concat(candidates, " "))
end

function M.main(args)
	local verb = args[1]

	if verb == "describe" then
		local stored
		if args[3] == "--unset" then
			stored = false
		elseif args[3] == "--stored" then
			stored = args[4] or ""
			if stored:match("^%s*$") then
				stored = false
			end
		end
		roleOrFail(args[2])
		describeText(M.describe(args[2], stored))
	elseif verb == "list" then
		if args[2] == "--json" then
			local roles = {}
			for _, name in ipairs(M.roles()) do
				roles[#roles + 1] = public(M.describe(name))
			end
			io.write(json(roles), "\n")
		else
			listText()
		end
	elseif verb == "candidates" then
		candidatesText(args[2])
	elseif verb == "argv" then
		local role = args[2]
		if role == "terminal" and #args >= 4 then
			writeArgv(M.terminalArgv(args[5], args[3], args[4]))
		elseif role == "webapp" then
			writeArgv(M.webAppArgv(args[3] or ""))
		else
			roleOrFail(role)
			writeArgv(M.argv(role))
		end
	else
		fail("unknown verb '" .. tostring(verb) .. "'")
	end
end

if arg ~= nil and arg[0] ~= nil and debug ~= nil and debug.getinfo ~= nil then
	local source = debug.getinfo(1, "S").source
	if source == "@" .. arg[0] then
		M.main(arg)
		os.exit(0)
	end
end

return M
