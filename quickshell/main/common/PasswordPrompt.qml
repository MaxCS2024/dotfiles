import QtQuick
import QtQuick.Layouts
import "../config"

// Reusable password entry modal. Any component can instantiate this as
// an overlay (anchors.fill: parent on whatever it should cover) and
// drive it via open()/close()/showError(), listening to the
// accepted(password) / cancelled() signals, or hand ask() a callback and
// let this hold it. This component holds no
// knowledge of what the password is used for — see
// services/PrivilegedExec.qml for the piece that actually runs a
// privileged command with it.
Item {
    id: root

    anchors.fill: parent
    visible: shown
    enabled: shown
    z: 100

    property bool shown: false
    property string title: "Authentication Required"
    property string subtitle: ""
    property string errorText: ""

    signal accepted(string password)
    signal cancelled()

    // Ask for a password and run `action(password)` when one is given.
    //
    // The alternative — listen to accepted() and park the closure until
    // it fires — is what both callers of this component were doing, in
    // fourteen identical lines each: a `_pendingPwAction` property, a
    // requestPassword() that set it, an onAccepted that called it and an
    // onCancelled that nulled it. That is a required setup step the
    // interface was pushing onto every caller, and the implementation it
    // was hiding is the three lines below.
    //
    // The action survives showError(), because a wrong password is meant
    // to be retried with the prompt still up. close() drops it, which
    // covers both the cancel path and a caller closing on success.
    property var _pendingAction: null

    function ask(titleText, subtitleText, action) {
        root._pendingAction = action
        root.open(titleText, subtitleText)
    }

    onAccepted: (password) => {
        if (root._pendingAction) root._pendingAction(password)
    }

    function open(titleText, subtitleText) {
        root.title = titleText || "Authentication Required"
        root.subtitle = subtitleText || ""
        root.errorText = ""
        passwordField.text = ""
        root.shown = true
        passwordField.forceActiveFocus()
    }

    function close() {
        root.shown = false
        passwordField.text = ""
        root._pendingAction = null
    }

    // Called by whatever consumed the password, if the attempt failed
    // (e.g. wrong password) — keeps the prompt open with an inline
    // error and refocused, rather than closing silently. Submitting
    // again re-fires accepted() with the newly typed password.
    function showError(message) {
        root.errorText = message
        passwordField.text = ""
        passwordField.forceActiveFocus()
    }

    function submit() {
        if (passwordField.text.length === 0) return
        root.accepted(passwordField.text)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: { root.cancelled(); root.close() }
    }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: 320
        implicitHeight: content.implicitHeight + 28
        radius: Theme.radius
        color: Theme.surface
        border.color: Theme.border
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            Text {
                text: root.title
                color: Theme.fgStrong
                font.bold: true
                font.pixelSize: Theme.fontMedium
                font.family: Theme.font
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Text {
                visible: root.subtitle !== ""
                text: root.subtitle
                color: Theme.fgMuted
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: 30
                radius: Theme.radius
                color: Theme.surfaceAlt
                border.color: root.errorText !== "" ? Theme.red : Theme.border
                border.width: 1

                TextInput {
                    id: passwordField
                    anchors.fill: parent
                    anchors.margins: 7
                    color: Theme.fg
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font
                    echoMode: TextInput.Password
                    clip: true

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.submit()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            root.cancelled()
                            root.close()
                            event.accepted = true
                        }
                    }
                }
            }

            Text {
                visible: root.errorText !== ""
                text: root.errorText
                color: Theme.red
                font.pixelSize: Theme.fontTiny
                font.family: Theme.font
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: cancelLabel.implicitWidth + 18
                    implicitHeight: 26
                    radius: Theme.radius
                    color: cancelHover.hovered ? Theme.hoverStrong : "transparent"
                    border.color: Theme.border
                    border.width: 1

                    Text {
                        id: cancelLabel
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Theme.fgSoft
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                    }

                    HoverHandler { id: cancelHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.cancelled(); root.close() }
                    }
                }

                Rectangle {
                    implicitWidth: okLabel.implicitWidth + 18
                    implicitHeight: 26
                    radius: Theme.radius
                    color: okHover.hovered ? Theme.hoverStrong : Theme.selected
                    border.color: Theme.green
                    border.width: 1

                    Text {
                        id: okLabel
                        anchors.centerIn: parent
                        text: "Confirm"
                        color: Theme.green
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                    }

                    HoverHandler { id: okHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.submit()
                    }
                }
            }
        }
    }
}
