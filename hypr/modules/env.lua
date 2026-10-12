hl.env("XCURSOR_SIZE", "18")
hl.env("HYPRCURSOR_SIZE", "18")

hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

local localbin = os.getenv("HOME") .. "/.local/bin"
local path = os.getenv("PATH") or ""
if not string.find(path, localbin, 1, true) then
    hl.env("PATH", localbin .. ":" .. path)
end

hl.env("XDG_DATA_DIRS",
    "/usr/local/share:/usr/share:/var/lib/flatpak/exports/share:"
    .. os.getenv("HOME") .. "/.local/share/flatpak/exports/share:"
    .. os.getenv("HOME") .. "/.local/share"
)
