import QtQuick
import QtQuick.Layouts

// Resolves a Modules.registry name to a live item and forwards the
// context every bar item might need: `barWindow` for dropdown anchoring,
// and (Workspaces only) `screen`, read off barWindow.screen rather than
// threaded through as a second required property. The `"prop" in item`
// checks mean this stays correct without an exceptions list as more
// modules are added — a module simply declares the properties it wants.
Loader {
    id: root

    required property string name
    property var barWindow

    // Same forwarding pattern as barWindow/screen below,
    // but needs to stay *live* (barWindow/screen are set once at load
    // and never change again; which item has keyboard focus changes
    // constantly), so it's Qt.binding() rather than a plain assignment.
    // keyboardNavigable reports outward whether this slot's loaded item
    // opted in at all (declares `keyboardFocused`) — bar/Bar.qml reads
    // it to build the roving-focus order without an exceptions list.
    property bool keyboardFocused: false
    readonly property bool keyboardNavigable: !!(item && ("keyboardFocused" in item))

    Layout.alignment: Qt.AlignVCenter

    // A module with nothing to show (MediaPlayer with no player,
    // ActiveWindow with nothing focused, BrightnessButton with no
    // backlight) says so with `hasContent`, and the Loader — the actual
    // RowLayout child — hides itself, so RowLayout drops the slot and
    // the spacing either side of it instead of leaving a blank gap.
    //
    // It reads `hasContent` rather than the module's `visible` because
    // Qt reports `visible` with every ancestor's folded in. That is how
    // this used to work — modules set `visible: false` and the Loader
    // mirrored item.visible — and a module that hid itself hid the
    // Loader, and then read false because the Loader was hidden, for
    // good: the media pill went with the last player and did not come
    // back for the next one, or never appeared at all if the shell
    // started with nothing playing, until a config reload.
    // services/MprisWatchdog.qml's reloads hid it now and then, so some
    // of what was put down to Mpris starting stale may have been this.
    // tests/bar/shell.qml has the regression test.
    //
    // So a module must not set its own `visible`, and nothing needs to
    // avoid hiding an ancestor of these Loaders on their account.
    visible: !item || !("hasContent" in item) || item.hasContent

    sourceComponent: Modules.registry[root.name]

    onLoaded: {
        if ("barWindow" in item) item.barWindow = root.barWindow
        if ("screen" in item && root.barWindow) item.screen = root.barWindow.screen
        if ("keyboardFocused" in item) item.keyboardFocused = Qt.binding(() => root.keyboardFocused)
    }
}
