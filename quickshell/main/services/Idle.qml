pragma Singleton
import Quickshell
import Quickshell.Wayland
import QtQuick

// Quickshell.Wayland.IdleMonitor wraps ext-idle-notify-v1
// (the compositor telling clients "no input for N seconds"), a
// different, unrelated Wayland protocol from IdleInhibitor's
// zwp_idle_inhibit_manager_v1 (a client telling the compositor "don't
// idle while I'm visible" — already used by bar/Bar.qml for
// Settings.stayAwake). `respectInhibitors: true` is what bridges them —
// verified live, but only after an initial false negative worth
// recording: a quick throwaway probe that created the IdleInhibitor and
// IdleMonitor in the same Component.onCompleted tick showed `isIdle`
// firing right on schedule regardless of the inhibitor, twice.
// The real test — toggling a real IdleInhibitor on well after both
// objects already existed and had settled — told the opposite story:
// `isIdle` flipped straight back to false the instant the inhibitor
// turned on, and stayed false for the rest of a 20s window. Most likely
// explanation: the inhibitor's Wayland request hadn't round-tripped to
// the compositor yet by the time the freshly-created monitor's own
// timer started, in that first same-tick probe — a startup race, not a
// real gap in `respectInhibitors`. bar/Bar.qml's inhibitor has existed
// since shell startup by the time anyone could plausibly go idle, so
// production doesn't hit that race. Confirmed end to end against the
// real bar too: `Settings.stayAwake: true` held `isIdle` false for 45+
// seconds past the configured timeout; flipping it back to `false`
// let idle fire on the very next timeout, right on schedule.
Singleton {
    id: root

    readonly property int timeoutSeconds: 120

    IdleMonitor {
        id: monitor
        enabled: true
        timeout: root.timeoutSeconds
        respectInhibitors: true
    }

    readonly property bool isIdle: monitor.isIdle
}
