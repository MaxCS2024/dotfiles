import Quickshell
import QtQuick
import "bar"
import "launcher"
import "osd"
import "notifications"
import "lockscreen"
import "wallpaper"
import "powermenu"
import "menu"
import "network"
import "volume"
import "media"
import "battery"
import "calendar"
import "clipboard"
import "installer"
import "keybinds"
import "packages"
import "theme"
import "services"

ShellRoot {
    id: shell

    Bar {}

    // Not dead code — deleting this turns the Night light switch on the
    // network rail back into a no-op. NightLight is a Singleton, so it is
    // built the first time something names it. Every other service is
    // named by a bar module or a panel that displays it; this one only
    // ever acts (it pushes a temperature at hyprsunset when
    // Settings.nightLight changes), so nothing would otherwise build it
    // and its Connections to Settings would never exist.
    //
    // Naming it here rather than letting that switch be the first
    // reference is also what gets a saved setting to hyprsunset at
    // login: network/NetworkPanel.qml is behind a LazyLoader like every
    // other panel, so its reference wouldn't happen until the rail was
    // first opened. This mattered the same way when the switch was a
    // dashboard tile, which is what it was until 2026-09-21.
    readonly property var nightLight: NightLight

    // Self-heals the Mpris staleness bug bar/MediaPlayer.qml can hit
    // (service singleton, so nothing else names it into existence — same
    // reasoning as nightLight above). See services/MprisWatchdog.qml.
    readonly property var mprisWatchdog: MprisWatchdog

    // The wallpaper folder, which image each output is showing, and the
    // hourly rotation (wallpaper/Wallpapers.qml). Named here for exactly
    // the reason nightLight is: the gallery that displays it is behind a
    // LazyLoader and most sessions never open it, but the rotation has to
    // run from login whether it is opened or not — and a singleton is
    // built the first time something names it.
    readonly property var wallpapers: Wallpapers

    // Launcher, WallpaperSwitcher and the packages window are the
    // heaviest (packages/PackagesList.qml spawns four pacman/flatpak
    // queries the moment it is built) and most sessions never open some
    // of them — LazyLoader defers construction to first use.
    // `active` only ever goes true here, on an open/toggle request; it
    // never goes false again afterward, so a window is built at most
    // once per shell run, not re-built on every open/close. Each
    // window's IpcHandler moved to services/Panels.qml so `qs ipc call
    // <target> ...` keeps working even before the window has ever
    // loaded (see that file's comment). Every window below opens itself
    // via its own Component.onCompleted the moment it's lazily created,
    // since that only ever happens in response to an open/toggle request
    // — see the matching comment in launcher/Launcher.qml.

    // ── Waking the lazily-built windows ─────────────────────
    // Fourteen near-identical Connections blocks until 2026-09-21, one
    // per surface, each listening for that surface's own three signals
    // and doing the same one thing: switch its loader on.
    //
    // All this has to do is build the window. What happens next is the
    // window's own: common/ShellSurface.qml opens itself when it is
    // completed and reads whatever payload the request carried off
    // services/Panels.qml, which is why the `wasInactive` handoff that
    // used to live here — call find() on the fresh item, but only if it
    // was not already up — is gone from both places that had it.
    readonly property var panelLoaders: ({
        "launcher": launcherLoader,
        "wallpaper": wallpaperSwitcherLoader,
        "lockscreen-preview": lockPreviewLoader,
        "menu": menuLoader,
        "keybinds": keybindsLoader,
        "network": networkLoader,
        "notification-history": notificationHistoryLoader,
        "volume": volumeLoader,
        "media": mediaLoader,
        "battery": batteryLoader,
        "calendar": calendarLoader,
        "clipboard": clipboardLoader,
        "themes": themesLoader,
        "installer": installerLoader,
        "packages": packagesLoader
    })

    Connections {
        target: Panels
        function onPanelRequested(name, verb, arg) {
            if (verb === "close") return
            const loader = shell.panelLoaders[name]
            if (loader) loader.active = true
        }
    }

    LazyLoader {
        id: launcherLoader
        active: false
        Launcher {}
    }
    VolumeOsd {}
    BrightnessOsd {}
    MicOsd {}
    CapsLockOsd {}
    ZenOsd {}
    NotificationPopups {}
    ScreenshotPopup {}

    LazyLoader {
        id: wallpaperSwitcherLoader
        active: false
        WallpaperSwitcher {}
    }
    // settingswindow/ (Appearance/Wallpaper/Animations/Keybinds/
    // Displays/Network/Audio) was loaded here and is
    // deleted as of 2026-09-13. Its Keybinds pane was the only part of
    // it anything still reached — Conf's Learn › Keybindings row — and
    // that row became a searchable level of the menu itself, then the
    // window loaded below (keybinds/KeybindsPanel.qml) once the keys
    // outgrew the slab. Panels' openSettings/closeSettings/
    // toggleSettings and its "settings" IPC target outlived it by eight
    // days: they were left in place while quickshell/old still built
    // that window off the same shared services, that config went away
    // 2026-09-20, and they were deleted on 2026-09-21 once nothing
    // anywhere could answer them.

    // Visual-only preview, IPC-triggered only — see lockscreen/LockScreen.qml.
    LazyLoader {
        id: lockPreviewLoader
        active: false
        LockScreen {}
    }
    // "Conf", the omarchy-style nested menu (SUPER+SPACE):
    // one list, one level at a time, over everything this config can do.
    // Lazy like the windows above; its GlobalShortcut and IPC target live
    // on services/Panels.qml so the first press of a shell run works, and
    // it opens itself from Component.onCompleted the way Launcher does.
    LazyLoader {
        id: menuLoader
        active: false
        ConfMenu {}
    }
    // Every key this desktop binds, in one window wide enough to show
    // them all (keybinds/KeybindsPanel.qml, user request 2026-09-19).
    // The Conf menu's Learn › Keybindings row used to be a level of the
    // menu itself; it opens this instead, and hands over whatever was in
    // its filter at the time. That query is the reason this one needs
    // the wasInactive handoff the plain self-opening windows above don't
    // — `find` on a window that does not exist yet has nowhere to land,
    // exactly as with the installer below.
    LazyLoader {
        id: keybindsLoader
        active: false
        KeybindsPanel {}
    }
    // The right-edge network rail (user request 2026-09-16). Lazy like
    // the windows above and, like Launcher and the
    // Conf menu, it opens itself from Component.onCompleted — shell.qml
    // only ever builds it in response to an open/toggle request, so there
    // is no first-open handoff to get wrong.
    LazyLoader {
        id: networkLoader
        active: false
        NetworkPanel {}
    }
    // The right-edge notification rail (notifications/
    // NotificationHistoryPanel.qml, user request 2026-09-18) — the
    // history as a slide-out instead of only as a quick settings tab and
    // a dashboard card. Lazy and self-opening on the same contract as the
    // network rail directly above, which it is a sibling of in every
    // sense: same corner, same geometry, same motion.
    //
    // NotificationPopups above stays eager — the toasts have to be
    // listening before anything arrives. This only ever shows what they
    // already recorded.
    LazyLoader {
        id: notificationHistoryLoader
        active: false
        NotificationHistoryPanel {}
    }
    // The right-edge volume rail (volume/VolumePanel.qml, user request
    // 2026-09-21) — the sound controls as a slide-out instead of only as
    // two quick settings tabs. Lazy and self-opening on the same contract
    // as the two rails above, which it is a sibling of in every sense but
    // one: its card is only as tall as what is in it, where theirs are
    // three fifths of the column and all of it.
    LazyLoader {
        id: volumeLoader
        active: false
        VolumePanel {}
    }
    // The media card (media/MediaPanel.qml, user request 2026-09-22) —
    // the player under the bar's media module, in place of the hover
    // dropdown that module used to carry. Lazy and self-opening on the
    // same contract as the rails above; like the calendar, it hangs from
    // its own module rather than from the right edge, and which player it
    // is about is services/Media.qml's, which the bar module reads too.
    LazyLoader {
        id: mediaLoader
        active: false
        MediaPanel {}
    }
    // The right-edge battery rail (battery/BatteryPanel.qml, user request
    // 2026-09-21) — the charge, what it is doing, and the packs behind
    // the one number the bar averages. Lazy and self-opening on the same
    // contract as the three rails above, and content-sized like the
    // volume one.
    LazyLoader {
        id: batteryLoader
        active: false
        BatteryPanel {}
    }
    // The calendar (calendar/CalendarPanel.qml, user request 2026-09-21)
    // — the card under the bar's clock, in place of the hover dropdown
    // that module used to carry. Lazy and self-opening on the same
    // contract as the rails above; it just hangs from the middle of the
    // bar rather than from the right edge.
    LazyLoader {
        id: calendarLoader
        active: false
        CalendarPanel {}
    }
    // The clipboard window (clipboard/ClipboardPanel.qml, user request
    // 2026-09-21) — search over the top, the history down the left, the
    // selected entry in full on the right. Lazy and self-opening like
    // the rest; it spawns a cliphist process per open and per selection,
    // so most sessions should never build it.
    LazyLoader {
        id: clipboardLoader
        active: false
        ClipboardPanel {}
    }
    // The themes menu (theme/ThemesPanel.qml) — the wallpaper's own
    // palette and theme/Palettes.qml's eight named ones, as a card under
    // the bar's themes module. Lazy and self-opening on the same contract
    // as the calendar it is built like; it holds nothing but a list, so
    // the only reason it is lazy is that a session which never switches a
    // theme should never build it.
    LazyLoader {
        id: themesLoader
        active: false
        ThemesPanel {}
    }
    // The app installer (installer/AppInstaller.qml) — one search over
    // pacman, the AUR and Flathub. Lazy like the windows above: it
    // spawns three package queries per search and most sessions never
    // open it. Opens itself from Component.onCompleted for the request
    // that built it, and a query that came with that request is handed
    // over the same way the dashboard's first-open handoff above does,
    // since `find` on a window that does not exist yet has nowhere to
    // land.
    LazyLoader {
        id: installerLoader
        active: false
        AppInstaller {}
    }
    // The packages window (packages/PackagesWindow.qml) — the installer's
    // other half: what is already on the machine, and how to take it off.
    // Lazy for the same reason that one is (four pacman/flatpak queries
    // per build) and self-opening on the same contract.
    LazyLoader {
        id: packagesLoader
        active: false
        PackagesWindow {}
    }
    WallpaperPopup {}
    // Replaces PowerOrbMenu.qml per the "retire the orb,
    // one power menu" decision (see PowerMenuPopout.qml's own header).
    PowerMenuPopout {}
}
