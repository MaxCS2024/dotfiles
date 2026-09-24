pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Persisted user settings, on the same FileView-based pattern
// Notifications.qml already proves out (see its own comments for the
// load-then-write-guard rationale). PersistentProperties was considered
// first, per an earlier note here, but it turned out to share its
// Reloadable base with LazyLoader — that type exists specifically to
// survive a QML hot-reload, not a full process restart, so it wouldn't
// have met the actual requirement (`qs kill && qs` and a toggle still
// holds). Plain FileView-backed properties do.
Singleton {
    id: root

    readonly property string _path: Quickshell.dataPath("settings.json")

    // ── Settings — one property per setting, with a sane default ──
    property bool dnd: false
    property bool stayAwake: false
    property bool nightLight: false
    property bool rotateWallpaperHourly: true

    // ── Appearance ─────────────────────────────────────────
    // Colours are theme/Appearance.qml's, persisted in its own file.
    // These two are the drawing settings that aren't colours.
    property real barOpacity: 0.65
    property int cornerRadius: 2

    // Originally the hand-written rows Bar.qml used before this went
    // data-driven; module names are Modules.registry keys
    // (bar/Modules.qml) and new modules just get added to a row here as
    // they're built. Keyed by monitor name (`bar.modelData.name`), with
    // "default" as the fallback
    // every monitor without its own entry uses — see barLayoutFor()
    // below. This shipped flat (no monitor keying, `default`'s shape
    // directly) until per-monitor config arrived; _apply() below migrates an
    // old-shape settings.json on load rather than silently discarding it.
    //
    // Every name below has to be a key bar/Modules.qml actually
    // registers. This default named "keyboard", "mic" and "camera" until
    // 2026-09-20 — three modules main dropped when it was rebuilt
    // alongside old/ on 2026-09-08 and which have had nothing to build
    // them since. bar/Bar.qml filters names the registry doesn't know
    // (see knownModules() there), so the only symptom was a right row
    // that quietly came up with four of its seven slots, on any machine
    // new enough to have no settings.json of its own — a fresh install
    // or a new-config.sh experiment. The filter stays: a *saved* layout
    // can still name a module that has since been removed, and that is
    // the case this default no longer is.
    //
    // "themes" left this row on 2026-09-22 for a different reason: the
    // module was removed, not lost. Switching a palette is a row in the
    // conf menu's Style section (menu/ConfMenu.qml) and a shortcut, and
    // a bar icon for the same card was one way in too many. The saved
    // layout on this machine still names it, which the filter above
    // covers exactly as it does the three names before it.
    //
    // "voxtype" left the centre row on 2026-09-24 the same way: dictation
    // is shown by osd/VoxtypeOsd.qml, the Wispr Flow-style pill at the
    // bottom of the screen, and the bar's pill was the same state twice.
    //
    // "earbuds" (2026-09-24) sits beside the battery it opens the rail
    // of, and takes no room until Nothing earbuds connect.
    property var barLayout: ({
        default: {
            left: ["workspaces", "media"],
            center: ["clock"],
            right: ["tray", "weather", "network", "volume", "earbuds", "battery"]
        }
    })

    // Per-monitor bar position/floating/enabled/height.
    // Same "default" + per-monitor-override keying as barLayout above,
    // resolved through barConfigFor(). `height: 0` means "unset, use
    // whatever bar/Bar.qml defaults to" — keeping the number there and
    // a sentinel here leaves this file free of a Theme import (no reason
    // to depend on the matugen-derived, live-reloading Theme singleton,
    // and load-order between two singletons isn't worth relying on) and
    // leaves no second copy of the height to drift from the real one.
    property var barConfig: ({
        default: { enabled: true, position: "top", floating: false, height: 0 }
    })

    function barLayoutFor(monitorName) {
        const d = (root.barLayout && root.barLayout.default) || { left: [], center: [], right: [] }
        const m = root.barLayout && root.barLayout[monitorName]
        return m || d
    }

    function barConfigFor(monitorName) {
        const d = (root.barConfig && root.barConfig.default) || {}
        const m = (root.barConfig && root.barConfig[monitorName]) || {}
        return {
            enabled: m.enabled !== undefined ? m.enabled : (d.enabled !== undefined ? d.enabled : true),
            position: m.position || d.position || "top",
            floating: m.floating !== undefined ? m.floating : (d.floating !== undefined ? d.floating : false),
            height: m.height || d.height || 0
        }
    }

    function _snapshot() {
        return {
            dnd: root.dnd,
            stayAwake: root.stayAwake,
            nightLight: root.nightLight,
            rotateWallpaperHourly: root.rotateWallpaperHourly,
            barLayout: root.barLayout,
            barConfig: root.barConfig,
            barOpacity: root.barOpacity,
            cornerRadius: root.cornerRadius
        }
    }

    function _isStringArray(v) {
        return Array.isArray(v) && v.every(x => typeof x === "string")
    }

    function _isLayoutEntry(v) {
        return v && typeof v === "object"
            && root._isStringArray(v.left) && root._isStringArray(v.center) && root._isStringArray(v.right)
    }

    function _apply(data) {
        if (typeof data.dnd === "boolean") root.dnd = data.dnd
        if (typeof data.stayAwake === "boolean") root.stayAwake = data.stayAwake
        if (typeof data.nightLight === "boolean") root.nightLight = data.nightLight
        if (typeof data.rotateWallpaperHourly === "boolean") root.rotateWallpaperHourly = data.rotateWallpaperHourly

        if (typeof data.barOpacity === "number") root.barOpacity = data.barOpacity
        if (typeof data.cornerRadius === "number") root.cornerRadius = data.cornerRadius

        if (data.barLayout && typeof data.barLayout === "object") {
            const l = data.barLayout
            if (root._isLayoutEntry(l)) {
                // Pre-3.4 flat shape ({left,center,right} directly, no
                // monitor keying) — migrate it to `default` rather than
                // discarding a real user layout just because the schema
                // grew a level.
                root.barLayout = { default: { left: l.left, center: l.center, right: l.right } }
            } else {
                const migrated = {}
                for (const key in l) {
                    if (root._isLayoutEntry(l[key])) migrated[key] = l[key]
                }
                if (!migrated.default) migrated.default = root.barLayout.default
                root.barLayout = migrated
            }
        }

        if (data.barConfig && typeof data.barConfig === "object") {
            const c = data.barConfig
            const migrated = {}
            for (const key in c) {
                const entry = c[key]
                if (!entry || typeof entry !== "object") continue
                const clean = {}
                if (typeof entry.enabled === "boolean") clean.enabled = entry.enabled
                if (entry.position === "top" || entry.position === "bottom") clean.position = entry.position
                if (typeof entry.floating === "boolean") clean.floating = entry.floating
                if (typeof entry.height === "number") clean.height = entry.height
                migrated[key] = clean
            }
            if (!migrated.default) migrated.default = root.barConfig.default
            root.barConfig = migrated
        }
    }

    // The probe, the guarded first write, the corrupt-file fallback and
    // the debounce are services/JsonStore.qml's — its header has the two
    // hazards they answer, including why a file that does not exist yet
    // still needs its path set.
    JsonStore {
        id: store
        path: root._path
        snapshot: () => root._snapshot()
        onRestored: (data) => {
            if (data && typeof data === "object") root._apply(data)
        }
    }

    function _save() { store.save() }

    // ── IPC (relay toggle nightlight / awake) ───────────────
    // These two switches have no window of their own to be reached
    // through: night light only ever acts (services/NightLight.qml
    // pushes it at hyprsunset) and stay-awake is an IdleInhibitor
    // living on the bar, so neither had any way in from a script until
    // now. relay/lib/toggle.sh is what drives them.
    //
    // Set here rather than by calling NightLight.toggle(): Settings is
    // the single source of truth and NightLight is the applier watching
    // it (see that file's header), so reaching the other way would have
    // Settings depend on the service that already depends on it.
    //
    // A target per switch, named for the switch, the way every target
    // in Panels.qml is named for the window it opens — and answering
    // "on"/"off" like the bar's does, so one CLI can treat them all
    // alike. Unlike the bar's, these two persist: a flip from the CLI
    // outlives the session exactly as the same flip from the UI does.
    IpcHandler {
        target: "nightlight"
        function toggle(): string { root.nightLight = !root.nightLight; return root.nightLight ? "on" : "off" }
        function enable(): string { root.nightLight = true; return "on" }
        function disable(): string { root.nightLight = false; return "off" }
        function state(): string { return root.nightLight ? "on" : "off" }
    }

    // "awake", not "idle": the property is stayAwake, the quick settings
    // tile is "Coffee", and on/off has to mean one obvious thing. Under
    // the other name `relay toggle idle off` would mean "stay awake",
    // which is the kind of inversion that gets scripted backwards.
    // relay's toggle module points anyone who types `idle` at this instead.
    IpcHandler {
        target: "awake"
        function toggle(): string { root.stayAwake = !root.stayAwake; return root.stayAwake ? "on" : "off" }
        function enable(): string { root.stayAwake = true; return "on" }
        function disable(): string { root.stayAwake = false; return "off" }
        function state(): string { return root.stayAwake ? "on" : "off" }
    }

    onDndChanged: root._save()
    onStayAwakeChanged: root._save()
    // nightLight is in both _snapshot() and _apply() but had no _save()
    // hook, so flipping it on its own never reached disk — it persisted
    // only when some *other* setting happened to change in the same
    // session, which made it look like it saved sometimes. Found when
    // `relay toggle nightlight` gave it a way to be flipped by itself.
    onNightLightChanged: root._save()
    onRotateWallpaperHourlyChanged: root._save()
    onBarLayoutChanged: root._save()
    onBarConfigChanged: root._save()
    onBarOpacityChanged: root._save()
    onCornerRadiusChanged: root._save()
}
