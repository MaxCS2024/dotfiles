-- Shared values used across the bind files.
-- Every consumer does: local vars = require("modules.vars")
--
-- The four app roles resolve in three steps, most deliberate first:
--
--   1. ~/.local/state/rack/defaults/<role>, the command line the Conf
--      menu writes (SUPER+SPACE > Setup > Defaults) before running
--      `hyprctl reload`. The read is deliberately incurious: whatever
--      the file says is what the bind runs, with no check that it is
--      installed. The menu only offers what it found on the machine,
--      and a hand-written file is the user meaning it.
--   2. the first candidate below that this machine actually has, so a
--      fresh checkout opens the terminal it owns rather than the one
--      this config happened to be written on.
--   3. the first candidate regardless, so a bind always names something
--      and the menu has a value to show as not-installed.
--
-- State, not config, on purpose -- the same split omarchy makes for its
-- own editor default. The menu could rewrite this file instead, but then
-- picking a terminal would dirty a tracked dotfile, and the fallback
-- that makes a fresh checkout work would be gone. Deleting a state file
-- puts step 2 back.
--
-- The candidate lists hold the same apps, spelled the same way, as the
-- Defaults level offers (quickshell/main/menu/ConfMenu.qml): that menu
-- marks the row in force by comparing whole command strings, so a
-- fallback spelled differently would read there as "not on the list".
local STATE = os.getenv("HOME") .. "/.local/state/rack/defaults/"

-- Where flatpak exports one file per installed ref. Checked directly
-- rather than through PATH: the system-wide dir is on PATH already, but
-- the per-user one is not, and a `flatpak install --user` is no less
-- installed for it.
local FLATPAK_EXPORTS = {
	"/var/lib/flatpak/exports/bin/",
	os.getenv("HOME") .. "/.local/share/flatpak/exports/bin/",
}

-- Is it there? Answered by walking directories rather than by spawning
-- `command -v` or `flatpak info`: this file is evaluated on every config
-- load and again by the Conf menu's probe, and a process per candidate
-- is a dozen of them for something a handful of io.opens settle. A
-- packaged binary is readable as well as executable, and an export is a
-- symlink to one, which is what makes the open a fair test for both.
local function present(path)
	local handle = io.open(path, "r")
	if handle == nil then
		return false
	end

	handle:close()
	return true
end

local function onPath(bin)
	for dir in (os.getenv("PATH") or ""):gmatch("[^:]+") do
		if present(dir .. "/" .. bin) then
			return true
		end
	end

	return false
end

local function exported(ref)
	for _, dir in ipairs(FLATPAK_EXPORTS) do
		if present(dir .. ref) then
			return true
		end
	end

	return false
end

-- uwsm-app puts a launched app in a systemd scope of its own, which is
-- how the Conf menu spells its commands too. Dropped when uwsm is not
-- here, so a machine without it gets a bind that works instead of one
-- that exits "command not found" into a bind's unread stderr.
local UWSM = onPath("uwsm-app")

local function launch(app, program)
	local line = program
	if app.args ~= nil then
		line = line .. " " .. app.args
	end

	-- `wrap = false` is for the ones that are not apps to launch but
	-- commands to run: a terminal editor gets no uwsm-app in front of it.
	if app.wrap == false or not UWSM then
		return line
	end

	return "uwsm-app -- " .. line
end

-- How this one is installed, if it is: its own binary first, then the
-- flathub ref the menu's Setup section would install. That is the order
-- the menu resolves its own rows in, and for the same reason -- a native
-- brave beats `flatpak run com.brave.Browser` on startup time, and the
-- flatpak is what you have when there is no native one. nil when neither
-- is here, which is how a candidate is skipped.
--
-- Per candidate rather than every native first: the lists below rank
-- apps, and how a given one was installed does not outrank the ranking.
local function command(app)
	if onPath(app.bin) then
		return launch(app, app.bin)
	end

	if app.flatpak ~= nil and exported(app.flatpak) then
		return launch(app, "flatpak run " .. app.flatpak)
	end

	return nil
end

-- kitty leads because it is the terminal a stock Hyprland install brings
-- with it: on a machine nobody has configured yet, SUPER+RETURN opens
-- the one that is already there. foot and ghostty follow as the two this
-- config is usually run with, alacritty last so that every terminal the
-- Defaults menu can set is also one this can find on its own.
local TERMINALS = {
	{ bin = "kitty" },
	{ bin = "foot" },
	{ bin = "ghostty", flatpak = "com.mitchellh.ghostty" },
	{ bin = "alacritty" },
}

-- Terminal editors first, and unwrapped: nvim.desktop is already this
-- machine's text/plain handler and carries Terminal=true.
local EDITORS = {
	{ bin = "nvim", wrap = false },
	{ bin = "vim", wrap = false },
	{ bin = "hx", wrap = false },
	{ bin = "code" },
	{ bin = "zeditor", flatpak = "dev.zed.Zed" },
}

-- The one role with no row in the Defaults menu since 2026-09-17, so
-- this list answers for it alone; its state file is still read, and
-- still the way to set it. No flathub refs for the same reason: there is
-- no menu row whose spelling these would have to match, and a sandboxed
-- file manager is a poor one.
local FILE_MANAGERS = {
	{ bin = "nautilus" },
	{ bin = "thunar" },
	{ bin = "dolphin" },
	{ bin = "nemo" },
}

-- --password-store=basic keeps brave off a keyring that nothing in this
-- session unlocks; it is part of the command the menu writes, so it is
-- part of the one spelled here, on the flatpak as well as the binary.
local BROWSERS = {
	{ bin = "brave", flatpak = "com.brave.Browser", args = "--password-store=basic" },
	{ bin = "firefox", flatpak = "org.mozilla.firefox" },
	{ bin = "chromium", flatpak = "org.chromium.Chromium" },
	{ bin = "google-chrome-stable", flatpak = "com.google.Chrome" },
	{ bin = "zen-browser", flatpak = "app.zen_browser.zen" },
}

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

local function default(role, candidates)
	local set = stateValue(role)
	if set ~= nil then
		return set
	end

	for _, app in ipairs(candidates) do
		local line = command(app)
		if line ~= nil then
			return line
		end
	end

	-- Nothing on the list is installed either way. Name the first one as
	-- its binary: a command that fails is a better answer than an empty
	-- bind, and it is the one the menu will show as set-but-missing.
	return launch(candidates[1], candidates[1].bin)
end

return {
	mainMod = "SUPER",
	terminal = default("terminal", TERMINALS),
	editor = default("editor", EDITORS),
	fileManager = default("file-manager", FILE_MANAGERS),
	browser = default("browser", BROWSERS),
}
