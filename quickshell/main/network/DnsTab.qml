import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

// Four buttons and a field, so it sits at the top of the card
// with a spacer under it rather than being stretched down the
// column the way the two list-bearing tabs are.
// The DNS tab: which resolver this machine is using, four providers to
// pick from, and a field for anything else.
//
// `customShown` lived on network/NetworkPanel.qml until 2026-09-21 even
// though nothing outside this tab ever read it, which is what happens
// when a tab has no file to keep its own state in.
ColumnLayout {
    id: root

    // Whether the custom-resolver field is showing.
    property bool customShown: false
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Theme.space2

    InfoRow {
        label: "Current"
        value: Network.currentDns
        valueMaxWidth: 170
        labelColor: Appearance.fg
    }

    // One provider per row (user request 2026-09-16). The
    // two-by-two grid existed because four labels across
    // 292px clips "Cloudflare"; now that DNS has a tab to
    // itself there is height to spend instead. Labels only,
    // left-aligned: a short word centred in a full-width row
    // reads as a stretched button rather than a list of
    // choices.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.space2

        Repeater {
            model: [
                { key: "default",    label: "Automatic" },
                { key: "cloudflare", label: "Cloudflare" },
                { key: "google",     label: "Google" },
                { key: "custom",     label: "Custom" }
            ]

            delegate: Rectangle {
                id: dnsBtn
                required property var modelData

                readonly property bool selected: Network.dnsProvider === dnsBtn.modelData.key

                Layout.fillWidth: true
                implicitHeight: 32
                radius: Theme.radius
                color: dnsBtn.selected ? SlabStyle.tintSelected
                     : (dnsHover2.hovered ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong))
                border.width: dnsBtn.selected ? 0 : 1
                border.color: Appearance.border

                Behavior on color {
                    ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.space3
                    anchors.rightMargin: Theme.space3
                    text: dnsBtn.modelData.label
                    color: dnsBtn.selected ? Appearance.fgStrong : Appearance.fgSoft
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    elide: Text.ElideRight
                }

                HoverHandler { id: dnsHover2 }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (dnsBtn.modelData.key === "custom") {
                            root.customShown = true
                        } else {
                            root.customShown = false
                            Network.applyDns(dnsBtn.modelData.key)
                        }
                    }
                }
            }
        }
    }

    // Only Custom needs somewhere to type; the other three
    // carry their own addresses.
    RowLayout {
        Layout.fillWidth: true
        visible: root.customShown
        spacing: Theme.space2

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 28
            radius: Theme.radius
            color: Appearance.surfaceAlt
            border.width: 1
            border.color: Appearance.border

            TextInput {
                id: dnsField
                anchors.fill: parent
                anchors.margins: Theme.space1
                anchors.leftMargin: Theme.space2
                anchors.rightMargin: Theme.space2
                color: Appearance.fg
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                clip: true
                onAccepted: Network.applyDns("custom", dnsField.text)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: dnsField.text.length === 0
                    text: "e.g. 9.9.9.9 149.112.112.112"
                    color: Appearance.fgDim
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                }
            }
        }

        Rectangle {
            implicitWidth: dnsApplyLabel.implicitWidth + 14
            implicitHeight: 28
            radius: Theme.radius
            color: dnsApplyHover.hovered ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong)
            border.width: 1
            border.color: Appearance.border

            Text {
                id: dnsApplyLabel
                anchors.centerIn: parent
                text: "Apply"
                color: Appearance.accent
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
            }

            HoverHandler { id: dnsApplyHover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: dnsField.text.length > 0
                onClicked: Network.applyDns("custom", dnsField.text)
            }
        }
    }

    Item { Layout.fillHeight: true }
}
