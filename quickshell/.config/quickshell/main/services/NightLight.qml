pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Settings.nightLight is the persisted toggle; this is what actually
// drives it — same split as stayAwake (Settings holds the bool,
// bar/Bar.qml's IdleInhibitor does the real work) and dnd (Settings
// holds it, NotificationsButton.qml's own logic reacts to it).
//
// Unlike those two, the half that does the work here is a Singleton
// rather than an object sitting in the tree, so it is built the first
// time something names it and not before. Nothing displays this
// service — it only ever acts — so main/shell.qml names it explicitly
// to build it with the shell; see the comment there. Without that the
// Connections below never exist and the toggle flips a persisted bool
// that nothing applies.
//
// hyprsunset (hypr/modules/autostart.lua runs it as a long-lived
// daemon, same as awww-daemon/hypridle) is controlled live over
// hyprctl — `temperature <K>` applies a warm filter, `identity` clears
// it back to normal. No local state to poll back from hyprsunset
// itself, same reasoning as stayAwake/dnd: Settings.nightLight is the
// single source of truth, applied here, not read back from the tool.
Singleton {
    id: root

    readonly property int warmTemp: 4500

    // What the UI binds to and calls, so a toggle tile drives this
    // service the way the Bluetooth and Airplane tiles drive theirs
    // instead of reaching past it to Settings. Settings.nightLight
    // stays the single persisted source of truth — this is a window
    // onto it, not a second copy that could drift out of step with the
    // _apply() below.
    readonly property bool enabled: Settings.nightLight

    function toggle() { Settings.nightLight = !root.enabled }

    function _apply(on) {
        applyProc.command = on
            ? ["hyprctl", "hyprsunset", "temperature", String(root.warmTemp)]
            : ["hyprctl", "hyprsunset", "identity"]
        applyProc.running = false
        applyProc.running = true
    }

    Process { id: applyProc }

    Component.onCompleted: root._apply(Settings.nightLight)

    Connections {
        target: Settings
        function onNightLightChanged() { root._apply(Settings.nightLight) }
    }
}
