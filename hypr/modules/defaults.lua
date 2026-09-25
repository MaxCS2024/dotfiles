-- Default apps: which app does each role on this desktop.
--
-- The one place that knows the candidates for each role, the order a
-- default resolves in, and what each app needs to be launched. See the
-- "Default apps" terms in quickshell/CONTEXT.md, and docs/adr/0001 for why
-- this is Lua and lives here.
--
-- Two callers, and only two:
--
--   * Hyprland, at config load, through modules/vars.lua -- the binds
--     capture the command string then, which is why setting a default
--     ends in `hyprctl reload`.
--   * `relay default`, which runs this file as a script (the bottom of
--     it). The shell, the Conf menu and anything else ask relay, never
--     this file, so there is one interface to test.
--
-- A role resolves in three steps, most deliberate first:
--
--   1. what the user set, in $XDG_STATE_HOME/rack/defaults/<role>: a
--      candidate's name, or anything else, which is a custom command and
--      runs as written. The read is deliberately incurious -- a set
--      candidate is used whether or not it is installed, because the user
--      meant it.
--   2. the first candidate this machine actually has, so a fresh checkout
--      opens the terminal it owns rather than the one this config happened
--      to be written on.
--   3. the first candidate regardless, so a bind always names something
--      and `relay default list` has a value to show as not installed.
--
-- State, not config, on purpose: picking a terminal should not dirty a
-- tracked file, and deleting the state file (`relay default unset`) puts
-- step 2 back.

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

-- flatpak's own variables for moving its installations, honoured here so
-- the tests can point at a fake one with the names flatpak itself uses.
local FLATPAK_SYSTEM = env("FLATPAK_SYSTEM_DIR", "/var/lib/flatpak")
local FLATPAK_USER = env("FLATPAK_USER_DIR", DATA_HOME .. "/flatpak")

-- ── The candidates ───────────────────────────────────────
--
-- Ranked: the order is step 2's order. `name` is what a set default stores
-- and what `relay default set` takes. `desktop` is a list because the id
-- is not always guessable; the first that exists wins. `wrap = false` is
-- for the ones that are commands to run rather than apps to launch -- a
-- terminal editor gets no uwsm-app in front of it.
--
-- `handler` is how the XDG side is told (see relay/lib/default.sh, which
-- does the writing): the terminal list xdg-terminal-exec reads, a MIME
-- default, or xdg-settings' default-web-browser, which sets the http,
-- https and text/html handlers together.
local ROLES = {
	{
		name = "terminal",
		handler = "terminals-list",
		-- kitty leads because it is the terminal a stock Hyprland install
		-- brings with it: on a machine nobody has configured yet,
		-- SUPER+RETURN opens the one that is already there.
		--
		-- `terminal` is how each one is told to run a command, and getting
		-- it wrong is not cosmetic: kitty rejects -e ("Unknown flag") and
		-- takes the program as plain trailing arguments; ghostty and
		-- alacritty take the app-id as --class, foot and kitty as --app-id.
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
		-- text/plain and nothing wider: nvim.desktop carries Terminal=true,
		-- so a terminal editor is a real answer here and not a trap.
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
		-- `appMode`: takes --app=<url>, the chromium-family flag that opens a
		-- page as its own window with no browser chrome. The firefox family
		-- has no equivalent left.
		--
		-- `preload`: takes --no-startup-window, which starts the browser
		-- with no window and keeps it running after its last window closes,
		-- so the autostart can have it up before the first SUPER+B. Also
		-- chromium-only; firefox quits when it has no window.
		--
		-- --password-store=basic keeps brave off a keyring that nothing in
		-- this session unlocks.
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
		-- No flathub refs: a sandboxed file manager is a poor one.
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

-- ── Is it here? ──────────────────────────────────────────
--
-- Answered by walking directories rather than by spawning `command -v` or
-- `flatpak info`: this runs on every Hyprland config load, and a process
-- per candidate is a dozen of them for something a handful of io.opens
-- settle. A packaged binary is readable as well as executable, and a
-- flatpak export is a symlink to one, which is what makes the open a fair
-- test for both.
local function present(path)
	local handle = io.open(path, "r")
	if handle == nil then
		return false
	end

	handle:close()
	return true
end

-- Where on PATH a binary is, or nil.
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

-- Checked in both installations rather than through PATH: the system
-- export dir is usually on PATH, the per-user one is not, and a
-- `flatpak install --user` is no less installed for it.
local function exported(ref)
	return present(FLATPAK_SYSTEM .. "/exports/bin/" .. ref) or present(FLATPAK_USER .. "/exports/bin/" .. ref)
end

-- uwsm-app puts a launched app in a systemd scope of its own. Dropped when
-- uwsm is not here, so a machine without it gets a bind that works instead
-- of one that exits "command not found" into a bind's unread stderr.
local UWSM = onPath("uwsm-app")

-- How this candidate is installed, if it is: its own binary first, then
-- its flathub ref. A native brave beats `flatpak run com.brave.Browser` on
-- startup time, and the flatpak is what you have when there is no native
-- one. Per candidate rather than every native first: the lists rank apps,
-- and how one was installed does not outrank the ranking.
local function installedVia(app)
	if onPath(app.bin) then
		return "native"
	end

	if app.flatpak ~= nil and exported(app.flatpak) then
		return "flatpak"
	end

	return nil
end

-- table.unpack is 5.2+; LuaJIT, which some builds embed, has only the global.
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

-- The argv that launches a candidate, given how it is installed. One that
-- is not installed is spelled as its binary: a command that fails is a
-- better answer than an empty bind.
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

-- The .desktop id the handler is set to. A flatpak's is its ref; a native
-- one's is the first of its ids that some applications dir holds. nil when
-- neither, and the handler is then left alone.
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

-- ── Resolving ────────────────────────────────────────────

-- Every role, in the order they are listed.
function M.roles()
	local names = {}
	for _, role in ipairs(ROLES) do
		names[#names + 1] = role.name
	end

	return names
end

-- What a role resolves to. `stored` answers "what if the user had set
-- this": nil reads the state file, false means nothing set, a string is
-- what the file would hold. That is what lets `relay default set` report
-- and write the handler of the default it is about to make, dry run or
-- not, without writing the file first.
--
-- Returns nil for a role that does not exist, else a table:
--   role, source ("set" | "missing" | "custom" | "fallback"), command,
--   and unless custom: name, label, installed, via, desktop, argv, app.
--
-- "missing" is a candidate that was set and has since been uninstalled
-- (user request 2026-09-24): the first installed candidate stands in, the
-- way it does when nothing is set, and `wanted`/`wantedLabel` name the one
-- that was set. The choice itself is kept, so installing it again brings
-- it back. Before, the role went on naming the missing app, and the
-- keybind and every terminal the shell opens failed until someone set
-- another. With nothing installed at all there is nothing to stand in,
-- and the set candidate is named anyway, as "set".
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
			found.source = "custom"
			found.command = stored
			return found
		end
		found.source = "set"
		if installedVia(app) == nil then
			local standIn = firstInstalled(role)
			if standIn ~= nil then
				found.source = "missing"
				found.wanted = app.name
				found.wantedLabel = app.label
				app = standIn
			end
		end
	else
		found.source = "fallback"
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

-- The command line a role's keybind runs.
function M.command(roleName)
	return M.describe(roleName).command
end

-- Every candidate for a role, marked with how it is installed and whether
-- it is the default.
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
			default = default.source ~= "custom" and default.name == app.name,
		}
	end

	return list
end

-- ── Launching ────────────────────────────────────────────

-- A custom command as an argv, with extra words passed after it. sh splits
-- the command and "$@" keeps each extra word whole.
local function customArgv(command, extra, ...)
	if extra == nil then
		return { "sh", "-c", command }
	end

	return append({ "sh", "-c", "exec " .. command .. " " .. extra .. ' "$@"', "sh" }, ...)
end

-- Open the default terminal, optionally running `command` in it, with the
-- given app-id and title when they are not empty. A custom terminal gets
-- none of those flags -- nothing is known about it -- and -e, which most
-- terminals take.
function M.terminalArgv(command, appId, title)
	local found = M.describe("terminal")
	if found.source == "custom" then
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

-- Open a page as a window of its own when the default browser can, and as
-- an ordinary xdg-open otherwise: a tab is a worse window than an app
-- window, and a page that does not open is worse than both.
function M.webAppArgv(url)
	local found = M.describe("browser")
	if found.source ~= "custom" and found.installed and found.app.appMode then
		return append(copy(found.argv), "--app=" .. url)
	end

	return append(launcher(), "xdg-open", url)
end

-- Start the default browser with no window, or nil when it cannot be
-- preloaded. A later launch hands its window to this process, so the
-- argv must be the browser's own, flags included: the first process's
-- --password-store is the one every window gets.
function M.preloadArgv()
	local found = M.describe("browser")
	if found.source == "custom" or not found.installed or not found.app.preload then
		return nil
	end

	return append(copy(found.argv), "--no-startup-window")
end

-- Run a role's default as it is.
function M.argv(roleName)
	local found = M.describe(roleName)
	if found.source == "custom" then
		return customArgv(found.command)
	end

	return copy(found.argv)
end

-- ── Script mode: relay's side of the seam ────────────────
--
-- relay/lib/default.sh runs `lua defaults.lua <verb> ...`. This is that
-- file's private protocol, not an interface of its own: the verbs mirror
-- what relay needs, and the user-facing words are relay's.
--
--   describe <role> [--stored <value> | --unset]   key<TAB>value lines
--   list [--json]                                   every role
--   candidates <role>                               one role's candidates
--   argv <role>                                     NUL-separated argv
--   argv terminal <app-id> <title> [command]
--   argv webapp <url>
--
-- Exit 2 with a message on stderr for a role or verb that does not exist.

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

-- What one role looks like outside this file: plain data, no app tables.
local function public(found)
	local out = {
		role = found.role,
		source = found.source,
		wanted = found.wanted,
		wantedLabel = found.wantedLabel,
		command = found.command,
		-- What the default is, as a package manager knows it: the binary's
		-- path for pacman to name the owner of (the app manager marks
		-- that package's row), or the flatpak ref itself.
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

-- One line per role for people: what it resolves to and why.
local function listText()
	for _, name in ipairs(M.roles()) do
		local found = M.describe(name)
		local shown, why
		if found.source == "custom" then
			shown, why = found.command, "custom command"
		else
			shown = found.label
			why = found.source == "set" and "set" or "first installed"
			if found.source == "missing" then
				why = found.wantedLabel .. " is set, not installed"
			elseif not found.installed then
				why = found.source == "set" and "set, not installed" or "nothing installed"
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
	line("source", found.source)
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

-- Run as a script only when this file is the script: required by Hyprland
-- or dofile'd, it is just the module. Hyprland's Lua may have neither `arg`
-- nor `debug`, which is the "not a script" answer anyway.
if arg ~= nil and arg[0] ~= nil and debug ~= nil and debug.getinfo ~= nil then
	local source = debug.getinfo(1, "S").source
	if source == "@" .. arg[0] then
		M.main(arg)
		os.exit(0)
	end
end

return M
