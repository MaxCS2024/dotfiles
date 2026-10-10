import Quickshell.Networking
import QtQuick

// The settings window's Network section (AGENTS.md, Settings window ›
// Network): Wi-Fi on/off and the networks in range (as on the island's
// page), joining a hidden network, VPNs and the wired port. In-range
// networks come from Quickshell.Networking (through Controls), the rest
// from nmcli (NetworkSettings).
Item {
    id: page

    // A network in range that needs a password first.
    property var promptNetwork: null
    property bool joiningHidden: false
    readonly property var wired: Object.keys(NetworkSettings.devices)
        .filter(d => NetworkSettings.devices[d].type === "ethernet")

    Component.onCompleted: {
        NetworkSettings.watching = true
        Controls.windowWifiScan = true
    }
    Component.onDestruction: {
        NetworkSettings.watching = false
        Controls.windowWifiScan = false
    }

    function pick(net) {
        if (net.connected)
            return
        if (Controls.needsPassword(net)) {
            promptNetwork = net
            prompt.text = ""
            prompt.focusInput()
        } else {
            Controls.joinWifi(net)
        }
    }

    function submitPrompt() {
        if (prompt.text === "" || !promptNetwork)
            return
        Controls.joinWifi(promptNetwork, prompt.text)
        promptNetwork = null
        prompt.text = ""
    }

    Connections {
        target: Controls
        function onWifiPasswordNeeded(net) {
            page.promptNetwork = net
            prompt.text = ""
            prompt.focusInput()
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.bottomMargin: NetworkSettings.message !== "" ? 40 : 0
        contentHeight: content.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            width: flick.width
            spacing: 4

            // ── Wi-Fi ──
            Item {
                width: content.width
                height: 32

                Heading { text: "Wi-Fi" }

                Toggle {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Controls.wifiDevice !== null
                    on: Controls.wifiOn
                    onToggled: Controls.setWifi(!Controls.wifiOn)
                }
            }

            Repeater {
                model: Controls.wifiOn ? Controls.wifiNetworks : []

                ListRow {
                    required property var modelData
                    width: content.width
                    icon: Controls.wifiIcon(modelData)
                    label: modelData.name
                    active: modelData.connected
                    detail: modelData.connected ? "Connected"
                        : modelData.state === ConnectionState.Connecting ? "Connecting…"
                        : modelData === Controls.failedNetwork ? "Failed"
                        : modelData.known ? "Saved" : ""
                    onClicked: page.pick(modelData)
                }
            }

            Empty {
                visible: !Controls.wifiOn || Controls.wifiNetworks.length === 0
                text: !Controls.wifiDevice ? "No Wi-Fi adapter"
                    : !Controls.wifiOn ? "Wi-Fi is off" : "Searching…"
            }

            // The password for a network in range.
            Column {
                width: content.width
                visible: page.promptNetwork !== null
                spacing: 8
                topPadding: 4

                Text {
                    text: page.promptNetwork ? "Password for " + page.promptNetwork.name : ""
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.Bold
                    font.pixelSize: 13
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Field {
                        id: prompt
                        width: parent.width - connectButton.width - cancelButton.width - 16
                        password: true
                        placeholder: "Password"
                        onAccepted: page.submitPrompt()
                        onCancelled: page.promptNetwork = null
                    }

                    PillButton {
                        id: cancelButton
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Cancel"
                        onClicked: page.promptNetwork = null
                    }

                    PillButton {
                        id: connectButton
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Connect"
                        primary: true
                        onClicked: page.submitPrompt()
                    }
                }
            }

            // Joining a hidden network: its name and password.
            Item {
                width: content.width
                height: 40
                visible: !page.joiningHidden && Controls.wifiOn

                PillButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Join hidden network"
                    onClicked: {
                        page.joiningHidden = true
                        hiddenSsid.text = ""
                        hiddenPassword.text = ""
                        hiddenSsid.focusInput()
                    }
                }
            }

            Column {
                width: content.width
                visible: page.joiningHidden
                spacing: 8
                topPadding: 4

                Field {
                    id: hiddenSsid
                    width: parent.width
                    placeholder: "Network name"
                    onAccepted: hiddenPassword.focusInput()
                    onCancelled: page.joiningHidden = false
                }

                Field {
                    id: hiddenPassword
                    width: parent.width
                    password: true
                    placeholder: "Password (empty for an open network)"
                    onAccepted: joinHidden.clicked()
                    onCancelled: page.joiningHidden = false
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8

                    PillButton {
                        text: "Cancel"
                        onClicked: page.joiningHidden = false
                    }

                    PillButton {
                        id: joinHidden
                        text: "Join"
                        primary: true
                        enabled: hiddenSsid.text.trim() !== ""
                        onClicked: {
                            NetworkSettings.joinHidden(hiddenSsid.text.trim(), hiddenPassword.text)
                            page.joiningHidden = false
                        }
                    }
                }
            }

            // ── VPN ──
            Item { width: 1; height: 12 }
            Heading { text: "VPN" }

            Repeater {
                model: NetworkSettings.vpns

                SettingRow {
                    required property var modelData
                    width: content.width
                    label: modelData.name
                    detail: modelData.type === "wireguard" ? "WireGuard" : "VPN"
                    Toggle {
                        on: modelData.active
                        onToggled: on ? NetworkSettings.down(modelData) : NetworkSettings.up(modelData)
                    }
                }
            }

            Empty {
                visible: NetworkSettings.vpns.length === 0
                text: "No VPN connections (add one with nmcli)"
            }

            // ── Wired ──
            Item { width: 1; height: 12; visible: page.wired.length > 0 }
            Heading { text: "Wired"; visible: page.wired.length > 0 }

            Repeater {
                model: page.wired

                ListRow {
                    required property string modelData
                    readonly property var dev: NetworkSettings.devices[modelData]
                    width: content.width
                    icon: "\u{f0200}"
                    label: dev.connection && dev.state.startsWith("connected") ? dev.connection : modelData
                    detail: dev.state === "unavailable" ? "Cable unplugged"
                        : dev.state.startsWith("connected") ? (dev.addresses[0] || "Connected")
                        : dev.state
                }
            }
        }
    }

    // nmcli's answer when something failed.
    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 32
        visible: NetworkSettings.message !== ""
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: NetworkSettings.message
        color: "white"
        opacity: 0.6
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 11
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

    // A read-only detail: the name on the left, the value at 60% on the right.
    component Info: Item {
        property string label
        property string value
        height: 28

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: "white"
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Bold
            font.pixelSize: 13
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width / 2
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: parent.value
            color: "white"
            opacity: 0.6
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Bold
            font.pixelSize: 13
        }
    }
}
