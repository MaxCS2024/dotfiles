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

    // Some modules set their own `visible: false` when there's nothing to
    // show (MediaPlayer, for one). That hides the item's contents but the
    // Loader itself — the actual RowLayout child — stays visible with the
    // item's implicitWidth, so the layout still reserves the slot and
    // spacing on both sides of it. Mirroring item.visible onto the Loader
    // lets RowLayout exclude the slot entirely instead of leaving a blank
    // gap.
    //
    // INVARIANT for anything that wants to hide part of the bar: never
    // drive `visible` on an ancestor of these Loaders. Qt Quick forces
    // every descendant's `visible` to false when an ancestor is hidden,
    // so this binding reads false, which keeps item.visible false, which
    // keeps the binding false — it latches, and the modules stay gone
    // until a config reload, leaving a bar that paints its background
    // and nothing else. The self-hiding modules (MediaPlayer.qml,
    // ActiveWindow.qml) are independently exposed to the same cascade,
    // so fixing this one binding would not be enough. Hide with opacity
    // instead — bar/Bar.qml's SUPER+ALT+SPACE toggle is the worked
    // example.
    visible: !item || item.visible

    sourceComponent: Modules.registry[root.name]

    onLoaded: {
        if ("barWindow" in item) item.barWindow = root.barWindow
        if ("screen" in item && root.barWindow) item.screen = root.barWindow.screen
        if ("keyboardFocused" in item) item.keyboardFocused = Qt.binding(() => root.keyboardFocused)
    }
}
