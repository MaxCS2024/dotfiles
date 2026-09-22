pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// "Which keyboard layout is active." Quickshell.Hyprland has no typed
// API for this at 0.3.1 (checked: no devices/keyboards/activeLayout
// exports), so this reads Hyprland's raw event stream instead — the
// event shape was confirmed live, not assumed from docs: temporarily
// configured a second layout (`hyprctl keyword` doesn't work on this
// Lua-config build — "can't work with non-legacy parsers" — used
// hypr/modules/input.lua directly + `hyprctl reload`, reverted after),
// listened on Hyprland's own raw event socket
// (`.socket2.sock`) while switching, and got
// `activelayout>>at-translated-set-2-keyboard,English (US)` — then
// confirmed the exact same text arrives via
// Hyprland.rawEvent(event) as event.name === "activelayout" and
// event.data === "at-translated-set-2-keyboard,English (US)".
Singleton {
    id: root

    property string currentLayout: ""

    // Comes from the configured kb_layout option (a comma-separated
    // list), not from counting distinct layouts seen over rawEvent —
    // with only one layout configured, no activelayout event ever
    // fires at all, so there'd be nothing to count from events alone.
    property int layoutCount: 1

    Component.onCompleted: {
        countProc.running = true
        devicesProc.running = true
    }

    Process {
        id: countProc
        command: ["sh", "-c", "hyprctl getoption input:kb_layout -j 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    const str = parsed.str || ""
                    root.layoutCount = str.split(",").filter(s => s.length > 0).length
                } catch (e) {
                    root.layoutCount = 1
                }
            }
        }
    }

    // Initial active layout at startup — rawEvent only fires on a
    // *switch*, so without this the indicator would show nothing until
    // the first switch after the shell starts.
    Process {
        id: devicesProc
        command: ["sh", "-c", "hyprctl devices -j 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    const kb = (parsed.keyboards || []).find(k => k.main)
                    if (kb) root.currentLayout = kb.active_keymap || ""
                } catch (e) {}
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return
            const comma = event.data.indexOf(",")
            if (comma === -1) return
            root.currentLayout = event.data.slice(comma + 1)
        }
    }

    // hl.dsp has no switchxkblayout wrapper on this Lua-config build
    // (confirmed live: dispatching hl.dsp.switchxkblayout(...) errors
    // "attempt to call a nil value") — exec_cmd shelling out to the
    // real hyprctl dispatcher is the working escape hatch, same pattern
    // already used for `hl.dsp.exec_cmd("hyprctl reload")` elsewhere in
    // this config.
    function cycle() {
        Hyprland.dispatch("hl.dsp.exec_cmd('hyprctl switchxkblayout all next')")
    }
}
