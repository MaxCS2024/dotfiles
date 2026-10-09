import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

// main/common/ShellSurface.qml for the configs that run beside the bar
// (../launcher, ../clipboard; symlinked into each). The same interface and
// the same invariant, minus what ties a surface to the bar's
// services/Panels.qml: `surfaceName`, `firstOpenArg` and opening itself
// when built. Each of these configs has one window, built at startup and
// opened by its own shell.qml.
//
// The invariant, in short (main's header has the history): close() can't
// hide the window, it starts a timer that lets the fade finish. Reopening
// inside that fade must not let the timer hide a window that is back on
// screen, so open() stops the timer and the timer checks `shown`.
PanelWindow {
    id: root

    // The layershell namespace, which hypr/modules/windowrules.lua
    // matches on.
    required property string surfaceNamespace

    // What takes keyboard focus when the surface opens.
    property Item focusTarget: null

    readonly property bool shown: root._shown

    property int enterDuration: 280
    property int exitDuration: 200

    signal surfaceOpened(var arg)
    signal surfaceClosed()
    signal surfaceHidden()

    property bool _shown: false

    function open(arg) {
        hideTimer.stop()
        root.visible = true
        root._shown = true
        if (root.focusTarget) root.focusTarget.forceActiveFocus()
        focusGrab.active = true
        root.surfaceOpened(arg)
    }

    function close() {
        root._shown = false
        focusGrab.active = false
        hideTimer.restart()
        root.surfaceClosed()
    }

    function toggle() { root._shown ? root.close() : root.open(undefined) }

    // No default `anchors`: a grouped assignment in a derived surface adds
    // to what the base set rather than replacing it (see main's).
    color: "transparent"
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: root.surfaceNamespace

    Timer {
        id: hideTimer
        interval: root.exitDuration
        onTriggered: {
            if (root._shown) return
            root.visible = false
            root.surfaceHidden()
        }
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onCleared: root.close()
    }
}
