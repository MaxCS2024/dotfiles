-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
local features = require("modules.features")
local defaults = require("modules.defaults")

hl.on("hyprland.start", function () 
	-- The shell at login is the dynamic island (quickshell/dynamic-island,
	-- brief in its AGENTS.md): the pill at the top centre and its settings
	-- window on SUPER+COMMA. The user's choice on 2026-10-10, replacing
	-- main. -n refuses a second copy: two answered SUPER+COMMA with two
	-- windows.
	hl.exec_cmd("qs -n -c dynamic-island")
	-- main (quickshell/main/shell.qml), the bar the island replaced, is no
	-- longer started; run it by hand with the line below. While it is up
	-- the island sits over its centre clock and hides with its bar. Not
	-- having it at login means none of its keys answer: Conf (SUPER+SPACE),
	-- the power menu (SUPER+ESCAPE; the island's is a middle click), the
	-- notification and network rails, themes, Print, and
	-- nothing shows notifications (dunst is masked so main could own them).
	--
	-- The other configs under quickshell/ are siblings with lines of their
	-- own; a layout still being tried is run by hand with `qs -c <name>`
	-- until it earns one.
	-- QT_QPA_PLATFORMTHEME is overridden for this process only. The
	-- session-wide value (env.lua) is "qt5ct": the *Qt5* tool, which isn't
	-- installed anyway. Qt6 fails to load it, falls back to the generic Unix
	-- theme and never learns an icon theme name, so the two icon *existence*
	-- checks answer "no" for every name — including ones that are installed.
	-- Measured under qt5ct: hasThemeIcon("foot") and
	-- hasThemeIcon("org.gnome.Nautilus") are both false and
	-- iconPath(name, true) is "" for both; under gtk3 both resolve, while a
	-- genuinely absent name still correctly answers false.
	--
	-- Icons gated on exactly those checks were silently falling back
	-- forever. Today that is services/AppIcons.qml (iconPath, behind the
	-- launcher, the active window, the tray and notifications) and
	-- volume/VolumePanel.qml's mixer (hasThemeIcon). "gtk3" reads
	-- gtk-icon-theme-name from ~/.config/gtk-3.0/settings.ini (Adwaita)
	-- and fixes both.
	--
	-- This does NOT affect the image://icon provider, which loads icons fine
	-- under either value — so it is never the explanation for an icon that
	-- renders as a broken placeholder. That is a malformed source URL; see
	-- bar/SystemTray.qml, which had one and is fixed independently of this.
	--
	-- Scoped to this process rather than fixed in env.lua on purpose: setting
	-- it session-wide also moves every other Qt app onto GTK file dialogs
	-- instead of the portal, which is a bigger change than the icons warrant.
	-- env QT_QPA_PLATFORMTHEME=gtk3 qs -c main
	-- The app launcher (SUPER+P), its own config since 2026-10-09 so it
	-- works without the bar. Same theme override: it uses AppIcons too.
	hl.exec_cmd("env QT_QPA_PLATFORMTHEME=gtk3 qs -c launcher")
	-- The clipboard window (SUPER+C), split out the same day for the same
	-- reason. It shows no app icons, so it needs no theme override.
	hl.exec_cmd("qs -c clipboard")
	hl.exec_cmd("awww-daemon")
	hl.exec_cmd("wl-paste --watch cliphist store")
	hl.exec_cmd("hypridle") -- idle/lock daemon, config in hypr/hypridle.conf
	-- The polkit agent: the password dialog for apps that ask the system
	-- for rights over D-Bus, such as Impression writing a USB stick or a
	-- disk tool formatting an internal drive. Without one they fail with
	-- NotAuthorizedCanObtain (found 2026-09-27). The shell's own admin
	-- actions don't go through it: services/PrivilegedExec.qml runs them
	-- with sudo -S and its own password window. A systemd user unit, which
	-- has this session's WAYLAND_DISPLAY because Hyprland hands it over.
	hl.exec_cmd("systemctl --user start hyprpolkitagent")
	-- No color-scheme here: GTK4/libadwaita takes light vs. dark from that
	-- setting alone, and the shell sets it to match the active palette
	-- whenever it writes GTK's colours (quickshell/main/theme/AppColors.qml).
	-- Pinning prefer-dark at login would put a light palette on the dark
	-- stylesheet until the shell corrected it.
	hl.exec_cmd("hyprsunset") -- blue-light filter daemon, controlled live via `hyprctl hyprsunset ...` (see quickshell/main/services/NightLight.qml)
	-- Dictation's daemon. `voxtype setup systemd` installs the unit as
	-- WantedBy=graphical-session.target, and nothing in this session
	-- activates that target (Hyprland is started by ly, not uwsm), so the
	-- unit is enabled and never starts: dictation worked only until the
	-- first reboot after `rack features on dictation` (found 2026-09-24).
	-- `rack features off dictation` disables the unit; the check here keeps
	-- this from starting it again at the next login.
	if features.on("dictation") then
		hl.exec_cmd("systemctl --user start voxtype.service")
	end
	-- The browser, started with no window so SUPER+B only has to open one.
	-- Measured 2026-09-25 on the T480s in power-saver: a cold Brave window
	-- took ~2.8s, the first one from a preloaded Brave ~1.5s and later ones
	-- ~0.9s. It costs a few hundred MB of RAM for the whole session.
	local preload = defaults.preloadArgv()
	if preload ~= nil then
		hl.exec_cmd(table.concat(preload, " "))
	end
end)
