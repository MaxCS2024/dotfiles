import Quickshell.Bluetooth
import QtQuick

// The settings panel's Bluetooth page: the header (back, "Bluetooth", the
// adapter's switch), then the devices, paired ones first, five rows tall
// and scrolling past that. A click on a paired device connects or
// disconnects it; a click on a new one pairs and connects it.
Item {
    id: page

    signal back()
    // The header's gear: the settings window's matching section.
    signal openSettings()

    // 32 header + 8 + five 40px rows 4px apart.
    height: 256

    PageHeader {
        hasSettings: true
        onSettings: page.openSettings()
        width: parent.width
        title: "Bluetooth"
        on: Controls.bluetoothOn
        onBack: page.back()
        onToggled: Controls.setBluetooth(!Controls.bluetoothOn)
    }

    ListView {
        id: list
        y: 40
        width: parent.width
        height: 216
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: Controls.bluetoothOn ? Controls.bluetoothDevices : []

        delegate: ListRow {
            required property var modelData
            width: list.width
            icon: Controls.deviceIcon(modelData)
            label: modelData.name
            active: modelData.connected
            detail: {
                const d = modelData
                if (d.connected)
                    return d.batteryAvailable ? "Connected – " + Math.round(d.battery * 100) + "%" : "Connected"
                if (d.pairing)
                    return "Pairing…"
                if (d.state === BluetoothDeviceState.Connecting)
                    return "Connecting…"
                if (d === Controls.failedDevice)
                    return "Failed"
                return Controls.isPaired(d) ? "" : "Pair"
            }
            onClicked: Controls.useDevice(modelData)
        }
    }

    // No adapter, the adapter off, or nothing paired or heard yet.
    Text {
        anchors.centerIn: list
        visible: list.count === 0
        text: !Controls.adapter ? "No Bluetooth adapter"
            : !Controls.bluetoothOn ? "Bluetooth is off" : "Searching…"
        color: "white"
        opacity: 0.6
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
    }
}
