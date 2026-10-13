pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The dynamic-island's quick settings, the two the settings window still
// needs since the split (2026-10-13): Stay awake, which the Power page's
// idle timers honour, and Night light, put back at login. Do not disturb
// (dunstctl) and the microphone toggle were the pill's and stayed there.
Singleton {
    id: root

    // ── Stay awake ──
    // A systemd idle lock, which hypridle honours (its
    // ignore_systemd_inhibit is off), held for as long as this is on. Not
    // saved: a Stay awake forgotten past a restart would keep the laptop
    // up on battery. Held by a process, not an IdleInhibitor on the
    // island's surface, so it keeps working while the island is hidden.
    property bool stayAwake: false

    function toggleStayAwake() { stayAwake = !stayAwake }

    Process {
        running: root.stayAwake
        command: ["systemd-inhibit", "--what=idle", "--who=Settings",
            "--why=Stay awake", "--mode=block", "sleep", "infinity"]
    }

    // ── Night light ──
    // hyprsunset (started by hypr/modules/autostart.lua) over hyprctl:
    // `temperature 4500` warms the screen, `identity` clears it; main's
    // warmth. Saved in settings.json (`quick.nightLight`) and put back
    // when this config starts.
    readonly property int warmth: 4500
    readonly property bool nightLight: (LocalConfig.settings.quick || {}).nightLight === true

    function toggleNightLight() {
        const on = !nightLight
        LocalConfig.settings = Object.assign({}, LocalConfig.settings,
            { quick: Object.assign({}, LocalConfig.settings.quick || {}, { nightLight: on }) })
        LocalConfig.saveJson()
        applyNightLight(on)
    }

    function applyNightLight(on) {
        Quickshell.execDetached(on
            ? ["hyprctl", "hyprsunset", "temperature", String(warmth)]
            : ["hyprctl", "hyprsunset", "identity"])
    }

    function restore() {
        if (LocalConfig.loaded && nightLight)
            applyNightLight(true)
    }

    Connections {
        target: LocalConfig
        function onLoadedChanged() { root.restore() }
    }

    Component.onCompleted: restore()
}
