pragma Singleton
import Quickshell

// Every key this desktop binds, transcribed from hypr/modules/binds/*.lua.
//
// A transcription and not a reading: nothing in this process can ask
// Hyprland for its live bind table, so this list drifts the moment those
// files change without it. Re-check it against that directory rather
// than trusting it — binds.lua is the list of which files are even
// loaded, and monitor.lua is not on it (its SUPER+R rotate never binds,
// so it is not a row here).
//
// It has lived in three places. The old Settings window's Keybinds pane
// held it first, with no way to search it, in a window whose other six
// panes nothing else in this shell reached. menu/ConfMenu.qml's tree
// held it next, as a searchable level of the Conf slab — findable at
// last, but forty rows in a 410px-wide popup, where the longest names
// elided beside their keys. It lives here now because two things read
// it: keybinds/KeybindsPanel.qml, the window that shows all of it at
// once, and that same Conf row, which is a way *in* to that window and
// needs only the count.
//
// `keys` is the chord as a list of keycaps, not a string, because the
// panel renders it as [Super + Shift + J] and only this file knows where
// the pluses go. "Volume Up" and "Brightness Down" are one key each —
// the bare XF86 function keys — and splitting either on its space would
// invent a modifier that does not exist. A string would leave the view
// guessing at that; a list states it.
//
// Stored in the printed casing (Super, Shift, J) and shouted only at
// the point of display — see chord(). This file stays readable; the
// panel is where omarchy's house style gets applied.
//
// Groups are by what the key controls, which is nearly — but not quite
// — one Lua file each: window.lua, alt-fullscreen.lua, zen.lua and
// mouse.lua all land in Windows, and apps.lua splits between Apps and
// Shell. Nothing draws them as headings any more; they order the list
// and they answer a search for a category.
Singleton {
    id: root

    // Ordered the way omarchy's own keybindings menu orders its list
    // (bin/omarchy-menu-keybindings): not by config file, but by how
    // often you reach for the thing. Its priority table runs apps and
    // menus first (Terminal 2, Browser 3, File manager 4, Launch apps
    // 5, System menu 6), then window management (Full screen 8, Close
    // window 10, Focus 33, Resize window 35), then capture (23), then
    // workspaces (29–38), with the bare XF86 keys dead last at 99.
    // These six groups are laid out to match; within a group the order
    // is the group's own.
    readonly property var groups: [
        { label: "Apps", icon: "\u{F14DE}", binds: [
            { action: "Terminal", keys: ["Super", "Return"] },
            { action: "Browser", keys: ["Super", "B"] },
            { action: "File manager", keys: ["Super", "E"] },
            { action: "App launcher", keys: ["Super", "P"] }
        ]},

        // The shell's own surfaces, plus the session's own exit, which
        // apps.lua keeps beside them. Conf leads it: omarchy puts its
        // own menu at priority 1, above everything but the keybindings
        // list itself. Super Q was the Dashboard's row here until that
        // panel was deleted on 2026-09-21; the key is unbound now, so it
        // has no row rather than a row that does nothing.
        { label: "Shell", icon: "\u{F0A07}", binds: [
            { action: "Conf menu", keys: ["Super", "Space"] },
            { action: "Clipboard", keys: ["Super", "C"] },
            { action: "Themes menu", keys: ["Super", "Shift", "T"] },
            // These two were bound in apps.lua when the rails were built
            // and never transcribed here — exactly the drift the header
            // warns this file is prone to. Caught 2026-09-21 while adding
            // the clipboard row above.
            { action: "Network rail", keys: ["Super", "N"] },
            { action: "Notification rail", keys: ["Super", "Shift", "N"] },
            { action: "Power menu", keys: ["Super", "Escape"] },
            { action: "Show or hide the bar", keys: ["Super", "Alt", "Space"] },
            { action: "Focus the bar", keys: ["Super", "Shift", "B"] },
            { action: "Log out", keys: ["Super", "M"] }
        ]},

        // The longest group: four directions of focus and four of move
        // are eight rows rather than two ("Focus left/down/up/right",
        // "Super H J K L"), because a row that packs four keys into one
        // line is a row the filter can no longer find "focus up" in.
        { label: "Windows", icon: "\u{F05B2}", binds: [
            { action: "Close window", keys: ["Super", "W"] },
            { action: "Force-kill window", keys: ["Super", "Shift", "W"] },
            { action: "Toggle floating", keys: ["Super", "T"] },
            { action: "Zoom window", keys: ["Super", "F"] },
            { action: "Zen mode", keys: ["Super", "Shift", "F"] },
            { action: "Focus left", keys: ["Super", "H"] },
            { action: "Focus down", keys: ["Super", "J"] },
            { action: "Focus up", keys: ["Super", "K"] },
            { action: "Focus right", keys: ["Super", "L"] },
            { action: "Move window left", keys: ["Super", "Shift", "H"] },
            { action: "Move window down", keys: ["Super", "Shift", "J"] },
            { action: "Move window up", keys: ["Super", "Shift", "K"] },
            { action: "Move window right", keys: ["Super", "Shift", "L"] },
            { action: "Drag window", keys: ["Super", "Left-drag"] },
            { action: "Resize window", keys: ["Super", "Right-drag"] }
        ]},

        // Print goes through this shell's own capture path (the same one
        // Trigger › Screenshot uses); Shift+Print is media.lua's own
        // grim/slurp line, which writes the file as well as copying it.
        { label: "Screenshots", icon: "\u{F0E51}", binds: [
            { action: "Screenshot", keys: ["Print"] },
            { action: "Screenshot to file", keys: ["Shift", "Print"] }
        ]},

        { label: "Workspaces", icon: "\u{F0570}", binds: [
            { action: "Next workspace", keys: ["Super", "Tab"] },
            { action: "Cycle workspaces", keys: ["Super", "Scroll"] },
            { action: "Go to workspace", keys: ["Super", "1…0"] },
            { action: "Move to workspace", keys: ["Super", "Shift", "1…0"] },
            { action: "Toggle scratchpad", keys: ["Super", "S"] },
            { action: "Move to scratchpad", keys: ["Super", "Shift", "S"] },
            { action: "Reload Hyprland config", keys: ["Super", "Shift", "R"] }
        ]},

        // Bare function keys — no modifier, and `locked` in media.lua so
        // they still work on the lock screen. Last, the way omarchy puts
        // every XF86 key at the bottom of its own list.
        { label: "Media", icon: "\u{F057E}", binds: [
            { action: "Volume up", keys: ["Volume Up"] },
            { action: "Volume down", keys: ["Volume Down"] },
            { action: "Mute output", keys: ["Mute"] },
            { action: "Mute microphone", keys: ["Mic Mute"] },
            { action: "Brightness up", keys: ["Brightness Up"] },
            { action: "Brightness down", keys: ["Brightness Down"] },
            { action: "Play or pause", keys: ["Play"] },
            { action: "Next track", keys: ["Next"] },
            { action: "Previous track", keys: ["Previous"] },
            { action: "Toggle Wi-Fi", keys: ["RFKill"] }
        ]}
    ]

    readonly property int count: root.groups.reduce(
        (total, group) => total + group.binds.length, 0)

    // One lowercased haystack of every action and every key, built once.
    // The Conf menu's single Keybindings row searches this rather than
    // its own label, so typing "volume" or "super shift" there still
    // finds the keys — it just surfaces the one row that opens this
    // window instead of forty rows inside the slab. See
    // menu/ConfMenu.qml's `matches()`. Joined with spaces and not with
    // " + ", so "super shift" matches the way it always did — nobody
    // types the pluses.
    readonly property string searchText: root.groups.map(
        group => group.label + " " + group.binds.map(
            bind => bind.action + " " + bind.keys.join(" ")).join(" ")).join(" ").toLowerCase()

    // Every bind in one list, in group order. The groups above are
    // still how the source reads — they are what each key controls, and
    // they keep related keys next to each other here — but the panel
    // draws one flat full-width column now (user request 2026-09-19),
    // so a list is what it wants.
    readonly property var all: root.groups.reduce(
        (out, group) => out.concat(group.binds), [])

    // A chord the way omarchy writes one: SUPER SHIFT + B. Its
    // omarchy-menu-keybindings builds the same string —
    //
    //     key_combo = $1 " + " $2
    //     gsub(/^[ \t]*\+?[ \t]*/, "", key_combo)
    //
    // — where $1 is the modmask already upper-cased and space-joined
    // and $2 is the key, with that gsub stripping the leading " + " off
    // a bind that has no modifier at all. Here the last element of the
    // list is the key and everything before it is a modifier, so a bare
    // XF86 key ("Volume Up") comes out unadorned exactly as it does
    // there.
    function chord(bind) {
        const keys = bind.keys
        const mods = keys.slice(0, -1).join(" ")
        const key = keys[keys.length - 1]
        return (mods === "" ? key : mods + " + " + key).toUpperCase()
    }

    // The narrowing the window's field does, kept here so the panel
    // stays a view over this file rather than a second copy of the
    // rules.
    //
    // A group whose *name* matches contributes all of its binds: typing
    // "media" is asking for that whole group, and with the headings
    // gone this is the only way left to ask for one.
    function matching(query) {
        const needle = (query || "").trim().toLowerCase()
        if (needle === "") return root.all

        const out = []
        for (let i = 0; i < root.groups.length; i++) {
            const group = root.groups[i]
            const wholeGroup = group.label.toLowerCase().indexOf(needle) !== -1
            for (let j = 0; j < group.binds.length; j++) {
                const bind = group.binds[j]
                if (wholeGroup
                        || (bind.action + " " + bind.keys.join(" "))
                            .toLowerCase().indexOf(needle) !== -1)
                    out.push(bind)
            }
        }
        return out
    }
}
