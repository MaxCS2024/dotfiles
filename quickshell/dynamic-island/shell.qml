import Quickshell
import QtQuick

// One island per screen, and the settings window. The design brief is
// AGENTS.md.
Scope {
    // Singletons load on first use; this one owns the SUPER+COMMA
    // shortcut and the `settings` IPC target, so it has to exist from
    // the start.
    readonly property var settings: SettingsWindow
    // Reverts a display trial left unconfirmed, and watches for screens
    // being plugged in.
    readonly property var localConfig: LocalConfig
    readonly property var displays: Displays
    // Writes the saved charge limit back if a battery forgot it.
    readonly property var power: PowerSettings
    // Puts the saved night light back.
    readonly property var quick: QuickSettings
    // Critical battery and disk-full notifications.
    readonly property var alerts: Alerts
    // Who is using the microphone, camera and screen (the dots).
    readonly property var privacy: Privacy

    Variants {
        model: Quickshell.screens

        Island {}
    }
}
