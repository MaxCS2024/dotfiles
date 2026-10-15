import Quickshell
import QtQuick

// Snap layouts, as on Windows 11: drag a window to the top edge of a screen
// and a bar of layouts drops down under the island; let go over a zone and
// the window fills that part of the screen. Independent of the island. The
// drag is found by hypr/modules/snap.lua; the brief is AGENTS.md.
Scope {
    Variants {
        model: Quickshell.screens

        SnapBar {}
    }
}
