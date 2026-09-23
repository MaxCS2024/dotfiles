import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"
import "../common"
import "../services"

// What is installed, and how to remove it.
//
// The list half of packages/PackagesWindow.qml, which is the window this
// was made into when the settings panel that hosted it as a tab was
// deleted (2026-09-21). It used to search as well, with a Search/
// Installed toggle at the top and a source to pick before either half
// would answer. The searching moved out to installer/AppInstaller.qml,
// which does all three sources at once and is what the Conf menu's
// Install row opens now; what stayed is the half that can't be asked by
// name — you remove a package by looking down a list of what you already
// have.
//
// So there is no viewMode any more, and the source filter below now only
// ever narrows the installed list.
//
// Still an Item rather than a window in its own right, so the chrome
// (scrim, focus grab, Escape, the toast its notifyRequested lands in)
// stays in one file next door and this one stays the list.
Item {
    id: root

    property string sourceFilter: "Pacman"   // "Pacman" | "AUR" | "Flatpak"

    // ── Installed state ───────────────────────────────────
    property var installedResults: []
    property bool loadingInstalled: false
    property bool _installedLoadedOnce: false
    readonly property var filteredInstalled: root.installedResults.filter(r => r.source === root.sourceFilter)


    signal notifyRequested(string title, string message, bool isError)

    function notify(title, message, urgency) {
        root.notifyRequested(title, message, urgency === "critical")
    }

    Component.onCompleted: {
        if (Packages.loadedOnce) root.installedResults = Packages.installed
        else root.loadInstalled()
    }

    // The service owns the inventory; this keeps a copy it can mark up —
    // see setUninstalling below — and re-takes it whenever the service
    // has asked the system again.
    Connections {
        target: Packages
        function onRefreshed() {
            root.installedResults = Packages.installed
            root.loadingInstalled = Packages.loading
            root._installedLoadedOnce = Packages.loadedOnce
        }
    }

    PasswordPrompt { id: pwPrompt }

    function setUninstalling(source, id, value) {
        root.installedResults = root.installedResults.map(r => {
            if (r.source === source && r.id === id) r.installing = value
            return r
        })
    }

    // ── Installed: loading ────────────────────────────────
    function loadInstalled() {
        root.loadingInstalled = true
        Packages.refresh()
    }

    // ── Uninstall ─────────────────────────────────────────
    function uninstallPacmanOrAur(entry) {
        pwPrompt.ask(
            "Remove Package",
            "Enter your password to remove " + entry.id + ".",
            (password) => {
                root.setUninstalling(entry.source, entry.id, true)
                PrivilegedExec.run(
                    ["pacman", "-Rns", "--noconfirm", entry.id],
                    password,
                    () => {
                        pwPrompt.close()
                        root.notify("Removed", entry.id + " removed successfully")
                        root.installedResults = root.installedResults.filter(r => r.id !== entry.id)
                        // The row is dropped above for immediate
                        // feedback; this re-asks the system, which is
                        // what actually knows.
                        Packages.refresh()
                    },
                    (message) => {
                        root.setUninstalling(entry.source, entry.id, false)
                        pwPrompt.showError(message)
                    }
                )
            }
        )
    }

    // Flatpak removal: --user scope runs directly (low risk, no
    // elevated privileges needed). --system scope needs root, so it
    // goes through the same password-prompt + PrivilegedExec path as
    // pacman above.
    Process { id: flatpakUninstallProc }
    property string _pendingFlatpakUninstallId: ""

    function uninstallFlatpak(entry) {
        if (entry.scope === "system") {
            pwPrompt.ask(
                "Remove Flatpak",
                "Enter your password to remove " + entry.name + " (system-wide).",
                (password) => {
                    root.setUninstalling("Flatpak", entry.id, true)
                    PrivilegedExec.run(
                        ["flatpak", "uninstall", "-y", "--system", entry.id],
                        password,
                        () => {
                            pwPrompt.close()
                            root.notify("Removed", entry.name + " uninstalled successfully")
                            root.installedResults = root.installedResults.filter(r => !(r.source === "Flatpak" && r.id === entry.id))
                            Packages.refresh()
                        },
                        (message) => {
                            root.setUninstalling("Flatpak", entry.id, false)
                            pwPrompt.showError(message)
                        }
                    )
                }
            )
            return
        }

        root.setUninstalling("Flatpak", entry.id, true)
        root._pendingFlatpakUninstallId = entry.id
        root.notify("Removing", entry.name + " (flatpak)…")
        flatpakUninstallProc.command = ["flatpak", "uninstall", "-y", "--user", entry.id]
        flatpakUninstallProc.running = false
        flatpakUninstallProc.running = true
    }

    Connections {
        target: flatpakUninstallProc
        // exitCode arrives as a signal parameter, not as a property to
        // read afterward; reading one is what made this report failure
        // regardless of the real outcome. PrivilegedExec's onExited
        // carries the same note for the privileged paths.
        function onExited(exitCode, exitStatus) {
            const app = root._pendingFlatpakUninstallId
            if (exitCode === 0) {
                root.notify("Removed", app + " uninstalled successfully")
                root.installedResults = root.installedResults.filter(r => !(r.source === "Flatpak" && r.id === app))
                Packages.refresh()
            } else {
                root.notify("Removal Failed", "Could not uninstall " + app, "critical")
                root.setUninstalling("Flatpak", app, false)
            }
        }
    }

    function uninstall(entry) {
        if (entry.source === "Flatpak") root.uninstallFlatpak(entry)
        else root.uninstallPacmanOrAur(entry)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space2

        // ── Source filter: Pacman / AUR / Flatpak ─────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            Repeater {
                model: [
                    { key: "Pacman",  badge: Appearance.badgePacman },
                    { key: "AUR",     badge: Appearance.badgeAur },
                    { key: "Flatpak", badge: Appearance.badgeFlatpak },
                ]

                delegate: Rectangle {
                    id: srcBtn
                    required property var modelData

                    readonly property bool selected: root.sourceFilter === srcBtn.modelData.key

                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.radius
                    color: srcBtn.selected ? srcBtn.modelData.badge : Appearance.surfaceAlt
                    border.color: srcBtn.selected ? srcBtn.modelData.badge : Appearance.border
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: srcBtn.modelData.key
                        // Was a ternary landing on Appearance.fgMuted when
                        // unselected — see bar/Clock.qml's matching note;
                        // the badge fill, border and bold below already
                        // carry that distinction.
                        color: Appearance.fg
                        font.pixelSize: Theme.fontSmall
                        font.bold: srcBtn.selected
                        font.family: Theme.font
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sourceFilter = srcBtn.modelData.key
                    }
                }
            }
        }

        // A translucent white line rather than common/Divider.qml's
        // Appearance.separator, which is barely lifted off the base background
        // and reads as invisible against this surface — the reason
        // quicksettings/SettingsDivider.qml existed at all before that
        // directory was deleted. One call site is not worth a file.
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.rgba(1, 1, 1, 0.12) }

        // ── The list ──────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: root.loadingInstalled ? "Loading…" : (root.filteredInstalled.length + " packages")
                color: Appearance.fgDim
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                Layout.fillWidth: true
            }

            PillButton {
                text: "Refresh"
                onClicked: root.loadInstalled()
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.filteredInstalled

            delegate: Rectangle {
                id: instRow
                required property var modelData

                width: ListView.view.width
                height: 40
                radius: Theme.radius
                color: instRowHover.hovered ? Appearance.hover : Appearance.clear(Appearance.hover)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space2
                    anchors.rightMargin: Theme.space2
                    spacing: Theme.space2

                    Rectangle {
                        implicitWidth: instSourceLabel.implicitWidth + 10
                        implicitHeight: 20
                        radius: Theme.radius
                        color: instRow.modelData.source === "Pacman" ? Appearance.badgePacman
                             : instRow.modelData.source === "AUR" ? Appearance.badgeAur
                             : Appearance.badgeFlatpak

                        Text {
                            id: instSourceLabel
                            anchors.centerIn: parent
                            text: instRow.modelData.source
                            color: Appearance.fg
                            font.pixelSize: 9
                            font.family: Theme.font
                        }
                    }

                    Text {
                        text: instRow.modelData.name
                        color: Appearance.fg
                        font.pixelSize: Theme.fontNormal
                        font.family: Theme.font
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: instRow.modelData.scope === "system"
                        text: "system"
                        color: Appearance.orange
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.font
                    }

                    Text {
                        visible: instRow.modelData.version !== ""
                        text: instRow.modelData.version
                        color: Appearance.fgFaint
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.font
                    }

                    Rectangle {
                        implicitWidth: uninstallLabel.implicitWidth + 16
                        implicitHeight: 24
                        radius: Theme.radius
                        color: uninstallHover.hovered ? Appearance.dangerBg : Appearance.clear(Appearance.dangerBg)
                        border.color: Appearance.dangerBorder
                        border.width: 1
                        opacity: instRow.modelData.installing ? 0.5 : 1

                        Text {
                            id: uninstallLabel
                            anchors.centerIn: parent
                            text: instRow.modelData.installing ? "…" : "Uninstall"
                            color: Appearance.red
                            font.pixelSize: Theme.fontTiny
                            font.family: Theme.font
                        }

                        HoverHandler { id: uninstallHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: !instRow.modelData.installing
                            onClicked: root.uninstall(instRow.modelData)
                        }
                    }
                }

                HoverHandler { id: instRowHover }
            }

            Text {
                anchors.centerIn: parent
                visible: !root.loadingInstalled && root.filteredInstalled.length === 0
                text: "No " + root.sourceFilter + " packages installed"
                color: Appearance.fgDim
                font.pixelSize: Theme.fontNormal
                font.family: Theme.font
            }
        }
    }
}
