import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"
import "../theme"

// The four DNS providers and the field Custom opens, under the Wi-Fi
// tab's DNS row. They were the DNS tab until 2026-09-28, when the tab
// went and they moved here (user request).
ColumnLayout {
    id: root

    // Whether the custom-resolver field is showing.
    property bool customShown: false
    Layout.fillWidth: true
    spacing: Theme.space2

    // Four across: the Wi-Fi tab's height belongs to the
    // network lists. The DNS tab stacked them one to a row
    // (2026-09-16) because four labels across the old 292px
    // card clipped "Cloudflare"; the card is wider now.
    RowLayout {
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
                // Equal columns rather than word-width ones.
                Layout.preferredWidth: 1
                Layout.minimumWidth: 0
                implicitHeight: 28
                radius: Theme.radius
                color: dnsBtn.selected ? Appearance.selected
                     : (dnsHover.hovered ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong))
                border.width: dnsBtn.selected ? 0 : 1
                border.color: Appearance.border

                Behavior on color {
                    ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.space1
                    anchors.rightMargin: Theme.space1
                    horizontalAlignment: Text.AlignHCenter
                    text: dnsBtn.modelData.label
                    color: dnsBtn.selected ? Appearance.fgStrong : Appearance.fgSoft
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    elide: Text.ElideRight
                }

                HoverHandler { id: dnsHover }
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
}
