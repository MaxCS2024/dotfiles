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

    // ── Features ──
    // Volume, microphone mute and brightness levels.
    readonly property bool osd: true
    // How long the OSD stays after the last change.
    readonly property int osdTimeout: 1500

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

    // ── Type ──
    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 13
    readonly property int iconSize: 16
    readonly property int expandedIconSize: 32

    // ── Sizes ──
    // Space between the pill's ends and its content.
    readonly property int padX: 16
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
