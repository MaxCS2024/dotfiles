import Quickshell
import QtQuick

// The settings window on its own, so it opens with whatever shell runs
// (`qs -c settings`, started from hypr/modules/autostart.lua), like the
// clipboard. Split out of the dynamic-island on 2026-10-13. The design
// brief is AGENTS.md.
Scope {
    // Singletons load on first use. The window owns SUPER+COMMA and the
    // `settings` IPC target, so it has to exist from the start; the rest
    // do their jobs at login.
    readonly property var settings: SettingsWindow
    // Reverts a display trial left unconfirmed, and watches for screens
    // being plugged in.
    readonly property var localConfig: LocalConfig
    readonly property var displays: Displays
    // Writes the saved charge limit back if a battery forgot it.
    readonly property var power: PowerSettings
    // Puts the saved night light back.
    readonly property var quick: QuickSettings
}
