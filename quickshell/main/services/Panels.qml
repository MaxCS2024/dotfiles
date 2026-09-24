pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQml

// Replaces the four copies of openQuickSettingsTab() that shelled out to
// `qs ipc call` in order to talk to this same process.
//
// Also the single home for the external IPC surface (`qs ipc call
// <target> <fn>`, see the IpcHandlers at the bottom) for every window
// wrapped in a LazyLoader in shell.qml. An IpcHandler
// declared inside one of those windows would not exist — and therefore
// would not be reachable over IPC — until the window has loaded once
// through some other path, which would break e.g. Hyprland's SUPER+P
// launcher bind on the very first press after every shell restart.
// Centralizing here means the IPC target always exists.
Singleton {
    id: root

    signal wallpaperApplied(string path, bool success, string message)
    function notifyWallpaperApplied(path, success, message) {
        root.wallpaperApplied(path, success, message)
    }

    // ── Bar visibility ───────────────────────────────────
    // Runtime-only, deliberately not persisted through Settings'
    // per-monitor `enabled` flag (services/Settings.qml):
    // that one is the configured answer to "should this monitor have a
    // bar at all", while this is a transient "get it out of the way for
    // a moment" toggle, and a shell restart should bring the bar back
    // rather than leave the user with no bar and no obvious way to ask
    // for one. Applies to every monitor's bar at once — bar/Bar.qml ANDs
    // it with its own bar.cfg.enabled, so a monitor configured without a
    // bar stays without one either way.
    property bool barVisible: true

    // Not a panel: the bar is built eagerly and this mutates real state
    // rather than asking a window to appear, which is why it keeps a
    // function of its own rather than answering to toggle("bar").
    function toggleBar() { root.barVisible = !root.barVisible }
    function showBar() { root.barVisible = true }
    function hideBar() { root.barVisible = false }

    // Where the clock module's middle sits across the bar, as a fraction
    // of the bar's width — 0.5 for the centre row it lives in by default.
    // Published by bar/Clock.qml, read by the calendar card to place
    // itself under the module that opened it: the bar and the card are
    // separate layer-shell surfaces and neither can see the other's
    // geometry, the same reason rightRailWidth above is state here.
    //
    // A fraction rather than a pixel column so it survives the trip
    // between two surfaces that may not be the same width — the bar is
    // inset by 8 on each side when it floats, the card's window is not.
    property real clockAnchor: 0.5

    // Whether that card is up, so the clock's own hover pill can stay
    // lit while it is — which is what the dropdown's `visible` did for
    // it before.
    property bool calendarShown: false

    // The same pair again for the media card, published by
    // bar/MediaPlayer.qml and read by media/MediaPanel.qml, for the same
    // reason and with the same meaning. Its default is not 0.5: the media
    // module ships in the *left* row (Settings.barLayout), so a card that
    // opened at the middle before the bar had laid out would jump across
    // the screen on the first frame that told it otherwise.
    //
    // mediaShown additionally gates the position tick on services/Media
    // .qml, which is why it is a fact about the card rather than only a
    // hint for the pill: with the bar hidden, the card is the only thing
    // left that needs the clock running.
    property real mediaAnchor: 0.12
    property bool mediaShown: false

    // And for the earbuds card (earbuds/EarbudsPanel.qml), published by
    // bar/EarbudsButton.qml. Its module ships in the right row, beside the
    // battery.
    property real earbudsAnchor: 0.9
    property bool earbudsShown: false

    // How much of the right screen edge a rail is covering right now, its
    // own 8px inset included — 0 whenever none is showing.
    // notifications/NotificationPopups.qml reads this and steps the toast
    // column left by it, which is the only reason it is state on this
    // singleton rather than a detail private to a rail: they are separate
    // layer-shell surfaces that all anchor to the top right corner, and
    // none of them can see the other's geometry.
    //
    // Five rails set it now — network/NetworkPanel.qml, notifications/
    // NotificationHistoryPanel.qml, volume/VolumePanel.qml, battery/
    // BatteryPanel.qml and weather/WeatherPanel.qml — and they are never up together: each one's
    // open() closes the others, precisely because this single number
    // could not describe two cards in the same column anyway.
    //
    // Set by a Binding in each rail rather than assigned from its
    // open()/close(), so the reservation cannot outlive the window that
    // made it — a `when` that goes false, and a destroyed rail, both
    // restore the 0. That is why claiming the *group* below is a signal
    // and reserving the *width* here stays a Binding: one is an event,
    // the other is a fact about a window that has to die with it.
    property int rightRailWidth: 0

    // ── Right-edge rail group ─────────────────────────────
    // The four rails are mutually exclusive, for the reason above: they
    // anchor to the same corner at the same width, and one number cannot
    // describe two cards in the same column.
    //
    // Each rail used to enforce that itself by naming the other three in
    // its own open() — twelve calls for four rails, twenty for five, and
    // every one of them a line in a file that had nothing else to do
    // with the surface being added. A rail now announces which one it is
    // and closes itself when it hears a name that is not its own, so
    // adding a fifth rail edits nothing that already exists.
    signal rightRailClaimed(string name)
    function claimRightRail(name) { root.rightRailClaimed(name) }

    // ── Screen capture ─────────────────────────────
    // notifications/ScreenshotPopup.qml does the capturing for all three
    // modes ("region" | "window" | "screen") so a shot started from the
    // Conf menu gets the same file, clipboard copy, thumbnail and history
    // row as the Print key does. In-process relay only — that popup is
    // built eagerly and keeps its own "screenshot" IPC target, so there
    // is no second external surface for this here.
    signal captureRequested(string mode)

    function capture(mode) { root.captureRequested(mode || "region") }

    // ── External IPC surface for the four LazyLoader-wrapped windows ──
    // Moved here from each window's own IpcHandler — see
    // the file-level comment above for why.
    // `find` rather than `search`: `qs ipc` answers `show`, `wait`,
    // `listen` and `prop` itself, printing the target's interface and
    // exiting 0 without ever calling in, and a name that collides with
    // one of those is a function that silently never runs.
    IpcHandler {
        target: "apps"
        function open(): void { root.open("apps", undefined) }
        function close(): void { root.close("apps") }
        function toggle(): void { root.toggle("apps") }
        function find(text: string): void { root.open("apps", text) }
    }

    IpcHandler {
        target: "keybinds"
        function open(): void { root.open("keybinds", undefined) }
        function close(): void { root.close("keybinds") }
        function toggle(): void { root.toggle("keybinds") }
        function find(text: string): void { root.open("keybinds", text) }
    }

    // Not a LazyLoader-wrapped window like the targets above (the bar is
    // built eagerly in shell.qml), but exposed the same way so the bar
    // can be hidden/shown from a script, not just from the keybind —
    // `relay toggle bar` (relay/lib/toggle.sh) is the command that does.
    // open/close rather than show/hide: `qs ipc call bar show` never
    // dispatches on this Quickshell build (0.3.1) — it prints the
    // handler's function listing and returns, the same as an unknown
    // name — and open/close is what every handler above uses anyway.
    // `state` is not one of those swallowed names: qs ipc only claims
    // show, call, wait, listen and prop.
    //
    // These answer with the resulting state instead of void, the way
    // Notifications.qml's dnd handlers already do, so a caller learns
    // what it just did in the same round trip rather than having to ask
    // again — and so `relay toggle bar` has something to print. One
    // answer for the whole shell, not one per monitor, because
    // barVisible above is a single flag every bar reads.
    IpcHandler {
        target: "bar"
        function toggle(): string { root.toggleBar(); return root.barVisible ? "on" : "off" }
        function open(): string { root.showBar(); return "on" }
        function close(): string { root.hideBar(); return "off" }
        function state(): string { return root.barVisible ? "on" : "off" }
    }

    // ── GlobalShortcut ──────────────────────────────────────
    // The shell-side half of Hyprland's `global` dispatcher
    // (`hyprland_global_shortcuts_manager_v1`, confirmed present via
    // `strings` on this build's Hyprland binary — it's a Hyprland
    // protocol extension, not the cross-compositor wlr one, despite
    // living under the same `Quickshell.Hyprland` import as everything
    // else Hyprland-specific in this repo). Registered on this
    // singleton — always alive, same reasoning as the IpcHandlers above
    // — rather than inside any individual panel window, so the
    // shortcut exists for the whole shell run regardless of whether
    // that window has been lazily created yet.
    //
    // `hypr/modules/binds/apps.lua` binds the physical key to
    // `hl.dsp.global("quickshell:<name>")` instead of shelling out to
    // `qs ipc call` — one Wayland round-trip instead of a process spawn
    // per press. The IpcHandlers above stay regardless: still useful
    // for scripting from outside a keybind, just not the primary path
    // for these four anymore.
    //
    // Both the handlers and the shortcuts below are generated from one
    // table. Eleven IpcHandler blocks and ten GlobalShortcut blocks that
    // differed only in their strings became rows; what each row is *for*
    // stays with the row, which is where it was always describing.
    //
    // Adding a surface used to mean three signals, three functions, a
    // handler and a shortcut. The last two are now one line.
    //
    // `fn` is the suffix on this singleton's own open/close/toggle —
    // open()/close()/toggle() use it. Verbs are open/close/toggle
    // and nothing else, because `qs ipc` answers `show`, `wait`, `listen`
    // and `prop` itself: a function with one of those names is never
    // reached and exits 0 without saying so. The targets needing a
    // fourth verb (apps, keybinds) or returning state
    // rather than void (bar) are still written out by hand below —
    // they are genuinely different, not repetitive.
    readonly property var surfaces: [
        // SUPER+P (hypr/modules/binds/apps.lua).
        { ipc: "launcher", fn: "Launcher", shortcut: "launcher-toggle", desc: "Toggle the app launcher" },

        // SUPER+ALT+SPACE (hypr/modules/binds/apps.lua) — took that bind
        // over from a "systemsettings-toggle" shortcut that was deleted
        // with the panel it opened (2026-09-21). The bar is not a
        // LazyLoader-wrapped window and its IPC answers with state rather
        // than void, so it has a row for its shortcut but no `ipc`: its
        // handler is hand-written below.
        { fn: "Bar", shortcut: "bar-toggle", desc: "Show or hide the bar" },

        // SUPER+SPACE (hypr/modules/binds/apps.lua) — omarchy puts its
        // menu on SUPER+ALT+SPACE, which this config already spends on
        // the bar toggle above.
        { ipc: "menu", fn: "Menu", shortcut: "menu-toggle", desc: "Toggle the Conf menu" },

        // SUPER+SHIFT+T (hypr/modules/binds/apps.lua) — bound, unlike the
        // rails below, because the bar's themes module is only one of the
        // two ways in this one wants: picking a theme is done by eye, and
        // a key that opens the menu without first finding a 22px palette
        // in the bar is the point.
        { ipc: "themes", fn: "Themes", shortcut: "themes-toggle", desc: "Toggle the themes menu" },

        // The four rails, the calendar and the media card are unbound by
        // default: the bar's own modules are the primary way in (bar/
        // NetworkButton, NotificationsButton, VolumeButton,
        // BatteryButton, WeatherButton, Clock, MediaPlayer).
        // Registered anyway so `hl.dsp.global("quickshell:<name>")` is
        // available to hypr/modules/binds/ without touching this file
        // again. The volume *keys* stay where they are —
        // hypr/modules/binds/media.lua drives services/Volume.qml through
        // the OSD, which is the right surface for a key press.
        { ipc: "network", fn: "Network", shortcut: "network-toggle", desc: "Toggle the network rail" },
        { ipc: "notification-history", fn: "NotificationHistory", shortcut: "notifications-toggle", desc: "Toggle the notification rail" },
        { ipc: "volume", fn: "Volume", shortcut: "volume-toggle", desc: "Toggle the volume rail" },
        { ipc: "media", fn: "Media", shortcut: "media-toggle", desc: "Toggle the media player" },
        { ipc: "battery", fn: "Battery", shortcut: "battery-toggle", desc: "Toggle the battery rail" },
        { ipc: "weather", fn: "Weather", shortcut: "weather-toggle", desc: "Toggle the weather rail" },
        { ipc: "calendar", fn: "Calendar", shortcut: "calendar-toggle", desc: "Toggle the calendar" },
        { ipc: "earbuds", fn: "Earbuds", shortcut: "earbuds-toggle", desc: "Toggle the earbuds card" },

        // Unbound like the rails: the bar's clipboard module is the way
        // in (bar/ClipboardButton.qml). A `hl.dsp.global` bind is the
        // obvious home for the SUPER+V this config has never had.
        { ipc: "clipboard", fn: "Clipboard", shortcut: "clipboard-toggle", desc: "Toggle the clipboard window" },

        // IPC only, no shortcut.
        { ipc: "wallpaper", fn: "Wallpaper" },

        // Visual-only preview — see lockscreen/LockScreen.qml's own
        // header for why this stays IPC-only rather than a GlobalShortcut
        // on SUPER+L, which stays bound to the real `hyprlock`.
        { ipc: "lockscreen-preview", fn: "LockPreview" },

        // `ownHandler` keeps these out of the generated set below without
        // keeping them out of the table: they are surfaces like any other
        // and answer open/close/toggle like any other, but each has a
        // handler the generated trio cannot express — apps and keybinds
        // take a query, and the power
        // menu registers its own IPC and shortcut in
        // powermenu/PowerMenuPopout.qml because it is not lazily built.
        { ipc: "apps", fn: "Apps", ownHandler: true },
        { ipc: "keybinds", fn: "Keybinds", ownHandler: true },
        { ipc: "powermenu", fn: "PowerMenu", ownHandler: true }
    ]

    // ── One request, by name ────────────────────────────────
    // Every surface answers the same three verbs, so the interface is
    // per-operation rather than per-surface: open("network") instead of
    // openNetwork(). Fifteen triplets of signals and their functions
    // collapse into this.
    //
    // The cost is worth stating plainly: `openNetwork()` is a typo the
    // engine catches and `open("netwrok")` is not. _request() checks the
    // name against the table above and complains, which turns a silent
    // no-op into a line in the log — not as good as a compile error, and
    // the reason that table is the one list of what exists.
    signal panelRequested(string name, string verb, var arg)

    function open(name, arg) { root._request(name, "open", arg) }
    function close(name) { root._request(name, "close", undefined) }
    function toggle(name) { root._request(name, "toggle", undefined) }

    function _request(name, verb, arg) {
        const s = root._surfaceFor(name)
        if (!s) {
            console.warn("Panels: no surface named '" + name + "' (" + verb + ")")
            return
        }
        if (arg !== undefined && arg !== "") root._lastArgs[name] = arg
        root.panelRequested(name, verb, arg)
    }

    // The payload of the most recent request per surface, so a window
    // that was built *by* that request can still read what it carried.
    // The signal that caused shell.qml to create the item is the one the
    // item was not yet subscribed to hear.
    //
    // This is the third answer to that problem and the only one left. It
    // used to be solved three ways at once: a `wasInactive` handoff in
    // shell.qml calling find() on the fresh item, a value parked on this
    // singleton and read back in Component.onCompleted, and — for most
    // surfaces — nothing at all, because they carried no payload.
    // common/ShellSurface.qml reads this once when it opens itself.
    property var _lastArgs: ({})

    function argFor(name) { return root._lastArgs[name] }

    function _surfaceFor(ipcName) {
        for (const s of root.surfaces) if (s.ipc === ipcName) return s
        return null
    }

    // The delegate declares no properties of its own, on purpose:
    // IpcHandler builds its interface by looking at its own members, and
    // a property brings a change signal that it reports as "Signal
    // detected" and then trips over — the config does not finish loading.
    // The handler's own `target` carries the identity instead.
    Instantiator {
        model: root.surfaces.filter(s => s.ipc !== undefined && !s.ownHandler)
        delegate: IpcHandler {
            target: modelData.ipc
            function open(): void { root.open(target, undefined) }
            function close(): void { root.close(target) }
            function toggle(): void { root.toggle(target) }
        }
    }

    Instantiator {
        model: root.surfaces.filter(s => s.shortcut !== undefined)
        delegate: GlobalShortcut {
            appid: "quickshell"
            name: modelData.shortcut
            description: modelData.desc
            // The bar is the only row without a surface to ask for — it
            // is built eagerly and toggling it mutates state rather than
            // opening a window.
            onPressed: {
                if (modelData.ipc !== undefined) root.toggle(modelData.ipc)
                else root.toggleBar()
            }
        }
    }

    // ── Bar keyboard navigation ─────────────────────────────
    // Fired at every monitor's bar/Bar.qml at once; each instance
    // decides for itself whether to actually engage (only the one on
    // the currently focused monitor does — see that file's own comment).
    signal focusBarRequested()

    GlobalShortcut {
        appid: "quickshell"
        name: "bar-focus"
        description: "Focus the bar for keyboard navigation"
        onPressed: root.focusBarRequested()
    }
}
