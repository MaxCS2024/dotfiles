pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The settings window's Input section (AGENTS.md, Settings window ›
// Input): keyboard layouts and repeat, the touchpad, the mouse. Saved
// in LocalConfig's `input` and applied with a reload, 400ms after the
// last change so a dragged slider reloads Hyprland once. Anything not
// saved yet shows Hyprland's current value (`runtime`).
Singleton {
    id: root

    property var runtime: ({})
    // Hyprland's names for the touchpads (udev's ID_INPUT_TOUCHPAD).
    property var touchpads: []
    // Every XKB layout: [{ code, name }], by name.
    property var allLayouts: []
    // Changes not saved yet.
    property var draft: null

    readonly property var saved: LocalConfig.settings.input || ({})

    // The keys that switch layouts. Not Win+Space (SUPER+SPACE opens
    // Conf) and not Right Alt (Swedish needs AltGr for @, { and [).
    readonly property var switchKeys: [
        { label: "Alt+Shift", value: "grp:alt_shift_toggle" },
        { label: "Ctrl+Shift", value: "grp:ctrl_shift_toggle" },
        { label: "Caps Lock", value: "grp:caps_toggle" },
        { label: "Both Shifts", value: "grp:shifts_toggle" },
    ]

    // What a reset goes back to: Hyprland's own defaults (the repo
    // doesn't set these). Shown at once after a reset, rather than the
    // runtime value, which is the old one until the reload is read.
    readonly property var defaults: ({ repeatDelay: 600, repeatRate: 25 })

    function value(key) {
        const d = draft || saved
        if (d[key] !== undefined)
            return d[key]
        return defaults[key] !== undefined ? defaults[key] : runtime[key]
    }

    function set(key, v) {
        const next = Object.assign({}, draft || saved)
        next[key] = v
        next.touchpads = touchpads
        draft = next
        saveSoon.restart()
    }

    // Back to the default: the key leaves local.lua, so the repo's value
    // (or Hyprland's own) applies again.
    function unset(key) {
        const next = Object.assign({}, draft || saved)
        delete next[key]
        next.touchpads = touchpads
        draft = next
        saveSoon.restart()
    }

    function isSet(key) {
        return (draft || saved)[key] !== undefined
    }

    function layoutName(code) {
        const l = allLayouts.find(l => l.code === code)
        return l ? l.name : code
    }

    Timer {
        id: saveSoon
        interval: 400
        onTriggered: {
            LocalConfig.saveInput(root.draft)
            root.draft = null
            rereadSoon.restart()
        }
    }

    // After the reload, Hyprland's values again: a key that went back to
    // its default shows the default.
    Timer {
        id: rereadSoon
        interval: 800
        onTriggered: root.refresh()
    }

    // Hyprland's values through its Lua REPL, one per line, then "@@" and
    // the touchpads' names as Hyprland spells them (lower case, dashes).
    Process {
        id: query
        command: ["sh", "-c", 'hyprctl repl "$1"; echo; echo @@; for e in /sys/class/input/event*; do udevadm info -q property -p "$e" 2>/dev/null | grep -q "^ID_INPUT_TOUCHPAD=1" && tr "A-Z " "a-z-" < "$e/device/name"; done', "sh",
            'local c = hl.get_config; local t = {}; for _, k in ipairs({ "input.kb_layout", "input.kb_options", "input.repeat_delay", "input.repeat_rate", "input.sensitivity", "input.accel_profile", "input.touchpad.tap_to_click", "input.touchpad.natural_scroll", "input.touchpad.disable_while_typing" }) do t[#t + 1] = tostring(c(k)) end; return table.concat(t, "\\n")']
        stdout: StdioCollector {
            onStreamFinished: root.read(text)
        }
    }

    function refresh() {
        query.running = true
    }

    function read(text) {
        const [values, pads] = text.split("@@")
        const v = values.trim().split("\n")
        if (v.length < 9)
            return
        const grp = v[1].split(",").find(o => o.startsWith("grp:")) || ""
        runtime = {
            layouts: v[0].split(",").filter(l => l !== ""),
            switchKey: grp || "grp:alt_shift_toggle",
            repeatDelay: parseInt(v[2]) || 600,
            repeatRate: parseInt(v[3]) || 25,
            mouseSpeed: parseFloat(v[4]) || 0,
            mouseAccel: v[5] !== "flat",
            tapToClick: v[6] === "true",
            naturalScroll: v[7] === "true",
            disableWhileTyping: v[8] === "true",
            touchpadSpeed: 0,
        }
        touchpads = (pads || "").split("\n").map(l => l.trim()).filter(l => l !== "")
    }

    // evdev.lst's "! layout" section: "  se   Swedish".
    Process {
        running: true
        command: ["sh", "-c", "awk '/^! layout/{p=1;next} /^!/{p=0} p&&NF' /usr/share/X11/xkb/rules/evdev.lst"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.allLayouts = text.split("\n").map(l => {
                    const m = /^\s*(\S+)\s+(.+)$/.exec(l)
                    return m ? { code: m[1], name: m[2].trim() } : null
                }).filter(l => l).sort((a, b) => a.name.localeCompare(b.name))
            }
        }
    }

    Component.onCompleted: refresh()
}
