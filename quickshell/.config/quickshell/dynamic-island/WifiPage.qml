import Quickshell.Networking
import QtQuick

// The settings panel's Wi-Fi page: the header (back, "Wi-Fi", the radio's
// switch), then the networks in range, five rows tall and scrolling past
// that. A click on a network connects to it. One that is secured and
// never joined asks for its password first: the list gives way to a
// password field, the header shows the network's name, Enter connects
// and Escape (or back) returns to the list.
Item {
    id: page

    signal back()
    // The header's gear: the settings window's matching section.
    signal openSettings()

    property var promptNetwork: null
    readonly property bool prompting: promptNetwork !== null

    // 32 header + 8 + five 40px rows 4px apart.
    height: 256

    function pick(net) {
        if (net.connected)
            return
        if (Controls.needsPassword(net))
            ask(net)
        else
            Controls.joinWifi(net)
    }

    function ask(net) {
        field.text = ""
        promptNetwork = net
        field.forceActiveFocus()
    }

    function cancelPrompt() {
        promptNetwork = null
        field.text = ""
    }

    function submit() {
        if (field.text === "" || !promptNetwork)
            return
        Controls.joinWifi(promptNetwork, field.text)
        cancelPrompt()
    }

    // Leaving the page (back, or the island closing) drops a half-typed
    // password.
    onVisibleChanged: if (!visible) cancelPrompt()

    // A saved network whose password no longer works.
    Connections {
        target: Controls
        function onWifiPasswordNeeded(net) {
            if (page.visible)
                page.ask(net)
        }
    }

    PageHeader {
        hasSettings: true
        onSettings: page.openSettings()
        width: parent.width
        title: page.prompting ? page.promptNetwork.name : "Wi-Fi"
        on: Controls.wifiOn
        onBack: page.prompting ? page.cancelPrompt() : page.back()
        onToggled: Controls.setWifi(!Controls.wifiOn)
    }

    ListView {
        id: list
        y: 40
        width: parent.width
        height: 216
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        visible: !page.prompting
        model: Controls.wifiOn ? Controls.wifiNetworks : []

        delegate: ListRow {
            required property var modelData
            width: list.width
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

    // No adapter, the radio off, or nothing heard yet.
    Text {
        anchors.centerIn: list
        visible: !page.prompting && list.count === 0
        text: !Controls.wifiDevice ? "No Wi-Fi adapter"
            : !Controls.wifiOn ? "Wi-Fi is off" : "Searching…"
        color: "white"
        opacity: 0.6
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
    }

    // The password field: a 40px pill, white at 12%, with a round white
    // connect button at its right end.
    Rectangle {
        y: 40
        width: parent.width
        height: 40
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.12)
        visible: page.prompting

        // Clicks in the pill's padding still land in the field.
        MouseArea {
            anchors.fill: parent
            onClicked: field.forceActiveFocus()
        }

        TextInput {
            id: field
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: submitButton.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            echoMode: TextInput.Password
            passwordCharacter: "•"
            selectByMouse: true
            color: "white"
            selectionColor: Qt.rgba(1, 1, 1, 0.3)
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Bold
            font.pixelSize: 13
            onAccepted: page.submit()
            Keys.onEscapePressed: page.cancelPrompt()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: field.text === ""
                text: "Password"
                color: "white"
                opacity: 0.4
                font: field.font
            }
        }

        Rectangle {
            id: submitButton
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            radius: 16
            color: "white"
            opacity: field.text === "" ? 0.3 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: "\u{f0054}"
                color: "black"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 18
            }

            MouseArea {
                anchors.fill: parent
                onClicked: page.submit()
            }
        }
    }
}
