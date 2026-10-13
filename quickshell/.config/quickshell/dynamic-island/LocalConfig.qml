pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// This machine's own settings from the settings window (AGENTS.md,
// Settings window › Saving). They are kept as JSON in
// ~/.local/state/dynamic-island/settings.json and turned into
// ~/.config/hypr/local.lua, which hyprland.lua loads last. The Lua file
// is only ever generated from the JSON; the JSON is the record.
//
// `save(next)` writes both and reloads Hyprland. `trial(next)` writes
// only local.lua, after backing up the old one to local.lua.bak, and
// reloads; `keep()` then saves the JSON and drops the backup, `revert()`
// rebuilds local.lua from the saved settings and drops it. A backup
// still there at startup is a trial nobody kept (the island stopped
// mid-countdown), so it is put back. `saveInput(input)` saves the input
// settings and reloads without re-applying the monitors; during a trial
// it leaves the backup alone and goes into the trial too.
Singleton {
    id: root

    readonly property string hyprDir: Quickshell.env("HOME") + "/.config/hypr"
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/dynamic-island"

    // { displays: { monitors: { "<desc:… or port>": entry }, laptopOffDocked: bool },
    //   input: { layouts: ["se", …], switchKey, repeatDelay, repeatRate,
    //            tapToClick, naturalScroll, disableWhileTyping, touchpadSpeed,
    //            touchpads: ["<hyprland device name>", …], mouseSpeed, mouseAccel },
    //   power: { lockAfter, screenOffAfter, suspendAfter (seconds, 0 = never),
    //            chargeLimit (percent, 100 = none) } }
    // A display entry: { name, laptop, mode, position, scale, transform, disabled, mirror }.
    // Only what the user has set is there; the rest stays the repo's.
    property var settings: ({})
    property bool loaded: false
    // The settings being tried, saved on keep().
    property var pending: null

    Process {
        running: true
        command: ["sh", "-c", 'cd "$1" && if [ -f local.lua.bak ]; then mv local.lua.bak local.lua && hyprctl reload >/dev/null; echo reverted >&2; fi; cat "$2/settings.json" 2>/dev/null', "sh", root.hyprDir, root.stateDir]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.settings = text.trim() ? JSON.parse(text) : {}
                } catch (e) {
                    console.warn("LocalConfig: unreadable settings.json, starting empty:", e)
                    root.settings = {}
                }
                root.loaded = true
            }
        }
    }

    function save(next) {
        settings = next
        pending = null
        write(true, lua(next), true, false)
    }

    function trial(next) {
        pending = next
        // A second trial during a countdown keeps the first backup: that
        // one is what was last kept.
        run('cd "$1" && { [ -f local.lua.bak ] || cp local.lua local.lua.bak 2>/dev/null || : > local.lua.bak; }'
            + ' && printf "%s" "$2" > local.lua.tmp && mv local.lua.tmp local.lua && hyprctl reload >/dev/null',
            [hyprDir, lua(next)])
    }

    function keep() {
        if (pending)
            // Only the displays come from the trial; anything saved
            // during the countdown (input, power) stays as saved.
            save(Object.assign({}, settings, { displays: pending.displays }))
    }

    function revert() {
        pending = null
        write(false, lua(settings), true, false)
    }

    function saveInput(input) {
        settings = Object.assign({}, settings, { input: input })
        if (pending)
            pending = Object.assign({}, pending, { input: input })
        write(true, lua(pending || settings), !pending, true)
    }

    // The idle timers go to hypridle.local.conf, which hypridle.conf
    // sources; hypridle reads its config only at start, so it is
    // restarted. The charge limit is written by PowerSettings itself.
    function savePower(power) {
        settings = Object.assign({}, settings, { power: power })
        const lines = [
            "# This machine's idle timers, written by the dynamic island's settings",
            "# window (Power) from ~/.local/state/dynamic-island/settings.json.",
            "# Seconds; empty means never. Read by hypridle.conf; ignored by git.",
        ]
        for (const [key, name] of [["lockAfter", "lock_after"], ["screenOffAfter", "screen_off_after"], ["suspendAfter", "suspend_after"]])
            if (power[key] !== undefined)
                lines.push("$" + name + " = " + (power[key] > 0 ? Math.round(power[key]) : ""))
        run('mkdir -p "$1" && printf "%s" "$2" > "$1/settings.json.tmp" && mv "$1/settings.json.tmp" "$1/settings.json"'
            + ' && printf "%s" "$4" > "$3/hypridle.local.conf.tmp" && mv "$3/hypridle.local.conf.tmp" "$3/hypridle.local.conf"'
            + ' && { pkill -x hypridle; sleep 0.3; setsid -f hypridle >/dev/null 2>&1; }',
            [stateDir, JSON.stringify(settings, null, 2) + "\n", hyprDir, lines.join("\n") + "\n"])
    }

    // Saves settings.json alone (the charge limit).
    function saveJson() {
        run('mkdir -p "$1" && printf "%s" "$2" > "$1/settings.json.tmp" && mv "$1/settings.json.tmp" "$1/settings.json"',
            [stateDir, JSON.stringify(settings, null, 2) + "\n"])
    }

    // Writes settings.json (when `json`) and local.lua, drops the trial
    // backup (when `dropBackup`), and reloads Hyprland, without the
    // monitors when `configOnly`.
    function write(json, luaText, dropBackup, configOnly) {
        run((json ? 'mkdir -p "$1" && printf "%s" "$2" > "$1/settings.json.tmp" && mv "$1/settings.json.tmp" "$1/settings.json" && ' : '')
            + 'cd "$3" && ' + (dropBackup ? 'rm -f local.lua.bak && ' : '')
            + 'printf "%s" "$4" > local.lua.tmp && mv local.lua.tmp local.lua && hyprctl reload $5 >/dev/null',
            [stateDir, JSON.stringify(settings, null, 2) + "\n", hyprDir, luaText, configOnly ? "config-only" : ""])
    }

    function run(script, args) {
        Quickshell.execDetached(["sh", "-c", script, "sh"].concat(args))
    }

    // ── local.lua ──

    function str(s) {
        return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"'
    }

    // The fields of one hl.monitor() call, without the braces.
    function monitorFields(output, e, disabled) {
        const f = ["output = " + str(output)]
        if (disabled === true)
            return f.concat(["disabled = true"]).join(", ")
        f.push("mode = " + str(e.mode || "preferred"))
        f.push("position = " + str(e.position || "auto"))
        f.push("scale = " + (e.scale || 1))
        f.push("transform = " + (e.transform || 0))
        if (e.mirror)
            f.push("mirror = " + str(e.mirror))
        if (disabled !== undefined && disabled !== false)
            f.push("disabled = " + disabled)
        return f.join(", ")
    }

    function lua(s) {
        const lines = [
            "-- This laptop's own settings, written by the dynamic island's settings",
            "-- window from ~/.local/state/dynamic-island/settings.json. Edits here",
            "-- are overwritten on its next save. Loaded last by hyprland.lua, so",
            "-- these win over the repo's defaults; ignored by git.",
            "",
        ]
        const d = s.displays || {}
        const monitors = d.monitors || {}
        const outputs = Object.keys(monitors).sort()
        const dock = d.laptopOffDocked === true
        const laptops = outputs.filter(o => monitors[o].laptop)

        const fixed = outputs.filter(o => !(dock && monitors[o].laptop))
        if (fixed.length > 0) {
            lines.push("-- Displays, kept per monitor by its description, so each gets its")
            lines.push("-- settings back whenever it is connected.")
            for (const o of fixed)
                lines.push("hl.monitor({ " + monitorFields(o, monitors[o], monitors[o].disabled) + " })")
            lines.push("")
        }

        if (dock && laptops.length > 0) {
            lines.push(
                "-- Laptop screen off while an external screen is connected. Checked",
                "-- whenever a screen comes or goes; a mirror or a screen turned off",
                "-- doesn't count, nor does the one being unplugged.",
                "local laptops = {")
            for (const o of laptops)
                lines.push("\t{ " + monitorFields(o, monitors[o]) + (monitors[o].disabled ? ", off = true" : "") + " },")
            lines.push(
                "}",
                "",
                "local function isLaptop(name)",
                "\treturn name:match(\"^eDP\") or name:match(\"^LVDS\") or name:match(\"^DSI\")",
                "end",
                "",
                "local function dock(gone)",
                "\tlocal docked = false",
                "\tfor _, m in ipairs(hl.get_monitors()) do",
                "\t\tif not isLaptop(m.name) and not m.is_mirror and m.name ~= gone then",
                "\t\t\tdocked = true",
                "\t\tend",
                "\tend",
                "\tfor _, rule in ipairs(laptops) do",
                "\t\tlocal spec = {}",
                "\t\tfor k, v in pairs(rule) do",
                "\t\t\tif k ~= \"off\" then spec[k] = v end",
                "\t\tend",
                "\t\tspec.disabled = docked or rule.off == true",
                "\t\thl.monitor(spec)",
                "\tend",
                "end",
                "",
                "dock(nil)",
                "hl.on(\"monitor.added\", function() dock(nil) end)",
                "hl.on(\"monitor.removed\", function(m) dock(m and m.name) end)",
                "")
        }
        lines.push(...inputLua(s.input || {}))
        return lines.join("\n")
    }

    function inputLua(i) {
        const input = []
        const touchpad = []
        if (i.layouts && i.layouts.length > 0) {
            input.push("kb_layout = " + str(i.layouts.join(",")))
            input.push("kb_variant = " + str(i.layouts.map(() => "").join(",")))
            // With two or more layouts a switch key is always written:
            // Alt+Shift unless another was picked (the page shows it as
            // the default, so it must be the one that works).
            input.push("kb_options = " + str(i.layouts.length > 1 ? (i.switchKey || "grp:alt_shift_toggle") : ""))
        }
        if (i.repeatDelay !== undefined)
            input.push("repeat_delay = " + Math.round(i.repeatDelay))
        if (i.repeatRate !== undefined)
            input.push("repeat_rate = " + Math.round(i.repeatRate))
        if (i.mouseSpeed !== undefined)
            input.push("sensitivity = " + i.mouseSpeed.toFixed(2))
        if (i.mouseAccel !== undefined)
            input.push("accel_profile = " + str(i.mouseAccel ? "adaptive" : "flat"))
        if (i.tapToClick !== undefined)
            touchpad.push("tap_to_click = " + i.tapToClick)
        if (i.naturalScroll !== undefined)
            touchpad.push("natural_scroll = " + i.naturalScroll)
        if (i.disableWhileTyping !== undefined)
            touchpad.push("disable_while_typing = " + i.disableWhileTyping)
        if (touchpad.length > 0)
            input.push("touchpad = { " + touchpad.join(", ") + " }")

        const lines = []
        if (input.length > 0) {
            lines.push("-- Keyboard, touchpad and mouse.")
            lines.push("hl.config({")
            lines.push("\tinput = {")
            for (const l of input)
                lines.push("\t\t" + l + ",")
            lines.push("\t},")
            lines.push("})")
            lines.push("")
        }
        // Hyprland has no touchpad-wide speed, only a device's own, so
        // each touchpad found gets one. It keeps libinput's adaptive
        // acceleration even when the mouse's is off.
        const pads = i.touchpads || []
        if (pads.length > 0 && (i.touchpadSpeed !== undefined || i.mouseAccel === false || i.mouseSpeed !== undefined)) {
            lines.push("-- Touchpad speed, per touchpad (Hyprland has no touchpad-wide one).")
            for (const name of pads)
                lines.push("hl.device({ name = " + str(name) + ", sensitivity = " + (i.touchpadSpeed || 0).toFixed(2)
                    + ", accel_profile = \"adaptive\" })")
            lines.push("")
        }
        return lines
    }
}
