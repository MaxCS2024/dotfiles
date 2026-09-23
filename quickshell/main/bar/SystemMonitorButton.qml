import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"
import "../common"
import "../services"

BarButton {
    id: root

    icon: "󰀻"

    // SystemMonitor only polls while at least one viewer is registered —
    // tie that to this dropdown's visibility rather than the button's
    // mere existence, since the button itself is always in the bar.
    onDropdownVisibleChanged: {
        if (dropdownVisible) SystemMonitor.addViewer()
        else SystemMonitor.removeViewer()
    }
    Component.onDestruction: if (dropdownVisible) SystemMonitor.removeViewer()

    // ── Dropdown ─────────────────────────────────────────
    Text {
        text: "System"
        color: Appearance.fgStrong
        font.bold: true
        font.pixelSize: Theme.fontMedium
        font.family: Theme.font
    }

    Divider {}

    Text {
        text: "CPU"
        color: Appearance.fgMuted
        font.pixelSize: Theme.fontSmall
        font.bold: true
        font.family: Theme.font
        Layout.topMargin: 2
    }

    InfoRow { label: "Usage"; value: Math.round(SystemMonitor.cpuUsage) + "%" }
    InfoRow {
        label: "Load (1m/5m/15m)"
        value: SystemMonitor.load1 + " / " + SystemMonitor.load5 + " / " + SystemMonitor.load15
    }
    InfoRow { label: "Temp"; value: SystemMonitor.cpuTemp === "-" ? "-" : SystemMonitor.cpuTemp + "°C" }

    Divider { Layout.topMargin: Theme.space1 }

    Text {
        text: "GPU (Intel)"
        color: Appearance.fgMuted
        font.pixelSize: Theme.fontSmall
        font.bold: true
        font.family: Theme.font
        Layout.topMargin: 2
    }

    Text {
        visible: !SystemMonitor.gpuAvailable
        text: "No Intel dGPU hwmon found"
        color: Appearance.fgDim
        font.pixelSize: Theme.fontNormal
        font.family: Theme.font
    }

    InfoRow {
        visible: SystemMonitor.gpuAvailable
        label: "Temp"
        value: SystemMonitor.gpuTemp === "-" ? "-" : SystemMonitor.gpuTemp + "°C"
    }
    InfoRow {
        visible: SystemMonitor.gpuAvailable
        label: "Power"
        value: SystemMonitor.gpuPower < 0 ? "-" : SystemMonitor.gpuPower.toFixed(1) + " W"
    }
}
