import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

// The Bluetooth tab: the adapter switch and a scan button, the paired
// devices with connect, disconnect and forget on each, and the nearby
// devices a scan turned up, which pair on click.
//
// Laid out as the Wi-Fi tab is: the short list of your own devices on
// top, capped, and the live list underneath taking the flexible height.
//
// Touches the rail around it only to decide its own visibility — see
// network/NetworkPanel.qml.
ColumnLayout {
    id: root
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Theme.space3

    // A scan left running behind a tab you can't see is only costing the
    // radio. Bt times it out anyway; this stops it on the tab switch.
    onVisibleChanged: if (!root.visible) Bt.setDiscovering(false)

    readonly property bool listsShown: Bt.available && Bt.powered

    // Section header in the caps and tracking of the Wi-Fi tab's
    // "Known networks" / "Other networks" pair.
    component SectionHeader: Text {
        color: Appearance.fg
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Theme.tracking(Theme.fontSmall, 0.12)
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.topMargin: 2
        elide: Text.ElideRight
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: Theme.space2

        Text {
            text: "Adapter"
            color: Appearance.fg
            font.pixelSize: Theme.fontSmall
            font.family: Theme.font
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
        }

        // Scan. The speed test button's shape (network/NetworkPanel.qml):
        // a glyph on a neutral edge, and the glyph in accent while the
        // thing it started is running. A second click stops it early.
        // nf-md-magnify.
        Rectangle {
            visible: root.listsShown
            implicitWidth: 28
            implicitHeight: 24
            radius: Theme.radius
            color: scanHover.hovered ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong)
            border.width: 1
            border.color: Appearance.border

            Behavior on color {
                ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
            }

            Text {
                anchors.centerIn: parent
                text: "\u{F0349}"
                color: Bt.discovering ? Appearance.accent : Appearance.fgSoft
                font.pixelSize: Theme.fontMedium
                font.family: Theme.font

                Behavior on color {
                    ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                }
            }

            HoverHandler { id: scanHover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Bt.toggleDiscovering()
            }
        }

        Rectangle {
            implicitWidth: btPowerLabel.implicitWidth + 16
            implicitHeight: 24
            radius: Theme.radius
            color: Bt.powered ? Appearance.selected
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

    // "No adapter" and "adapter off" are different things to do next,
    // and a blank card for both says neither. An empty paired list has a
    // line of its own under its header.
    Text {
        Layout.fillWidth: true
        visible: text !== ""
        wrapMode: Text.WordWrap
        text: !Bt.available ? "No Bluetooth adapter found"
            : !Bt.powered ? "Adapter is off"
            : ""
        color: Appearance.fgFaint
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
    }

    // ── Paired devices ───────────────────────────
    SectionHeader {
        text: "Paired devices"
        visible: root.listsShown
    }

    Text {
        Layout.fillWidth: true
        visible: root.listsShown && Bt.pairedDevices.length === 0
        wrapMode: Text.WordWrap
        text: "No paired devices"
        color: Appearance.fgFaint
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
    }

    // Capped at four rows and scrolling past that, so the nearby list
    // below keeps the card's spare height — Known networks' reasoning.
    RowLayout {
        Layout.fillWidth: true
        // Not a filling row: a nested layout defaults to fillHeight,
        // and this one would split the spare height with the nearby
        // list. See the same line in network/WifiTab.qml.
        Layout.fillHeight: false
        Layout.preferredHeight: Math.min(Bt.pairedDevices.length, 4) * 44
        Layout.maximumHeight: Layout.preferredHeight
        visible: root.listsShown && Bt.pairedDevices.length > 0
        spacing: Theme.space1

        ListView {
            id: pairedList

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: Bt.pairedDevices
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: btRow
                required property var modelData

                // Forget takes two clicks: the first arms it for three
                // seconds, the second removes the bond. Re-pairing means
                // putting the device back into pairing mode, which is too
                // much to cost a stray click on a 16px glyph.
                property bool forgetArmed: false

                Timer {
                    id: disarm
                    interval: 3000
                    onTriggered: btRow.forgetArmed = false
                }

                width: pairedList.width
                height: 44
                radius: Theme.radius
                // The connected row sits on `selected`, the fill of the
                // connected network in the Wi-Fi tab (user request
                // 2026-09-29), and doesn't light under the pointer, so
                // the two can't meet. The rest light on hoverStrong, as
                // the Wi-Fi rows do — `hover` is one step over the card
                // and hard to see.
                color: btRow.modelData.connected ? Appearance.selected
                    : btRowHover.hovered ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong)

                Behavior on color {
                    ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space2
                    anchors.rightMargin: Theme.space2
                    spacing: Theme.space2

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
                                if (btRow.forgetArmed) return "Click again to forget"
                                const state = BluetoothDeviceState.toString(btRow.modelData.state)
                                if (btRow.modelData.batteryAvailable)
                                    return state + " · " + Math.round(btRow.modelData.battery * 100) + "%"
                                return state
                            }
                            // Green while connected, as the Wi-Fi tab's
                            // "Connected"; fgFaint was also too dim to
                            // read on the `selected` fill.
                            color: btRow.modelData.connected && !btRow.forgetArmed
                                ? Appearance.green : Appearance.fgFaint
                            font.pixelSize: Theme.fontMicro
                            font.family: Theme.font
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                        }
                    }

                    // Forget, before connect so the glyph you use daily
                    // keeps the edge. nf-md-trash_can_outline; red while
                    // armed. Same -6 hit target as the link glyph.
                    Text {
                        text: "\u{F0A7A}"
                        color: btRow.forgetArmed ? Appearance.red
                            : forgetHover.hovered ? Appearance.fgStrong : Appearance.fgSoft
                        font.pixelSize: Theme.fontNormal
                        font.family: Theme.font

                        Behavior on color {
                            ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                        }

                        HoverHandler { id: forgetHover }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (btRow.forgetArmed) {
                                    disarm.stop()
                                    btRow.forgetArmed = false
                                    Bt.forget(btRow.modelData)
                                } else {
                                    btRow.forgetArmed = true
                                    disarm.restart()
                                }
                            }
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
            view: pairedList
            Layout.fillHeight: true
            trackColor: Appearance.scrollTrack
            thumbColor: Appearance.scrollThumb
        }
    }

    // ── Nearby devices ───────────────────────────
    // Unpaired devices BlueZ has heard, named ones only — see
    // Bt.nearbyDevices. BlueZ drops them again about 30 seconds after
    // the scan stops.
    SectionHeader {
        text: "Nearby devices"
        visible: root.listsShown
    }

    RowLayout {
        id: nearbyRow

        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.listsShown
        spacing: Theme.space1

        // Wrapped so the empty-state line has somewhere to centre —
        // see the same wrapper in network/WifiTab.qml.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: nearbyList

                anchors.fill: parent
                clip: true
                model: Bt.nearbyDevices
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: nearRow
                    required property var modelData

                    readonly property bool pairing: Bt.pairingDevice === nearRow.modelData
                    readonly property bool failed: Bt.failedDevice === nearRow.modelData
                    // One pairing at a time; the rest hold still until
                    // it finishes.
                    readonly property bool pairable: Bt.pairingDevice === null
                    readonly property bool lit: nearHover.hovered && nearRow.pairable

                    width: nearbyList.width
                    height: 36
                    radius: Theme.radius
                    color: nearRow.lit ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong)

                    Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space2
                        anchors.rightMargin: Theme.space2
                        spacing: Theme.space2

                        Text {
                            text: "\u{F00AF}"
                            color: nearRow.lit || nearRow.pairing ? Appearance.fg : Appearance.fgFaint
                            font.pixelSize: Theme.fontNormal
                            font.family: Theme.font
                            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                        }
                        Text {
                            text: nearRow.modelData.name || nearRow.modelData.deviceName
                            color: nearRow.lit || nearRow.pairing ? Appearance.fgStrong : Appearance.fg
                            font.pixelSize: Theme.fontNormal
                            font.family: Theme.font
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                        }
                        Text {
                            text: nearRow.pairing ? "Pairing…"
                                : nearRow.failed ? "Failed"
                                : "Pair"
                            color: nearRow.failed ? Appearance.red
                                : nearRow.lit || nearRow.pairing ? Appearance.fgSoft : Appearance.fgFaint
                            font.pixelSize: Theme.fontSmall
                            font.family: Theme.font
                            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                        }
                    }

                    HoverHandler { id: nearHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: nearRow.pairable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: nearRow.pairable
                        onClicked: Bt.pair(nearRow.modelData)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 16
                visible: nearbyList.count === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Bt.discovering ? "Scanning…" : "Scan to find devices"
                color: Appearance.fgFaint
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
            }
        }

        ListScrollBar {
            view: nearbyList
            Layout.fillHeight: true
            trackColor: Appearance.scrollTrack
            thumbColor: Appearance.scrollThumb
        }
    }

    // Absorbs the card's spare height when the nearby list isn't there
    // to — no adapter, or adapter off. A ColumnLayout with nothing left
    // to fill hands that height to whatever else can grow (nested
    // layouts default to fillHeight), and the header and tab rows took
    // it and spread the card out.
    Item {
        visible: !nearbyRow.visible
        Layout.fillHeight: true
    }
}
