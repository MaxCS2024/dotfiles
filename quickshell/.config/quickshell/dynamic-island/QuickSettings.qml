pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// The settings panel's quick settings, under its notch (AGENTS.md,
// Quick settings): Stay awake, Do not disturb, Night light and the
// microphone.
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
        command: ["systemd-inhibit", "--what=idle", "--who=Dynamic island",
            "--why=Stay awake", "--mode=block", "sleep", "infinity"]
    }

    // ── Do not disturb ──
    // dunst, which answers notifications under any shell, paused: it
    // holds them and shows them once unpaused. Read from dunst on start,
    // after a toggle and whenever the settings panel opens (`refresh`),
    // since `dunstctl` can change it from outside too.
    property bool dnd: false

    function toggleDnd() {
        dnd = !dnd
        setDnd.command = ["dunstctl", "set-paused", dnd ? "true" : "false"]
        setDnd.running = true
    }

    Process {
        id: setDnd
        onExited: readDnd.running = true
    }

    Process {
        id: readDnd
        running: true
        command: ["dunstctl", "is-paused"]
        stdout: StdioCollector {
            onStreamFinished: root.dnd = text.trim() === "true"
        }
    }

    function refresh() { readDnd.running = true }

    // ── Night light ──
    // hyprsunset (started by hypr/modules/autostart.lua) over hyprctl:
    // `temperature 4500` warms the screen, `identity` clears it. Saved in settings.json (`quick.nightLight`) and put back
    // when the island starts.
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

    // ── Microphone ──
    // The default source's mute, like the speaker segment above it.
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: root.source ? [root.source] : [] }
    readonly property bool micMuted: source && source.audio ? source.audio.muted : false

    function toggleMic() {
        if (source && source.audio)
            source.audio.muted = !source.audio.muted
    }
}
