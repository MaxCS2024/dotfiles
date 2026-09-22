-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
hl.on("hyprland.start", function () 
	-- "main" is the stable quickshell config (quickshell/main/shell.qml).
	-- Experimental layouts live as sibling configs under quickshell/ and
	-- are run manually with `qs -c <name>` — they never touch autostart.
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
	-- Four call sites gate an icon on exactly those checks and were silently
	-- falling back forever: launcher/Launcher.qml, bar/ActiveWindow.qml,
	-- quicksettings/MixerTab.qml (via hasThemeIcon) and
	-- notifications/NotificationCard.qml. "gtk3" reads gtk-icon-theme-name
	-- from ~/.config/gtk-3.0/settings.ini (Adwaita) and fixes all four.
	--
	-- This does NOT affect the image://icon provider, which loads icons fine
	-- under either value — so it is never the explanation for an icon that
	-- renders as a broken placeholder. That is a malformed source URL; see
	-- bar/SystemTray.qml, which had one and is fixed independently of this.
	--
	-- Scoped to this process rather than fixed in env.lua on purpose: setting
	-- it session-wide also moves every other Qt app onto GTK file dialogs
	-- instead of the portal, which is a bigger change than the icons warrant.
	hl.exec_cmd("env QT_QPA_PLATFORMTHEME=gtk3 qs -c main")
	hl.exec_cmd("awww-daemon")
	hl.exec_cmd("wl-paste --watch cliphist store")
	hl.exec_cmd("hypridle") -- idle/lock daemon, config in hypr/hypridle.conf
	-- GTK4/libadwaita apps take light vs. dark from this setting alone;
	-- gtk-{3,4}.0/settings.ini's gtk-application-prefer-dark-theme only
	-- reaches GTK3. Without it the libadwaita colors that matugen doesn't
	-- override (sidebars especially) stay light — see matugen/templates/
	-- gtk-colors.css. It's dconf state, so this is just to keep a fresh
	-- machine reproducible.
	hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
	hl.exec_cmd("hyprsunset") -- blue-light filter daemon, controlled live via `hyprctl hyprsunset ...` (see quickshell/main/services/NightLight.qml)
end)
