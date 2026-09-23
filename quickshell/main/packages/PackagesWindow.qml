import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

// What is installed, and how to remove it — the window.
//
// The other half of the pair installer/AppInstaller.qml already made: one
// window to find something and put it on the machine, one to look down
// what is already there and take something off. This was the Packages tab
// of the settings panel until that panel was deleted (2026-09-21), and it
// is the last of its tabs to need a home of its own — everything else in
// it had already been replaced by a rail, a card or a window.
//
// Chrome only. The list, the three source filters and every privileged
// removal are packages/PackagesList.qml's, unchanged by the move; this
// file is the scrim, the box, Escape, and the toast that the list's
// notifyRequested lands in. The window itself — the layershell lines,
// the open/close lifecycle and the focus grab — belongs to
// common/ShellSurface.qml, which this was the first surface to take.
// The installer is the model for the rest of it, including the
// slightly-above-centre y: a list you are about to scroll starts high.
ShellSurface {
    id: window

    surfaceNamespace: "quickshell:packages"
    surfaceName: "packages"
    focusTarget: box

    // Full screen: the scrim dims the whole desktop behind the box.
    anchors { top: true; bottom: true; left: true; right: true }


    // The Conf menu's Remove row names a source; a bare open keeps
    // whichever one was last looked at. The list loads itself on first
    // build, so there is nothing else to kick off here.
    onSurfaceOpened: (source) => { if (source) list.sourceFilter = source }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: window.shown ? 0.5 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard }
        }
    }

    // ── The window ────────────────────────────────────────
    Rectangle {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter
        // The installer's proportions, one for one: these two windows are
        // the same question asked in both directions and should not be
        // two different sizes of box.
        width: Math.min(1040, Math.round(parent.width * 0.6))
        height: Math.min(820, Math.round(parent.height * 0.76))
        y: Math.round((parent.height - box.height) / 2.6)
        radius: Theme.radius
        color: Appearance.surface
        border.width: Theme.hyprBorderWidth
        border.color: Appearance.border

        focus: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                window.close()
                event.accepted = true
            }
        }

        opacity: window.shown ? 1 : 0
        scale: window.shown ? 1 : 0.97
        Behavior on opacity {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard }
        }
        Behavior on scale {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingDecel }
        }

        layer.enabled: true
        layer.effect: PopupShadow {}
        HyprFrame {
            frameWidth: box.border.width
            targetRadius: box.radius
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space4
            spacing: Theme.space3

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                SectionTitle { text: "Packages" }

                // The way to the other half. The installer takes this
                // window's place on screen rather than stacking on it:
                // two full-screen scrims over each other would dim the
                // desktop twice, and the two lists answer different
                // questions anyway.
                PillButton {
                    text: "Install"
                    onClicked: {
                        window.close()
                        Panels.open("installer", "")
                    }
                }
            }

            PackagesList {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                onNotifyRequested: (title, message, isError) => {
                    toast.show(title, message, isError)
                    Notifications.addManual(title, message, isError ? "critical" : "normal")
                }
            }
        }
    }

    Toast {
        id: toast
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.space4
        z: 50
    }
}
