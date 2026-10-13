pragma Singleton

import Quickshell
import QtQuick

// Every setting the island has, in one file (AGENTS.md, Configuration).
// Save and Quickshell reloads.
Singleton {
    // ── Idle ──
    // "clock": a small pill with the time. "notch": a thin bar, no text.
    readonly property string idle: "clock"
    readonly property string clockFormat: "HH:mm"

    // ── Behaviour ──
    // "click" or "hover": what opens the expanded state.
    readonly property string expandOn: "click"
    // How long the pointer rests on the pill before it opens, with "hover".
    readonly property int hoverDelay: 300
    // How long the pointer is away before the expanded island closes.
    readonly property int collapseDelay: 400
    // How long a transient activity shows when it names no timeout.
    readonly property int transientTimeout: 2500

    // ── Profiles ──
    // Each activity type's interruption profile (AGENTS.md, Interruption
    // and motion): its priority, and how the pill moves when it arrives
    // and when it leaves. The research brief's starting points, to tune.
    //   enter, exit  ms the pill takes to morph in and out; exits shorter
    //   overshoot    one slight overshoot on arrival; high interruption only
    //   defer        ms a transient may wait for a break (a workspace
    //                switch, a focus change, a window closing) before it
    //                shows; 0 shows it at once
    // Privacy isn't in the queue, so it has no priority.
    readonly property var profiles: ({
        privacy:         { interruption: "high",   enter: 250, exit: 150, overshoot: true },
        urgent:          { interruption: "high",   priority: 70, enter: 280, exit: 180, overshoot: true },
        notification:    { interruption: "medium", priority: 60, enter: 280, exit: 180, overshoot: false, defer: 45000 },
        criticalBattery: { interruption: "high",   priority: 55, enter: 250, exit: 150, overshoot: true },
        osd:             { interruption: "low",    priority: 50, enter: 100, exit: 150, overshoot: false },
        hyprland:        { interruption: "low",    priority: 45, enter: 220, exit: 150, overshoot: false },
        battery:         { interruption: "low",    priority: 40, enter: 220, exit: 150, overshoot: false },
        // Low battery is the one battery event the user didn't cause:
        // it waits for a break. Charger notices answer the user at once.
        lowBattery:      { interruption: "low",    priority: 40, enter: 220, exit: 150, overshoot: false, defer: 45000 },
        ipc:             { interruption: "medium", priority: 30, enter: 250, exit: 180, overshoot: false, defer: 45000 },
        media:           { interruption: "low",    priority: 20, enter: 250, exit: 150, overshoot: false },
    })
    // For an activity that names no profile (the test queue's).
    readonly property var defaultProfile: ({ interruption: "medium", priority: 0, enter: 250, exit: 150, overshoot: false, defer: 0 })

    function profile(name) {
        return profiles[name] ?? defaultProfile
    }

    // Opening and closing the expanded state, and the pill fitting new
    // content without anything arriving or leaving (a longer title).
    readonly property int expandTime: 280
    readonly property int collapseTime: 180
    readonly property int resizeTime: 150

    // ── Features ──
    // Volume, microphone mute and brightness levels.
    readonly property bool osd: true
    // How long the OSD stays after the last change.
    readonly property int osdTimeout: 1500

    // The current MPRIS player: art and playing bars, controls when expanded.
    readonly property bool media: true
    // The playing bars: "still" (standing bars while it plays, flat when
    // paused), "subtle" (slow and small) or "dancing". Still by default:
    // constant motion at the edge of sight distracts.
    readonly property string mediaBars: "still"
    // How long a paused player stays in the island before it leaves.
    readonly property int mediaPausedTimeout: 60000

    // Charger in and out, charging done, low and critical.
    readonly property bool battery: true
    readonly property int batteryLowPercent: 20
    readonly property int batteryCriticalPercent: 5
    readonly property int batteryTimeout: 3000
    readonly property int batteryCriticalTimeout: 6000
    // Submap and keyboard layout changes.
    readonly property bool hyprlandEvents: true
    readonly property int hyprlandTimeout: 1500

    // Microphone, camera and screen in use: the dots and the announcement.
    // Off removes both; nothing else can.
    readonly property bool privacy: true
    // How long the island names the app when a device starts being used,
    // and when a dot is clicked.
    readonly property int privacyAnnounceTimeout: 2000
    readonly property int privacyListTimeout: 3000

    // ── Window ──
    // Distance from the top of the screen to the pill.
    readonly property int topMargin: 7
    // Reserve a strip the height of the compact pill so tiled windows
    // start below it. false lets the island float over them.
    readonly property bool reserveSpace: true

    // ── Colours ──
    readonly property color background: "black"
    readonly property color foreground: "white"
    readonly property color foregroundSoft: Qt.rgba(1, 1, 1, 0.6)
    readonly property color track: Qt.rgba(1, 1, 1, 0.2)
    // The privacy dots, which the brief fixes: orange, green, red.
    readonly property color privacyMic: "#ff9f0a"
    readonly property color privacyCamera: "#30d158"
    readonly property color privacyScreen: "#ff453a"

    function privacyColor(kind) {
        return kind === "mic" ? privacyMic : kind === "camera" ? privacyCamera : privacyScreen
    }

    // ── Type ──
    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 13
    readonly property int fontSizeSmall: 11
    readonly property int iconSize: 16
    readonly property int expandedIconSize: 32

    // ── Sizes ──
    // Space between the pill's ends and its content.
    readonly property int padX: 16
    readonly property int dotSize: 8
    readonly property int idleHeight: 24
    readonly property int notchWidth: 120
    readonly property int notchHeight: 8
    readonly property int compactHeight: 32
    readonly property int transientHeight: 40
    // Compact and transient pills fit their content within these.
    readonly property int minWidth: 160
    readonly property int maxWidth: 400
    readonly property int expandedWidth: 400
    readonly property int expandedHeight: 152
    // Corner radius once the pill is taller than twice this.
    readonly property int expandedRadius: 32
}
