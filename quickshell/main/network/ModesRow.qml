import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

// Night light and stay-awake. Both were tiles in
// dashboard/Dashboard.qml's toggle card until that panel was
// deleted on 2026-09-21, and neither had a second home: every
// other tile there had one (bluetooth in the tab below,
// airplane in the header, DND on bar/NotificationsButton.qml,
// wallpaper on its own panel), which is most of why the
// dashboard went. These two are why this section exists.
//
// Outside all three tabs rather than in one, for the reason
// the airplane switch sits in the header: these are modes the
// machine is put into and left in, not something a tab does,
// so they stay reachable whichever tab is open.
//
// That they are not network settings is the fair objection to
// this being their address. The answer is that the rail is
// the surface you open to look at machine state rather than
// to configure one service, and after the dashboard there is
// no other.
//
// Labelled, where the airplane switch deliberately is not:
// that one has the caption under the title to name it once it
// is on (see the switch in the header), and nothing on this
// card would ever say what these two are.
// Night light and stay-awake, under the tabs rather than inside one:
// they are modes the machine is put into and left in, not something a tab
// does, so they stay reachable whichever tab is open.
//
// They came to the network rail when the dashboard was deleted on
// 2026-09-21. This block reached out to nothing at all, which made it the
// easiest of the four to lift out of network/NetworkPanel.qml.
ColumnLayout {
    id: root
    Layout.fillWidth: true
    Layout.topMargin: 2
    spacing: Theme.space2

    // Capitals and tracking as the Wi-Fi tab's own section
    // headers — see "Known networks" above for why both.
    Text {
        text: "Modes"
        color: Appearance.fg
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Theme.tracking(Theme.fontSmall, 0.12)
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        elide: Text.ElideRight
    }

    // Label left, switch right: the Bluetooth tab's "Adapter"
    // row with the header's switch in place of that row's
    // On/Off button. Two of them, so it is a component rather
    // than the same fourteen lines twice — the same call
    // StatLabel/StatValue make in the detail grid above.
    component ModeRow: RowLayout {
        id: modeRow

        required property string label
        required property bool active

        signal switched()

        Layout.fillWidth: true
        spacing: Theme.space2

        Text {
            text: modeRow.label
            color: Appearance.fg
            font.pixelSize: Theme.fontSmall
            font.family: Theme.font
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
        }

        ToggleSwitch {
            checked: modeRow.active
            trackOffColor: Appearance.trackBg
            trackOnColor: Appearance.accent
            borderColor: Appearance.border
            knobColor: Appearance.fgStrong
            onToggled: modeRow.switched()
        }
    }

    // NightLight.toggle() writes Settings.nightLight, which
    // the service's own Connections turns into a hyprsunset
    // temperature — see services/NightLight.qml. Nothing here
    // has to know that, but it is the reason shell.qml names
    // the singleton: this switch is no longer the shell's
    // first reference to it, and never was the one that
    // mattered at login.
    ModeRow {
        label: "Night light"
        active: NightLight.enabled
        onSwitched: NightLight.toggle()
    }

    // Read by one IdleInhibitor per monitor in bar/Bar.qml.
    // That was the last thing in the shell touching this
    // setting once the dashboard's tile went, which left it
    // written only by whatever was in the settings file.
    ModeRow {
        label: "Stay awake"
        active: Settings.stayAwake
        onSwitched: Settings.stayAwake = !Settings.stayAwake
    }
}
