import Quickshell.Services.UPower
import QtQuick

// The settings window's Power section (AGENTS.md, Settings window ›
// Power): the power mode, the idle timers and the charge limit. Each
// applies at once.
Item {
    id: page

    Component.onCompleted: PowerSettings.refresh()

    // Never, then minutes; the current value joins the list when it isn't
    // one of them (hypridle.conf's 330s for the screen).
    readonly property var steps: [0, 60, 120, 180, 300, 600, 900, 1200, 1800]

    function timerOptions(current) {
        const list = steps.indexOf(current) === -1 ? steps.concat([current]).sort((a, b) => a - b) : steps
        return list.map(s => ({ label: timerText(s), value: s }))
    }

    function timerText(s) {
        if (s <= 0)
            return "Never"
        const m = s / 60
        return (Number.isInteger(m) ? m : m.toFixed(1)) + (m === 1 ? " minute" : " minutes")
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

            // ── Power mode ──
            Heading { text: "Power mode" }

            Repeater {
                model: Controls.profilesAvailable ? Controls.profiles : []

                ListRow {
                    required property var modelData
                    width: content.width
                    icon: Controls.profileIcon(modelData)
                    label: Controls.profileLabel(modelData)
                    active: PowerProfiles.profile === modelData
                    onClicked: Controls.setProfile(modelData)
                }
            }

            Empty {
                visible: !Controls.profilesAvailable
                text: "Power profiles unavailable"
            }

            // ── When idle ──
            Item { width: 1; height: 12 }
            Heading { text: "When idle" }

            SettingRow {
                width: content.width
                visible: PowerSettings.stayAwake
                label: "Stay awake is on"
                detail: "The main bar's Stay awake pauses these timers"

                PillButton {
                    text: "Turn off"
                    onClicked: PowerSettings.turnOffStayAwake()
                }
            }

            SettingRow {
                width: content.width
                label: "Lock after"
                Choice {
                    width: 200
                    value: PowerSettings.value("lockAfter")
                    options: page.timerOptions(PowerSettings.value("lockAfter"))
                    onPicked: v => PowerSettings.setTimer("lockAfter", v)
                }
            }

            SettingRow {
                width: content.width
                label: "Screen off after"
                Choice {
                    width: 200
                    value: PowerSettings.value("screenOffAfter")
                    options: page.timerOptions(PowerSettings.value("screenOffAfter"))
                    onPicked: v => PowerSettings.setTimer("screenOffAfter", v)
                }
            }

            SettingRow {
                width: content.width
                label: "Suspend after"
                Choice {
                    width: 200
                    value: PowerSettings.value("suspendAfter")
                    options: page.timerOptions(PowerSettings.value("suspendAfter"))
                    onPicked: v => PowerSettings.setTimer("suspendAfter", v)
                }
            }

            // ── Battery ──
            Item { width: 1; height: 12; visible: PowerSettings.hasLimit }
            Heading {
                visible: PowerSettings.hasLimit
                text: "Battery"
            }

            SettingRow {
                width: content.width
                visible: PowerSettings.hasLimit
                label: "Charge limit"
                detail: PowerSettings.writable
                    ? (PowerSettings.chargeLimit < 100 ? "Stops charging at " + PowerSettings.chargeLimit + "%, kinder to the battery" : "Charges to full")
                    : "Needs the Battery charge limit patch"

                Item {
                    width: PowerSettings.writable ? limits.width : install.width
                    height: 32

                    Segmented {
                        id: limits
                        visible: PowerSettings.writable
                        value: PowerSettings.chargeLimit
                        options: [
                            { label: "Off", value: 100 },
                            { label: "90%", value: 90 },
                            { label: "80%", value: 80 },
                            { label: "60%", value: 60 },
                        ]
                        onPicked: v => PowerSettings.setChargeLimit(v)
                    }

                    PillButton {
                        id: install
                        visible: !PowerSettings.writable
                        text: "Install patch"
                        onClicked: PowerSettings.installPatch()
                    }
                }
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
