import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

// The settings window's Bluetooth section (AGENTS.md, Settings window ›
// Bluetooth): the adapter's switch and visibility, the paired devices
// (connect, rename, forget, battery), and other devices to pair. While
// it is open it runs bt-agent.py, a BlueZ pairing agent, so devices that
// need a code (confirm a number, type a PIN) pair from here; its
// questions show in a box above the lists. Discovery is the island's:
// at most 30 seconds, then "Search again".
Item {
    id: page

    readonly property var adapter: Controls.adapter
    readonly property var paired: Controls.bluetoothDevices.filter(d => Controls.isPaired(d))
    readonly property var others: Controls.bluetoothDevices.filter(d => !Controls.isPaired(d))

    // The paired device whose actions are open, and whether its Forget
    // has been pressed once.
    property var expanded: null
    property bool forgetArmed: false

    // The agent's open question ({ type, device, passkey }), or null, and
    // why it isn't running, if it isn't.
    property var question: null
    property string agentProblem: ""

    Component.onCompleted: Controls.windowBluetoothScan = true
    Component.onDestruction: Controls.windowBluetoothScan = false

    function toggle(d) {
        forgetArmed = false
        expanded = expanded === d ? null : d
    }

    function answer(text) {
        agent.write(text + "\n")
        if (question && question.type !== "display")
            question = null
    }

    Process {
        id: agent
        running: true
        stdinEnabled: true
        // -B: no __pycache__ beside the script in the repo.
        command: ["python3", "-I", "-B", String(Qt.resolvedUrl("bt-agent.py")).replace(/^file:\/\//, "")]
        stdout: SplitParser {
            onRead: line => {
                let m
                try {
                    m = JSON.parse(line)
                } catch (e) {
                    return
                }
                if (m.type === "ready")
                    page.agentProblem = ""
                else if (m.type === "error")
                    page.agentProblem = m.message
                else if (m.type === "cancel")
                    page.question = null
                else
                    page.question = m
            }
        }
        stderr: StdioCollector {
            id: agentErr
        }
        onExited: code => {
            page.question = null
            if (code !== 0 && page.agentProblem === "")
                page.agentProblem = agentErr.text.trim().split("\n").pop() || "the pairing agent stopped"
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: content.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            width: flick.width
            spacing: 4

            // ── The adapter ──
            Item {
                width: content.width
                height: 32

                Heading { text: "Adapter" }

                Toggle {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.adapter !== null
                    on: Controls.bluetoothOn
                    onToggled: Controls.setBluetooth(!Controls.bluetoothOn)
                }
            }

            Empty {
                visible: page.adapter === null || !Controls.bluetoothOn
                text: page.adapter === null ? "No Bluetooth adapter" : "Bluetooth is off"
            }

            SettingRow {
                width: content.width
                visible: Controls.bluetoothOn
                label: "Visible to other devices"
                detail: page.adapter ? "As " + page.adapter.name : ""
                Toggle {
                    on: page.adapter ? page.adapter.discoverable : false
                    onToggled: page.adapter.discoverable = !page.adapter.discoverable
                }
            }

            // ── A question from the pairing agent ──
            Rectangle {
                visible: page.question !== null
                width: content.width
                height: questionColumn.height + 32
                radius: 20
                color: Qt.rgba(1, 1, 1, 0.12)

                Column {
                    id: questionColumn
                    x: 16
                    y: 16
                    width: parent.width - 32
                    spacing: 8

                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: !page.question ? ""
                            : page.question.type === "confirm" ? "Pair with " + page.question.device + "?"
                            : page.question.type === "authorize" ? "Let " + page.question.device + " connect?"
                            : page.question.type === "display" ? "Type this code on " + page.question.device
                            : "Enter the " + (page.question.type === "pin" ? "PIN" : "passkey") + " for " + page.question.device
                        color: "white"
                        font.family: "JetBrainsMono Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: 13
                    }

                    // The code, for a confirm or one to type on the device.
                    Text {
                        visible: !!page.question && !!page.question.passkey
                        text: page.question && page.question.passkey ? page.question.passkey : ""
                        color: "white"
                        font.family: "JetBrainsMono Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: 24
                        font.letterSpacing: 4
                    }

                    Text {
                        visible: !!page.question && page.question.type === "confirm"
                        text: "Check that the device shows the same code."
                        color: "white"
                        opacity: 0.6
                        font.family: "JetBrainsMono Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: 11
                    }

                    Field {
                        id: code
                        visible: !!page.question && (page.question.type === "pin" || page.question.type === "passkey")
                        width: parent.width
                        placeholder: page.question && page.question.type === "pin" ? "PIN, often 0000" : "Passkey"
                        onAccepted: {
                            page.answer(text)
                            text = ""
                        }
                        onVisibleChanged: if (visible) focusInput()
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 8

                        PillButton {
                            visible: !!page.question && page.question.type !== "display"
                            text: "Cancel"
                            onClicked: {
                                page.answer(page.question.type === "confirm" || page.question.type === "authorize" ? "no" : "")
                                code.text = ""
                            }
                        }

                        PillButton {
                            primary: true
                            text: !page.question ? ""
                                : page.question.type === "display" ? "Done"
                                : page.question.type === "confirm" || page.question.type === "authorize" ? "Pair" : "Send"
                            onClicked: {
                                const q = page.question
                                if (q.type === "display")
                                    page.question = null
                                else if (q.type === "confirm" || q.type === "authorize")
                                    page.answer("yes")
                                else {
                                    page.answer(code.text)
                                    code.text = ""
                                }
                            }
                        }
                    }
                }
            }

            // ── My devices ──
            Item { width: 1; height: 12; visible: Controls.bluetoothOn }
            Heading { text: "My devices"; visible: Controls.bluetoothOn }

            Repeater {
                model: Controls.bluetoothOn ? page.paired : []

                Column {
                    id: deviceItem
                    required property var modelData
                    readonly property bool open: page.expanded === modelData
                    width: content.width
                    spacing: 4

                    // The rename field starts from the current name.
                    onOpenChanged: if (open) rename.text = modelData.name

                    ListRow {
                        width: parent.width
                        icon: Controls.deviceIcon(deviceItem.modelData)
                        label: deviceItem.modelData.name
                        active: deviceItem.modelData.connected
                        detail: {
                            const d = deviceItem.modelData
                            if (d.state === BluetoothDeviceState.Connecting)
                                return "Connecting…"
                            if (d.state === BluetoothDeviceState.Disconnecting)
                                return "Disconnecting…"
                            if (!d.connected)
                                return ""
                            return d.batteryAvailable ? "Connected – " + Math.round(d.battery * 100) + "%" : "Connected"
                        }
                        onClicked: page.toggle(deviceItem.modelData)
                    }

                    // Its actions, under the row while it is open.
                    Column {
                        visible: deviceItem.open
                        width: parent.width
                        leftPadding: 44
                        rightPadding: 8
                        bottomPadding: 8
                        spacing: 8

                        readonly property real inner: width - leftPadding - rightPadding

                        SettingRow {
                            width: parent.inner
                            label: "Name"
                            detail: deviceItem.modelData.deviceName !== deviceItem.modelData.name
                                ? "Its own: " + deviceItem.modelData.deviceName : ""

                            Row {
                                spacing: 8

                                Field {
                                    id: rename
                                    width: 200
                                    placeholder: deviceItem.modelData.deviceName
                                    onAccepted: deviceItem.modelData.name = text.trim() || deviceItem.modelData.deviceName
                                }

                                PillButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Rename"
                                    onClicked: deviceItem.modelData.name = rename.text.trim() || deviceItem.modelData.deviceName
                                }
                            }
                        }

                        Row {
                            spacing: 8

                            PillButton {
                                text: deviceItem.modelData.connected ? "Disconnect" : "Connect"
                                onClicked: deviceItem.modelData.connected
                                    ? deviceItem.modelData.disconnect()
                                    : deviceItem.modelData.connect()
                            }

                            // Forget takes two presses: pairing it again may need the device's pairing mode.
                            PillButton {
                                text: page.forgetArmed ? "Forget – sure?" : "Forget"
                                primary: page.forgetArmed
                                onClicked: {
                                    if (!page.forgetArmed) {
                                        page.forgetArmed = true
                                        return
                                    }
                                    const d = deviceItem.modelData
                                    page.forgetArmed = false
                                    page.expanded = null
                                    d.forget()
                                }
                            }
                        }
                    }
                }
            }

            Empty {
                visible: Controls.bluetoothOn && page.paired.length === 0
                text: "No paired devices"
            }

            // ── Other devices ──
            Item { width: 1; height: 12; visible: Controls.bluetoothOn }

            Item {
                width: content.width
                height: 32
                visible: Controls.bluetoothOn

                Heading { text: "Other devices" }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.adapter !== null && page.adapter.discovering
                    text: "Searching…"
                    color: "white"
                    opacity: 0.6
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.Bold
                    font.pixelSize: 11
                }

                PillButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.adapter !== null && !page.adapter.discovering
                    text: "Search again"
                    onClicked: Controls.setDiscovering(true)
                }
            }

            Repeater {
                model: Controls.bluetoothOn ? page.others : []

                ListRow {
                    required property var modelData
                    width: content.width
                    icon: Controls.deviceIcon(modelData)
                    label: modelData.name
                    detail: modelData.pairing ? "Pairing…"
                        : modelData === Controls.failedDevice ? "Failed" : "Pair"
                    onClicked: Controls.useDevice(modelData)
                }
            }

            Empty {
                visible: Controls.bluetoothOn && page.others.length === 0
                text: page.adapter && page.adapter.discovering ? "Looking for devices…" : "None found"
            }

            Empty {
                visible: page.agentProblem !== ""
                text: "Pairing with a code is unavailable: " + page.agentProblem
            }
        }
    }

    component Heading: Text {
        height: 32
        verticalAlignment: Text.AlignVCenter
        color: "white"
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 16
    }

    component Empty: Text {
        height: 40
        leftPadding: 12
        verticalAlignment: Text.AlignVCenter
        color: "white"
        opacity: 0.6
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
    }
}
