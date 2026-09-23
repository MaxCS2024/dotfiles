import Quickshell
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"
import "../common"
import "../services"

BarButton {
    id: root

    // Font Awesome's bluetooth-rune glyph (U+F293) stood out next to
    // every other bar icon, which are all Material Design Icons glyphs
    // (ClipboardButton, LauncherButton, etc.) — swapped for MDI's own
    // bluetooth set so it matches the rest of the bar, and reflects
    // adapter/connection state the way iconColor below already does.
    // \u{...}, not bare \u (which only takes exactly 4 hex digits) --
    // these are 5-digit codepoints in the Supplementary PUA-A. A bare
    // \uF00B2 parses as \uF00B ("fa-th_list", a small grid icon) plus
    // a literal trailing "2" character -- same trap ClipboardButton.qml
    // avoids with \u{F0214}.
    icon: !Bt.available || !Bt.powered ? "\u{F00B2}" : (Bt.anyConnected ? "\u{F00B1}" : "\u{F00AF}")
    iconColor: !Bt.available || !Bt.powered
        ? Appearance.disabled
        : (Bt.anyConnected ? Appearance.green : Appearance.icon)

    onRightTapped: Bt.togglePowered()

    RowLayout {
        Layout.fillWidth: true

        Text {
            text: "Bluetooth"
            color: Appearance.fgStrong
            font.bold: true
            font.pixelSize: Theme.fontMedium
            font.family: Theme.font
            Layout.fillWidth: true
        }

        Rectangle {
            implicitWidth: powerLabel.implicitWidth + 2 * Theme.space2
            implicitHeight: Theme.space6
            radius: Theme.radius
            color: Bt.powered ? SlabStyle.tintSelected : (powerHover.hovered ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong))
            border.color: Appearance.border
            border.width: Bt.powered ? 0 : 1

            Text {
                id: powerLabel
                anchors.centerIn: parent
                text: Bt.powered ? "On" : "Off"
                color: Bt.powered ? Appearance.fgStrong : Appearance.fgSoft
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
            }

            HoverHandler { id: powerHover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: Bt.available
                onClicked: Bt.togglePowered()
            }
        }
    }

    Divider {}

    Text {
        visible: !Bt.available
        text: "No adapter found"
        color: Appearance.fgDim
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
    }

    Text {
        visible: Bt.available && Bt.powered && Bt.devices.length === 0
        text: "No devices"
        color: Appearance.fgDim
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
    }

    Text {
        visible: Bt.available && !Bt.powered
        text: "Adapter off"
        color: Appearance.fgDim
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
    }

    Repeater {
        model: Bt.available && Bt.powered ? Bt.devices : []

        delegate: Rectangle {
            id: devRow
            required property var modelData

            Layout.fillWidth: true
            implicitHeight: 32
            radius: Theme.radius
            color: rowHover.hovered ? Appearance.hover : Appearance.clear(Appearance.hover)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space2
                anchors.rightMargin: Theme.space2
                spacing: Theme.space2

                Text {
                    text: ""
                    color: devRow.modelData.connected ? Appearance.green : Appearance.fgFaint
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0

                    Text {
                        text: devRow.modelData.name || devRow.modelData.deviceName
                        color: Appearance.fg
                        font.pixelSize: Theme.fontNormal
                        font.family: Theme.font
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Text {
                        text: {
                            const state = BluetoothDeviceState.toString(devRow.modelData.state)
                            if (devRow.modelData.batteryAvailable)
                                return state + " · " + Math.round(devRow.modelData.battery * 100) + "%"
                            return state
                        }
                        color: Appearance.fgDim
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.font
                    }
                }

                Text {
                    text: devRow.modelData.connected ? "" : ""
                    color: Appearance.fgSoft
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                }
            }

            HoverHandler { id: rowHover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Bt.toggleConnected(devRow.modelData)
            }
        }
    }
}
