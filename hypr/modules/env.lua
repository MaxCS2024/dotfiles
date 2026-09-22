-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

-- Hyprland
hl.env("XCURSOR_SIZE", "18")
hl.env("HYPRCURSOR_SIZE", "18")

-- Toolkit backend
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")

-- XDG
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Qt
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- Hyprland hands `sh -c` the environment it was started in, and ~/.local/bin
-- is exported from .zshrc, which only interactive shells read. Without this a
-- bind calling `relay` or `rack` dies with "command not found" — and a bind's
-- stderr goes nowhere the user ever sees, so that failure is silent.
--
-- Guarded because this file is re-evaluated on every `hyprctl reload`, and
-- os.getenv reads the PATH the *previous* evaluation already prepended to: an
-- unguarded line grows the variable by one copy per reload for as long as the
-- session lives.
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
