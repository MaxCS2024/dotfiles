import Quickshell.Services.UPower
import QtQuick

// The settings panel's battery page: the header (back, "Battery", the
// charge on the right), then one row per power profile, the current one
// solid white. A click on a profile switches to it.
Item {
    id: page

    signal back()
    // The header's gear: the settings window's matching section.
    signal openSettings()

    // 32 header + 8 + three 40px rows 4px apart.
    height: 168

    PageHeader {
        hasSettings: true
        onSettings: page.openSettings()
        width: parent.width
        title: "Battery"
        hasToggle: false
        detail: Controls.batteryPercent < 0 ? ""
            : Math.round(Controls.batteryPercent) + "%" + (Controls.charging ? " – Charging" : "")
        onBack: page.back()
    }

    Column {
        y: 40
        width: parent.width
        spacing: 4
        visible: Controls.profilesAvailable

        Repeater {
            model: Controls.profiles

            delegate: ListRow {
                required property var modelData
                width: parent.width
                icon: Controls.profileIcon(modelData)
                label: Controls.profileLabel(modelData)
                active: PowerProfiles.profile === modelData
                onClicked: Controls.setProfile(modelData)
            }
        }
    }

    // power-profiles-daemon isn't running.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 40 + (128 - height) / 2
        visible: !Controls.profilesAvailable
        text: "Power profiles unavailable"
        color: "white"
        opacity: 0.6
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
    }
}
