import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

// The device list takes the flexible height — it is the part
// that grows, and the rest of this tab is one toggle.
// The Bluetooth tab: the adapter switch and the paired devices, with
// connect, disconnect and forget on each.
//
// 199 lines that touched the rail around them exactly once, and only to
// decide their own visibility — see network/NetworkPanel.qml.
ColumnLayout {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 6

        Text {
            text: "Adapter"
            color: Appearance.fg
            font.pixelSize: Theme.fontSmall
            font.family: Theme.font
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
        }

        Rectangle {
            implicitWidth: btPowerLabel.implicitWidth + 16
            implicitHeight: 22
            radius: Theme.radius
            color: Bt.powered ? SlabStyle.tintSelected
                 : (btPowerHover.hovered ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong))
            border.width: Bt.powered ? 0 : 1
            border.color: Appearance.border

            Behavior on color {
                ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
            }

            Text {
                id: btPowerLabel
                anchors.centerIn: parent
                text: Bt.powered ? "On" : "Off"
                color: Bt.powered ? Appearance.fgStrong : Appearance.fgSoft
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
            }

            HoverHandler { id: btPowerHover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: Bt.available
                onClicked: Bt.togglePowered()
            }
        }
    }

    // Same three states quicksettings/BluetoothTab.qml
    // distinguishes — "no adapter", "adapter off" and "on but
    // nothing paired" are three different things to do next,
    // and one blank list for all three says none of them.
    Text {
        Layout.fillWidth: true
        visible: text !== ""
        wrapMode: Text.WordWrap
        text: !Bt.available ? "No Bluetooth adapter found"
            : !Bt.powered ? "Adapter is off"
            : Bt.devices.length === 0 ? "No devices"
            : ""
        color: Appearance.fgFaint
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
    }

    RowLayout {
        id: btListRow

        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: Bt.available && Bt.powered && Bt.devices.length > 0
        spacing: 4

        ListView {
            id: btList

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: Bt.devices
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: btRow
                required property var modelData

                width: btList.width
                height: 44
                radius: Theme.radius
                color: btRowHover.hovered ? Appearance.hover : Appearance.clear(Appearance.hover)

                Behavior on color {
                    ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    // nf-md-bluetooth{,_connect,_off}, written
                    // the same \u{...} way bar/BluetoothButton
                    // .qml writes the identical three.
                    Text {
                        text: btRow.modelData.connected ? "\u{F00B1}" : "\u{F00AF}"
                        color: btRow.modelData.connected ? Appearance.green : Appearance.fgFaint
                        font.pixelSize: Theme.fontNormal
                        font.family: Theme.font
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 0

                        Text {
                            text: btRow.modelData.name || btRow.modelData.deviceName
                            color: btRow.modelData.connected ? Appearance.fgStrong : Appearance.fg
                            font.bold: btRow.modelData.connected
                            font.pixelSize: Theme.fontNormal
                            font.family: Theme.font
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                        }

                        Text {
                            text: {
                                const state = BluetoothDeviceState.toString(btRow.modelData.state)
                                if (btRow.modelData.batteryAvailable)
                                    return state + " \u00b7 " + Math.round(btRow.modelData.battery * 100) + "%"
                                return state
                            }
                            color: Appearance.fgFaint
                            font.pixelSize: Theme.fontMicro
                            font.family: Theme.font
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                        }
                    }

                    // Glyph rather than a "Connect"/"Disconnect"
                    // word: at 320px the word crowds out the
                    // device name it belongs to. nf-md-link /
                    // nf-md-link_off. Same -6 hit
                    // target trick the DNS arrow uses.
                    Text {
                        text: btRow.modelData.connected ? "\u{F0338}" : "\u{F0337}"
                        color: btConnectHover.hovered ? Appearance.fgStrong : Appearance.fgSoft
                        font.pixelSize: Theme.fontNormal
                        font.family: Theme.font

                        HoverHandler { id: btConnectHover }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Bt.toggleConnected(btRow.modelData)
                        }
                    }
                }

                HoverHandler { id: btRowHover }
            }
        }

        ListScrollBar {
            view: btList
            Layout.fillHeight: true
            trackColor: Appearance.scrollTrack
            thumbColor: Appearance.scrollThumb
        }
    }

    // Absorbs the card's spare height whenever the device list
    // above is not there to do it — no adapter, adapter off, or
    // nothing paired. A ColumnLayout with nothing left to fill
    // hands that height to whatever else can grow, and
    // Layout.fillHeight defaults to TRUE for nested layouts, so
    // the header and tab rows took it and the whole card spread
    // itself out. The Wi-Fi tab never hits this (its list is
    // always present) and the DNS tab already carries a spacer
    // of its own for the same reason.
    Item {
        visible: !btListRow.visible
        Layout.fillHeight: true
    }
}
