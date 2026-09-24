import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "../config"
import "../services"

// A dismissible shell surface: the window under every panel, rail, card
// and overlay you open, look at, and dismiss. Fifteen files were their
// own copy of this until 2026-09-21.
//
// ── The invariant this exists to hold ────────────────────
// A surface closes on an animation, so close() cannot hide the window —
// it has to start a timer and let the fade finish first. That timer is a
// loaded gun: reopen the surface before it fires and it hides a window
// that is now supposed to be on screen. `visible` goes false while
// `shown` stays true, which leaves the next toggle calling close() on
// something already gone, and the press after *that* is the one that
// brings it back. Two presses, and nothing in the log.
//
// There are two ways to hold it — stop the timer when reopening, or have
// the timer check `shown` before firing — and this module does both. In
// fifteen files that redundancy would be waste; in one it is the
// difference between an invariant and a convention, because neither a
// future reopen path nor a future edit to the timer can drop it alone.
//
// It is not hypothetical. The shell shipped fourteen surfaces holding it
// one way or the other and one holding it neither way, and that one —
// lockscreen/LockScreen.qml — did exactly the above; reproduced and
// fixed in 2964ae3, which is the commit that made the case for this
// file. Nothing catches this class of bug except one place to fix it.
//
// ── Using it ─────────────────────────────────────────────
//     ShellSurface {
//         id: panel
//         surfaceNamespace: "quickshell:example"
//         focusTarget: card
//         anchors { top: true; right: true }
//         onSurfaceOpened: (arg) => Something.refresh()
//         Rectangle { id: card; opacity: panel.shown ? 1 : 0 }
//     }
//
// Content is declared as children exactly as before: this is a
// PanelWindow, so its default property is still the window's own.
//
// What stays with the surface, because it genuinely varies: `anchors`,
// `exclusiveZone`, `mask`, the card's width, and the transform half of
// the open animation — surfaces slide in on x, drop in on y, or scale,
// and encoding four directions here would widen this interface to save
// four repetitions. The opacity fade is here because all fifteen had it.
PanelWindow {
    id: root

    // ── Interface ────────────────────────────────────────

    // The layershell namespace, which hypr/modules/windowrules.lua
    // matches on. `required` rather than defaulted: a surface that
    // forgets it would land in the compositor as an unnamed layer and
    // silently miss every rule written for it.
    //
    // Not spelled `namespace`: that is a future-reserved word in
    // JavaScript, and this shell has already been bitten once by a QML
    // parser reserving a word that reads like an ordinary name.
    required property string surfaceNamespace

    // What takes keyboard focus when the surface opens. Fifteen files
    // called forceActiveFocus() on something; only the id varied.
    property Item focusTarget: null

    // Click-outside-to-dismiss. On for everything except a surface with
    // no outside — see lockscreen/LockScreen.qml, which is full-screen
    // and where a grab would be meaningless rather than merely unwanted.
    property bool grabFocus: true

    // Lazily-built windows are activated in response to a request they
    // did not exist to hear, so they open themselves for it. Off for
    // powermenu/PowerMenuPopout.qml, where the request that built the
    // window may have been a *toggle*: only its Connections knows which
    // arrived, and an unconditional open here would double up and close
    // it again on the very first press.
    property bool openOnCompleted: true

    // The name this surface answers to on services/Panels.qml — the same
    // string its IPC target uses. Setting it is the whole subscription:
    // a surface no longer writes a Connections block naming its own three
    // signals, because there are no longer three signals to name.
    //
    // Left empty for a surface nothing asks for by name.
    property string surfaceName: ""

    Connections {
        target: Panels
        enabled: root.surfaceName !== ""
        function onPanelRequested(name, verb, arg) {
            if (name !== root.surfaceName) return
            if (verb === "open") root.open(arg)
            else if (verb === "close") root.close()
            else if (verb === "toggle") root.toggle()
        }
    }

    // What open() is handed at Component.onCompleted, for a surface
    // whose first request carried a payload the signal could not deliver
    // (the signal is the one that built the item). Bind it to wherever
    // the payload was parked. Nothing sets it today: _firstArg() below
    // falls back on what Panels parked, which covers every window.
    property var firstOpenArg: undefined

    // Read-only on purpose: open(), close() and toggle() are the only
    // things that move it, so a surface cannot put `shown` and `visible`
    // out of step by hand.
    readonly property bool shown: root._shown

    // Motion. Distinct numbers from Theme.animPanel (220) rather than a
    // drifted copy of it: a surface enters slower than it leaves.
    property int inset: 8
    property int enterDuration: 280
    property int exitDuration: 200

    // `arg` is whatever open() was called with — a Conf menu row naming
    // a source, a query to put in a search field, or undefined.
    //
    // Prefixed for the same reason surfaceNamespace is: `closed` collides
    // with a signal PanelWindow already inherits, which QML reports as
    // "Duplicate signal name: invalid override" and then ignores — the
    // handler simply never runs. Caught on this module's first load.
    // `opened` did not collide, but an asymmetric pair would invite
    // someone to "fix" it back.
    signal surfaceOpened(var arg)
    signal surfaceClosed()

    // The window is actually gone, not merely on its way out. Distinct
    // from surfaceClosed, which fires the moment close() is called and
    // the fade begins: menu/ConfMenu.qml runs what you picked only once
    // the menu is off the screen, so that the action does not start
    // behind its own closing animation.
    //
    // Not fired for a close that was undone by a reopen inside the fade,
    // because in that case the window never went.
    signal surfaceHidden()

    // ── Implementation ───────────────────────────────────

    property bool _shown: false

    // Ordering is part of the contract, not an accident of how this is
    // written: the surface is real and focused before `opened` fires, so
    // per-open work (a rescan, a filter, a reset) runs against a window
    // that exists, and a surface that wants focus somewhere else can
    // move it from the handler rather than race this.
    function open(arg) {
        hideTimer.stop()
        root.visible = true
        root._shown = true
        if (root.focusTarget) root.focusTarget.forceActiveFocus()
        if (root.grabFocus) focusGrab.active = true
        root.surfaceOpened(arg)
    }

    function close() {
        root._shown = false
        focusGrab.active = false
        hideTimer.restart()
        root.surfaceClosed()
    }

    function toggle() { root._shown ? root.close() : root.open(undefined) }

    // No default `anchors` here on purpose, and this is not an omission
    // to be tidied up later: a grouped property assignment in a derived
    // surface *adds to* what the base set rather than replacing it, so a
    // default of all four edges cannot be narrowed. A rail declaring
    // `anchors { top: true; bottom: true; right: true }` would silently
    // keep `left` from here and stretch across the screen — which is
    // exactly what happened to all four rails the first time this file
    // carried a default, caught by looking at them rather than by the
    // clean reload. Every surface states its own anchors; all fifteen
    // already did.
    color: "transparent"
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: root.surfaceNamespace

    // Half of the invariant. The other half is hideTimer.stop() at the
    // top of open() — see the header for why this file carries both.
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

    // An explicit firstOpenArg wins; otherwise the payload Panels parked
    // for this name is used, which is what a window built by the very
    // request it needed to hear falls back on.
    function _firstArg() {
        if (root.firstOpenArg !== undefined) return root.firstOpenArg
        if (root.surfaceName !== "") return Panels.argFor(root.surfaceName)
        return undefined
    }

    Component.onCompleted: if (root.openOnCompleted) root.open(root._firstArg())
}
