import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"
import "../theme"

// The one leaf of the Conf menu that answers a question instead of
// doing something: About › System, drawn as a list of label/value pairs.
//
// It is a mapping of services/SystemInfo.qml, which the quick settings
// dashboard and the system settings tab read too. This view used to
// gather the same facts with a shell script of its own — three copies of
// one question, which is what that service exists to end.
//
// Defaults (under Apps then, Setup now) was the second leaf and kept a
// script of its own here, printing "label<TAB>value<TAB>sub" lines for
// the XDG handlers and the four app roles in hypr/modules/vars.lua. It
// became a branch of settable rows on 2026-09-13 (menu/ConfMenu.qml's
// own `defaultRoles`, resolved by menu/MenuActions.qml) and the script
// went with it:
// reporting what a default is and offering to change it are one walk of
// the machine, and doing it in two places is how the two answers drift.
Item {
    id: view

    // "system" is the only kind left. Kept as a string rather than
    // collapsed away: the tree's `info:` rows name it, and ConfMenu hands
    // whatever they say straight to load().
    property string kind: ""

    // Type sizes come from the slab this view is a leaf of rather than
    // from Theme: it stands in for the list, at the same size, and a
    // second copy of those numbers here is how the two drift. See
    // menu/ConfMenu.qml. The defaults are the sizes this view used
    // before that scale existed.
    property int fontBody: Theme.fontNormal
    property int fontSub: Theme.fontXSmall

    readonly property var rows: view.systemRows
    readonly property bool loading: !SystemInfo.ready

    // Only the height is consulted — the consumer gives this its width.
    implicitHeight: column.implicitHeight

    // The service keeps `uptime` as `uptime -p` gives it ("up 1 hour"),
    // which reads as a sentence beside a label that already says Uptime.
    readonly property var systemRows: [
        { label: "Kernel", value: SystemInfo.kernel, sub: "" },
        { label: "Distro", value: SystemInfo.osName, sub: "" },
        { label: "Host", value: SystemInfo.hostname, sub: "" },
        { label: "Uptime", value: SystemInfo.uptime.replace(/^up /, ""), sub: "" },
        { label: "Hyprland", value: SystemInfo.hyprland, sub: "" },
        { label: "Quickshell", value: SystemInfo.quickshell, sub: "" },
        { label: "Session", value: SystemInfo.session, sub: "" },
        { label: "CPU", value: SystemInfo.cpu, sub: "" },
        { label: "Memory", value: SystemInfo.memory, sub: "" },
        { label: "Packages", value: SystemInfo.packages === "" ? "" : SystemInfo.packages + " installed", sub: "" }
    ]

    function load(which) {
        view.kind = which
        // Nothing to spawn here — the service re-reads the half of its
        // answers that can have changed.
        SystemInfo.refresh()
    }

    ColumnLayout {
        id: column
        width: view.width
        spacing: 2

        Text {
            visible: view.loading
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            text: "Reading…"
            color: Appearance.fgMuted
            font.family: Theme.font
            font.pixelSize: view.fontBody
        }

        Repeater {
            model: view.rows

            delegate: RowLayout {
                id: infoRow
                required property var modelData

                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: infoRow.modelData.label
                    color: Appearance.fgMuted
                    font.family: Theme.font
                    font.pixelSize: view.fontBody
                    // Wide enough for the longest label above
                    // ("Quickshell", 10 characters at 0.6em), which is
                    // 90px at the 15px this now renders at.
                    Layout.preferredWidth: 96
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0

                    Text {
                        // The service can leave a field empty — a
                        // fact it hasn't answered for yet.
                        text: infoRow.modelData.value || "—"
                        color: Appearance.fgStrong
                        font.family: Theme.font
                        font.pixelSize: view.fontBody
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: infoRow.modelData.sub !== ""
                        text: infoRow.modelData.sub
                        color: Appearance.fgDim
                        font.family: Theme.font
                        font.pixelSize: view.fontSub
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }

        Text {
            visible: !view.loading && view.rows.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            text: "Nothing to show"
            color: Appearance.fgMuted
            font.family: Theme.font
            font.pixelSize: view.fontBody
        }
    }
}
