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

            Item {
                id: sidebar
                x: 16
                y: 16
                width: win.narrow ? 40 : 200
                height: parent.height - 32

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
