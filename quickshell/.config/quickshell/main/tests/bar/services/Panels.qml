pragma Singleton
import Quickshell
import QtQuick

// Stands in for services/Panels.qml: the flag and signal Bar.qml reads,
// without the GlobalShortcuts, which would fight main's for SUPER+SHIFT+B.
Singleton {
    // Starts hidden, so the bar maps inert (no reserved strip, no input)
    // and only takes space for the tests that show it.
    property bool barVisible: false
    signal focusBarRequested()
}
