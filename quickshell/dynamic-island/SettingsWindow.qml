pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// The settings window (AGENTS.md, Settings window): a normal Hyprland
// window, not a panel, for what doesn't fit the pill. One window at most,
// created while open and destroyed on close; `section` outlives it, so
// it reopens where it was left. SUPER+COMMA toggles it through the
// global shortcut below (hypr/modules/binds/apps.lua), settings.desktop
// and anything else through the `settings` IPC target.
Singleton {
    id: root

    readonly property var sections: [
        { key: "displays", label: "Displays", icon: "\u{f0379}" },
        { key: "sound", label: "Sound", icon: "\u{f057e}" },
        { key: "network", label: "Network", icon: "\u{f05a9}" },
        { key: "bluetooth", label: "Bluetooth", icon: "\u{f00af}" },
        { key: "power", label: "Power", icon: "\u{f0079}" },
        { key: "input", label: "Input", icon: "\u{f030c}" },
    ]
    property string section: "displays"
    readonly property var current: sections.find(s => s.key === section)
    property bool shown: false
    // The keys were used since the last click (see the window's Keyboard).
    property bool keyboard: false
    // How the keys' focus shows: a fill well above hover's 12–20%, and a
    // control that is already solid white dimmed to 60%.
    readonly property real focusFill: 0.32
    readonly property real focusSolid: 0.6

    // Scrolls every Flickable around `item` until it is in view, with
    // 8px to spare.
    function reveal(item) {
        for (let f = item.parent; f; f = f.parent) {
            if (f.contentY === undefined || f.contentItem === undefined)
                continue
            const top = item.mapToItem(f.contentItem, 0, 0).y - 8
            const bottom = top + item.height + 16
            const lowest = f.originY + Math.max(0, f.contentHeight - f.height)
            if (top < f.contentY)
                f.contentY = Math.max(f.originY, top)
            else if (bottom > f.contentY + f.height)
                f.contentY = Math.min(lowest, bottom - f.height)
        }
    }

    // Opens on `key` (any other string, "" included, keeps the last
    // section), or focuses the window if it is already open.
    function open(key) {
        if (sections.some(s => s.key === key))
            section = key
        if (shown)
            focus()
        else
            shown = true
    }

    function close() {
        shown = false
    }

    // Focusing switches to the window's workspace too.
    function focus() {
        if (!shown) {
            shown = true
            return
        }
        const t = toplevel()
        if (t) {
            Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + t.address + '" })')
        } else {
            // Open as far as `shown` knows, but Hyprland has no such
            // window (closed from outside without `visible` saying so):
            // make a new one, or it could never come back.
            shown = false
            Qt.callLater(() => shown = true)
        }
    }

    // SUPER+COMMA: open if closed, close if focused, else focus.
    function toggle() {
        if (shown && Hyprland.activeToplevel && Hyprland.activeToplevel === toplevel())
            close()
        else
            focus()
    }

    // Hyprland's record of this window, found by its title and
    // Quickshell's app id; null until Hyprland has reported it.
    function toplevel() {
        return Hyprland.toplevels.values.find(t => {
            const cls = String((t.wayland && t.wayland.appId)
                || (t.lastIpcObject && t.lastIpcObject.class) || "")
            return t.title === "Settings" && cls.indexOf("quickshell") !== -1
        }) || null
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "island-settings"
        description: "Open, focus or close the island's settings window"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "settings"
        function open(section: string): void { root.open(section) }
        function focus(): void { root.focus() }
        function close(): void { root.close() }
        function toggle(): void { root.toggle() }
    }

    LazyLoader {
        active: root.shown

        FloatingWindow {
            id: win

            title: "Settings"
            color: "black"
            implicitWidth: 880
            implicitHeight: 600
            minimumSize: Qt.size(360, 400)

            // Closed from Hyprland (killactive) rather than from here.
            onVisibleChanged: if (!visible) root.shown = false

            // Tiled narrow at the side of the screen: icons only.
            readonly property bool narrow: width < 640

            // Keyboard (AGENTS.md, Settings window › Keyboard). Whether
            // the keys were used since the last click: only then does the
            // focused control show it, so the mouse sees no change.
            Component.onCompleted: {
                root.keyboard = false
                win.toSidebar()
            }

            // Whether the keys were last in the page rather than the
            // sidebar, for when the focused control goes away.
            property bool inPage: false

            // The page's controls in order: every visible, enabled item
            // that says `navigable`, in the order they are built, a
            // ListView's rows by their place. An open dialog
            // (`navTrap`) keeps the keys to itself.
            function controls() {
                const found = []
                const traps = []
                const walk = (item, trapped) => {
                    if (!item.visible || !item.enabled)
                        return
                    if (!trapped && item.navTrap === true) {
                        traps.push(item)
                        return
                    }
                    if (item.navigable === true) {
                        found.push(item)
                        return
                    }
                    const kids = []
                    for (let i = 0; i < item.children.length; i++)
                        kids.push(item.children[i])
                    const view = item.parent
                    if (view && view.contentItem === item && view.currentIndex !== undefined)
                        kids.sort((a, b) => a.y - b.y)
                    for (const k of kids)
                        walk(k, trapped)
                }
                walk(page, false)
                if (traps.length === 0)
                    return found
                found.length = 0
                walk(traps[0], true)
                return found
            }

            // The control the keys were last on, to come back to after ←.
            property var lastControl: null

            function focusControl(item) {
                inPage = true
                lastControl = item
                item.forceActiveFocus()
                root.reveal(item)
            }

            // Into the page: back on the control left with ←, while it
            // is still there, else on the first.
            function enterPage() {
                const list = controls()
                if (list.length > 0)
                    focusControl(list.indexOf(lastControl) !== -1 ? lastControl : list[0])
            }

            // One control on (1) or back (-1); stops at the ends.
            function step(delta) {
                const list = controls()
                if (list.length === 0)
                    return
                const i = list.findIndex(c => c.activeFocus)
                const j = i === -1 ? (delta > 0 ? 0 : list.length - 1)
                    : Math.max(0, Math.min(list.length - 1, i + delta))
                focusControl(list[j])
            }

            function toSidebar() {
                inPage = false
                sidebar.forceActiveFocus()
            }

            Connections {
                target: root
                // The page is rebuilt; whatever had the keys is gone.
                function onSectionChanged() {
                    win.lastControl = null
                    win.toSidebar()
                }
            }

            // Keys that reach here found nothing focused (the control
            // was hidden or rebuilt): go back where the keys last were.
            FocusScope {
                id: nav
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    const k = event.key
                    if (k !== Qt.Key_Up && k !== Qt.Key_Down && k !== Qt.Key_Left && k !== Qt.Key_Right
                            && k !== Qt.Key_Tab && k !== Qt.Key_Backtab)
                        return
                    root.keyboard = true
                    if (win.inPage && k !== Qt.Key_Left)
                        win.enterPage()
                    else
                        win.toSidebar()
                    event.accepted = true
                }

                // A click hides the keyboard's focus again; the click
                // itself goes on to whatever is under it.
                MouseArea {
                    anchors.fill: parent
                    z: 1
                    acceptedButtons: Qt.AllButtons
                    onPressed: mouse => {
                        root.keyboard = false
                        mouse.accepted = false
                    }
                }

                Item {
                    id: sidebar
                    x: 16
                    y: 16
                    width: win.narrow ? 40 : 200
                    height: parent.height - 32

                    // ↑ ↓ switch the section at once (the white row moves);
                    // → (or Enter, Tab) goes into its page.
                    function go(i) {
                        const n = root.sections.length
                        root.section = root.sections[Math.max(0, Math.min(n - 1, i))].key
                    }

                    Keys.onPressed: event => {
                        const k = event.key
                        const i = root.sections.findIndex(s => s.key === root.section)
                        if (k === Qt.Key_Up)
                            go(i - 1)
                        else if (k === Qt.Key_Down)
                            go(i + 1)
                        else if (k === Qt.Key_Home)
                            go(0)
                        else if (k === Qt.Key_End)
                            go(root.sections.length - 1)
                        else if (k === Qt.Key_Right || k === Qt.Key_Return || k === Qt.Key_Enter
                                || k === Qt.Key_Tab)
                            win.enterPage()
                        else
                            return
                        root.keyboard = true
                        event.accepted = true
                    }

                    Text {
                        visible: !win.narrow
                        height: 40
                        x: 12
                        verticalAlignment: Text.AlignVCenter
                        text: "Settings"
                        color: "white"
                        font.family: "JetBrainsMono Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: 20
                    }

                    Column {
                        y: 56
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: root.sections

                            SidebarRow {
                                required property var modelData
                                width: parent.width
                                icon: modelData.icon
                                label: modelData.label
                                active: root.section === modelData.key
                                compact: win.narrow
                                onClicked: root.section = modelData.key
                            }
                        }
                    }
                }

                // A hairline between the sidebar and the page, the window's
                // full height; 16px from the sidebar, 32px from the page.
                Rectangle {
                    id: divider
                    x: sidebar.x + sidebar.width + 16
                    width: 1
                    height: parent.height
                    color: Qt.rgba(1, 1, 1, 0.12)
                }

                Item {
                    id: page
                    anchors.left: divider.right
                    anchors.leftMargin: 32
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.top: parent.top
                    anchors.topMargin: 16
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 16

                    // What the focused control leaves: ↑ ↓ (and Tab) go
                    // from control to control, ← or Escape back to the
                    // sidebar; → is already here.
                    Keys.onPressed: event => {
                        const k = event.key
                        if (k === Qt.Key_Down || k === Qt.Key_Tab)
                            win.step(1)
                        else if (k === Qt.Key_Up || k === Qt.Key_Backtab)
                            win.step(-1)
                        else if (k === Qt.Key_Left || k === Qt.Key_Escape)
                            win.toSidebar()
                        else if (k !== Qt.Key_Right)
                            return
                        root.keyboard = true
                        event.accepted = true
                    }

                    Text {
                        id: pageTitle
                        height: 40
                        verticalAlignment: Text.AlignVCenter
                        text: root.current ? root.current.label : ""
                        color: "white"
                        font.family: "JetBrainsMono Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: 20
                    }

                    // The section's page; one not built yet says so.
                    Loader {
                        anchors.top: pageTitle.bottom
                        anchors.topMargin: 16
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        sourceComponent: root.section === "displays" ? displaysPage
                            : root.section === "sound" ? soundPage
                            : root.section === "input" ? inputPage
                            : root.section === "power" ? powerPage
                            : root.section === "network" ? networkPage
                            : root.section === "bluetooth" ? bluetoothPage
                            : notBuilt
                    }

                    Component {
                        id: inputPage
                        InputPage {}
                    }

                    Component {
                        id: powerPage
                        PowerPage {}
                    }

                    Component {
                        id: networkPage
                        NetworkPage {}
                    }

                    Component {
                        id: bluetoothPage
                        BluetoothSettingsPage {}
                    }

                    Component {
                        id: displaysPage
                        DisplaysPage {}
                    }

                    Component {
                        id: soundPage
                        SoundPage {}
                    }

                    Component {
                        id: notBuilt

                        Item {
                            Text {
                                anchors.centerIn: parent
                                text: "Not built yet"
                                color: "white"
                                opacity: 0.6
                                font.family: "JetBrainsMono Nerd Font"
                                font.weight: Font.Bold
                                font.pixelSize: 13
                            }
                        }
                    }
                }
            }
        }
    }
}
