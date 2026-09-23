import Quickshell
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"
import "../common"
import "../theme"

// Full-screen ink lock screen. Built as a **visual-only preview**, per
// explicit user decision (2026-09-03, asked because it was flagged at
// the time as the highest-risk thing here): the
// look only, not wired to `SUPER+L`, not replacing `hyprlock`, and not
// using `WlSessionLock` — that API actually seizes the session (no
// PAM auth behind it has been built or reviewed yet, see the open
// decision this deferred), so a plain `PanelWindow` overlay is the
// correct primitive here, not a step toward the real thing. Reachable
// only via `qs ipc call -- lockscreen-preview toggle` (routed through
// `services/Panels.qml`, same pattern as every other LazyLoader window)
// for whoever picks this up next to look at without wiring real auth
// first. The password field is decorative: Enter always "fails" (there
// is nothing to check it against) and just replays the shake animation
// README specifies, so that motion is at least verified against
// something real rather than asserted from the code.
ShellSurface {
    id: lock

    surfaceNamespace: "quickshell:lockscreen-preview"
    surfaceName: "lockscreen-preview"
    focusTarget: passwordInput

    anchors { top: true; bottom: true; left: true; right: true }

    // This surface is the whole screen, so it has no outside to click.
    // A focus grab here would not be merely unwanted, it would have
    // nothing to grab away from.
    grabFocus: false

    // 220, not ShellSurface's 200: this fades on the shell-wide panel
    // duration rather than the rails' toast curve, and a refactor is not
    // the place to quietly shorten it.
    exitDuration: Theme.animPanel

    // No `date` subprocess — same reasoning as `bar/Clock.qml`'s
    // `SystemClock`, and the same hand-rolled Swedish weekday/month
    // names (not Qt's locale default) so this reads consistently with
    // the bar's own date line rather than switching languages mid-shell.
    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    readonly property var _weekdays: ["Söndag", "Måndag", "Tisdag", "Onsdag", "Torsdag", "Fredag", "Lördag"]
    readonly property var _months: ["Januari", "Februari", "Mars", "April", "Maj", "Juni",
        "Juli", "Augusti", "September", "Oktober", "November", "December"]
    readonly property string dateLabel: lock._weekdays[sysClock.date.getDay()] + ", "
        + sysClock.date.getDate() + " " + lock._months[sysClock.date.getMonth()]

    Rectangle {
        id: ground
        anchors.fill: parent
        color: Appearance.bar
        opacity: lock.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard } }

        focus: true
        // Escape closes the PREVIEW only — a real lock screen must never
        // let any key dismiss it. Kept far away from anything the real
        // implementation would reuse, so this can't accidentally survive
        // into that version.
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                lock.close()
                event.accepted = true
            }
        }
        onVisibleChanged: if (lock.shown) ground.forceActiveFocus()

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: lock.dateLabel
                color: Appearance.fgMuted
                font.family: Theme.fontHeading
                font.pixelSize: Theme.fontSmall
                font.capitalization: Font.SmallCaps
                font.letterSpacing: Theme.tracking(Theme.fontSmall, 0.24)
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 16
                Layout.bottomMargin: 6
                text: Qt.formatDateTime(sysClock.date, "HH:mm")
                color: Appearance.fgStrong
                font.family: Theme.font
                font.pixelSize: Theme.fontLockTime
                font.letterSpacing: Theme.tracking(Theme.fontLockTime, -0.02)
                font.features: ({ "tnum": 1 })
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 150
                height: 1
                color: Appearance.separator
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 14
                text: "Preview only — not a real session lock"
                font.italic: true
                color: Appearance.fgSoft
                font.family: Theme.font
                font.pixelSize: Theme.fontProse
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 38
                spacing: 12

                Text {
                    text: Quickshell.env("USER") || "user"
                    color: Appearance.fgMuted
                    font.family: Theme.fontHeading
                    font.pixelSize: Theme.fontSmall
                    font.capitalization: Font.SmallCaps
                    font.letterSpacing: Theme.tracking(Theme.fontSmall, 0.16)
                }

                Item {
                    id: passwordField
                    width: 230
                    implicitHeight: passwordInput.implicitHeight + 14

                    property real shakeOffset: 0
                    transform: Translate { x: passwordField.shakeOffset }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Appearance.border
                    }

                    FocusRing {
                        active: passwordInput.activeFocus
                    }

                    TextInput {
                        id: passwordInput
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 7
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        color: Appearance.fgStrong
                        font.family: Theme.font
                        font.pixelSize: Theme.fontMedium
                        font.letterSpacing: Theme.tracking(Theme.fontMedium, 0.3)

                        // Nothing real to check this against yet (see the
                        // file header) — every submit "fails" and replays
                        // the shake, which is the one piece of motion
                        // this preview exists to demonstrate honestly.
                        Keys.onReturnPressed: shakeAnim.restart()
                        Keys.onEnterPressed: shakeAnim.restart()
                    }

                    SequentialAnimation {
                        id: shakeAnim
                        loops: 1
                        NumberAnimation { target: passwordField; property: "shakeOffset"; to: -Theme.lockShakeDistance; duration: Theme.lockShakeDuration / 6; easing.type: Theme.easingStandard }
                        NumberAnimation { target: passwordField; property: "shakeOffset"; to: Theme.lockShakeDistance; duration: Theme.lockShakeDuration / 3; easing.type: Theme.easingStandard }
                        NumberAnimation { target: passwordField; property: "shakeOffset"; to: -Theme.lockShakeDistance; duration: Theme.lockShakeDuration / 3; easing.type: Theme.easingStandard }
                        NumberAnimation { target: passwordField; property: "shakeOffset"; to: 0; duration: Theme.lockShakeDuration / 6; easing.type: Theme.easingStandard }
                    }
                }

                Text {
                    text: "→"
                    color: Appearance.fgMuted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontMedium
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 30
                text: "ESC TO CLOSE PREVIEW"
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontMicro
                font.letterSpacing: Theme.tracking(Theme.fontMicro, 0.14)
                color: Appearance.fgFaint
            }
        }
    }
}
