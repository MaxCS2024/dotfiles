import Quickshell
import QtQuick

// Snap layouts, as on Windows 11: drag a window to the bottom edge of a
// screen and a bar of layouts slides up; let go over a zone and
// the window fills that part of the screen. Independent of the island. The
// drag is found by hypr/modules/snap.lua; the brief is AGENTS.md.
Scope {
    Variants {
        model: Quickshell.screens

        SnapBar {}
    }
}
