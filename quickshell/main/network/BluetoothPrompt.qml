import Quickshell
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

// What the pairing agent asks (services/BtAgent.qml): compare a code, type
// a PIN, or type a code on the device itself. A surface of its own rather
// than part of the network rail, because a phone can ask to pair while the
// rail is closed.
//
// A small window centred on screen. Enter answers yes, Escape or a click
// anywhere else answers no — the same as ignoring a pairing request, which
// is what a stray click should amount to.
ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:bluetooth-prompt"
    focusTarget: keys
    openOnCompleted: false

    implicitWidth: 320 + 2 * Theme.space4
    implicitHeight: card.implicitHeight + 2 * Theme.space4
    exclusiveZone: 0

    // The question on screen. Held here, not read live off BtAgent.current,
    // so the card keeps its words while it fades out after the answer.
    property var prompt: null
    property bool answered: false

    readonly property string kind: panel.prompt ? panel.prompt.kind : ""
    readonly property string name: panel.prompt ? panel.prompt.name : ""
    readonly property bool displayOnly: panel.kind.startsWith("display-")
    readonly property bool needsText: panel.kind === "pin" || panel.kind === "passkey"

    function show(p) {
        const same = panel.prompt && p && panel.prompt.id === p.id
        panel.prompt = p
        if (same) return
        panel.answered = false
        field.text = ""
        panel.open()
        if (panel.needsText) field.forceActiveFocus()
    }

    function answer(accept) {
        if (!panel.prompt || panel.answered) return
        if (panel.needsText && accept && field.text.trim() === "") return
        panel.answered = true
        // A display prompt has nothing to answer; saying no to one means
        // stopping the pairing it belongs to.
        if (panel.displayOnly && !accept) {
            const d = Bt.devices.find(d => d.address === panel.prompt.address)
            if (d && d.pairing) d.cancelPair()
        }
        BtAgent.respond(panel.prompt.id, accept, field.text.trim())
        panel.close()
    }

    Connections {
        target: BtAgent
        function onCurrentChanged() {
            if (BtAgent.current) panel.show(BtAgent.current)
            else if (panel.shown) { panel.answered = true; panel.close() }
        }
    }

    // Loaded on the first question, which has already arrived by now.
    Component.onCompleted: if (BtAgent.current) panel.show(BtAgent.current)

    // Closed without an answer: the focus grab cleared, or Escape.
    onSurfaceClosed: panel.answer(false)

    component DialogButton: Rectangle {
        id: btn
        property alias text: btnLabel.text
        // Primary is a step up the ladder with its label in accent, as
        // common/PasswordPrompt.qml's Confirm.
        property bool primary: false
        signal clicked()

        implicitWidth: btnLabel.implicitWidth + 20
        implicitHeight: 28
        radius: Theme.radius
        color: btn.primary ? (btnHover.hovered ? Appearance.selected : Appearance.hoverStrong)
                           : (btnHover.hovered ? Appearance.hoverStrong : Appearance.hover)

        Behavior on color {
            ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
        }

        Text {
            id: btnLabel
            anchors.centerIn: parent
            color: btn.primary ? Appearance.accent : Appearance.fgStrong
            font.pixelSize: Theme.fontSmall
            font.family: Theme.font
        }

        HoverHandler { id: btnHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 320
        implicitHeight: content.implicitHeight + 2 * Theme.cardPadding
        radius: Theme.radius
        color: Appearance.surface
        border.color: Appearance.border
        border.width: 1

        opacity: panel.shown ? 1 : 0
        scale: panel.shown ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingDecel } }
        Behavior on scale { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingDecel } }

        // Holds focus for Enter/Escape when there is no text field to.
        Item {
            id: keys
            focus: true
            Keys.onReturnPressed: panel.answer(true)
            Keys.onEnterPressed: panel.answer(true)
            Keys.onEscapePressed: panel.answer(false)
        }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Theme.cardPadding
            spacing: Theme.space2

            Text {
                text: panel.kind === "confirm" ? "Pair with " + panel.name + "?"
                    : panel.kind === "authorize" ? panel.name + " wants to pair"
                    : panel.kind === "pin" ? "PIN for " + panel.name
                    : panel.kind === "passkey" ? "Passkey for " + panel.name
                    : "Type this on " + panel.name
                color: Appearance.fgStrong
                font.bold: true
                font.pixelSize: Theme.fontMedium
                font.family: Theme.font
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Text {
                text: panel.kind === "confirm" ? "Pair only if " + panel.name + " shows the same code."
                    : panel.kind === "authorize" ? (panel.prompt ? panel.prompt.address : "")
                    : panel.kind === "pin" ? "Shown on the device or in its manual. Often 0000 or 1234."
                    : panel.kind === "passkey" ? "The number the device shows."
                    : "Then press Enter on it."
                color: Appearance.fgMuted
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            // The code, digit by digit, so a keyboard typing it can mark
            // how far it has got: digits already typed drop to fgFaint and
            // the rest stay fgStrong. fgFaint because a typed digit is done
            // with — fgMuted was too close to fgStrong at this size to show
            // progress at all.
            Row {
                visible: panel.prompt !== null && panel.prompt.code !== undefined
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.space2
                Layout.bottomMargin: Theme.space1
                spacing: Theme.space1

                Repeater {
                    model: panel.prompt && panel.prompt.code ? panel.prompt.code.split("") : []

                    delegate: Text {
                        required property string modelData
                        required property int index

                        readonly property bool typed: panel.prompt && panel.prompt.entered !== undefined
                                                      && index < panel.prompt.entered
                        text: modelData
                        color: typed ? Appearance.fgFaint : Appearance.fgStrong
                        font.pixelSize: Theme.fontHuge
                        font.family: Theme.fontMono
                        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                    }
                }
            }

            Rectangle {
                visible: panel.needsText
                Layout.fillWidth: true
                Layout.topMargin: Theme.space1
                implicitHeight: 32
                radius: Theme.radius
                color: Appearance.surfaceAlt
                border.color: Appearance.border
                border.width: 1

                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.margins: Theme.space2
                    verticalAlignment: TextInput.AlignVCenter
                    color: Appearance.fg
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.fontMono
                    clip: true
                    // A passkey is at most six digits (0–999999); a legacy
                    // PIN is up to 16 characters of anything.
                    maximumLength: panel.kind === "passkey" ? 6 : 16
                    inputMethodHints: panel.kind === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
                    validator: RegularExpressionValidator {
                        regularExpression: panel.kind === "passkey" ? /[0-9]*/ : /.*/
                    }

                    Keys.onReturnPressed: panel.answer(true)
                    Keys.onEnterPressed: panel.answer(true)
                    Keys.onEscapePressed: panel.answer(false)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space2
                spacing: Theme.space2

                Item { Layout.fillWidth: true }

                DialogButton {
                    text: "Cancel"
                    onClicked: panel.answer(false)
                }

                DialogButton {
                    visible: !panel.displayOnly
                    primary: true
                    text: "Pair"
                    onClicked: panel.answer(true)
                }
            }
        }
    }
}
