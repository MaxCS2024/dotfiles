import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"

// The workspace chips sit together on one pill-shaped track, so the
// cluster reads as a single bar module rather than loose circles.
Item {
    id: root

    implicitWidth: row.implicitWidth + 2 * root.trackPadX
    implicitHeight: row.implicitHeight + 2 * root.trackPad
    Layout.alignment: Qt.AlignVCenter

    readonly property int trackPad: Theme.space1
    // More room at the ends than above/below, so the end chips don't
    // crowd the track's rounded caps.
    readonly property int trackPadX: Theme.space2
    readonly property int pillSize: Theme.barItemHeight

    property var screen
    property int minWorkspaces: 5
    // BarModuleLoader forwards this to any module that declares it. Only
    // needed here to hand down to WorkspacePill, whose urgent pulse
    // stops while the bar is hidden.
    property var barWindow

    readonly property var monitor: root.screen ? Hyprland.monitorFor(root.screen) : null

    readonly property var wsIds: {
        const ids = []
        for (let i = 1; i <= root.minWorkspaces; i++) ids.push(i)
        for (const w of Hyprland.workspaces.values) {
            if (w.id < 1) continue
            if (root.monitor && w.monitor && w.monitor.id !== root.monitor.id) continue
            if (ids.indexOf(w.id) === -1) ids.push(w.id)
        }
        ids.sort((a, b) => a - b)
        return ids
    }

    // Generalised from a single hardcoded "magic" scratchpad — add
    // another name here to get another special-workspace
    // pill. This machine's own Hyprland config only defines "magic"
    // (checked hypr/binds/workspaces.lua), so the single-entry case is
    // the only one actually exercised live; a second entry is
    // architecturally ready but unverified beyond that, since there's
    // nothing real here to verify it against.
    property var specialWorkspaceNames: ["magic"]

    function wsFor(id) {
        return Hyprland.workspaces.values.find(w => w.id === id)
    }
    function isActive(id) {
        return Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id === id : false
    }
    function isOccupied(id) {
        const ws = root.wsFor(id)
        return ws !== undefined && ws.toplevels.values.length > 0
    }

    function dispatchWorkspace(id) {
        Hyprland.dispatch('hl.dsp.focus({ workspace = "' + id + '" })')
    }

    function toggleSpecial(name) {
        Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + name + '")')
    }

    function switchBy(delta) {
        const ids = root.wsIds
        const cur = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : ids[0]
        let i = ids.indexOf(cur)
        if (i === -1) i = 0
        const next = ids[Math.max(0, Math.min(ids.length - 1, i + delta))]
        root.dispatchWorkspace(next)
    }

    WheelHandler {
        onWheel: (event) => root.switchBy(event.angleDelta.y > 0 ? -1 : 1)
    }

    // Sunk below the bar rather than raised above it, so the raised
    // occupied/current chips lift off the track while empty workspaces
    // sit flat on it.
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Appearance.sunken
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.space2

        Repeater {
            model: root.wsIds

            delegate: WorkspacePill {
                id: wsItem
                required property int modelData

                readonly property var ws: root.wsFor(wsItem.modelData)

                active: root.isActive(wsItem.modelData)
                occupied: root.isOccupied(wsItem.modelData)
                label: wsItem.modelData
                // The sliding indicator above draws the current state.
                showsActive: false
                urgent: wsItem.ws ? wsItem.ws.urgent : false
                barWindow: root.barWindow

                onClicked: root.dispatchWorkspace(wsItem.modelData)
            }
        }

        Repeater {
            model: root.specialWorkspaceNames

            delegate: WorkspacePill {
                id: specialItem
                required property string modelData

                readonly property var ws: Hyprland.workspaces.values.find(w => w.name === "special:" + specialItem.modelData)
                readonly property bool specialOccupied: specialItem.ws
                    ? specialItem.ws.toplevels.values.length > 0 : false
                readonly property bool specialShown: !!(root.monitor && root.monitor.activeWorkspace
                    && specialItem.ws && root.monitor.activeWorkspace.id === specialItem.ws.id)

                // Hiding an ancestor via `visible` would latch this false for
                // good — see the invariant on BarModuleLoader.qml.
                visible: specialItem.specialOccupied
                Layout.leftMargin: 2

                active: specialItem.specialShown
                occupied: specialItem.specialOccupied
                label: ""
                labelSize: Theme.fontSmall
                urgent: specialItem.ws ? specialItem.ws.urgent : false
                barWindow: root.barWindow

                onClicked: root.toggleSpecial(specialItem.modelData)
            }
        }
    }
    // One accent pill for the current workspace that slides between
    // numbers. It sits above the chips and carries its own copy of the
    // numbers in the on-accent colour, clipped to itself, so whichever
    // number it covers — mid-slide included — reads dark on accent and
    // every other number keeps its normal colour. Only x animates, so
    // there's no layout work per frame. Chips are all pillSize, so
    // index * (pillSize + spacing) is exact. Decelerating easing: it
    // leaves at once and settles softly.
    Rectangle {
        id: indicator
        readonly property int index: Hyprland.focusedWorkspace
            ? root.wsIds.indexOf(Hyprland.focusedWorkspace.id) : -1

        x: row.x + Math.max(0, indicator.index) * (root.pillSize + row.spacing)
        y: row.y + (row.height - height) / 2
        width: root.pillSize
        height: root.pillSize
        radius: height / 2
        color: Appearance.accent
        clip: true
        // opacity, not visible — the special workspace takes focus while
        // shown, and the pill should fade out rather than vanish.
        opacity: indicator.index === -1 ? 0 : 1

        Behavior on x { NumberAnimation { duration: Theme.workspaceSlideDuration; easing.type: Theme.easingDecel } }
        Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

        Row {
            x: row.x - indicator.x
            spacing: row.spacing

            Repeater {
                model: root.wsIds

                delegate: Item {
                    id: cell
                    required property int modelData
                    width: root.pillSize
                    height: root.pillSize

                    Text {
                        anchors.centerIn: parent
                        text: cell.modelData
                        font.pixelSize: Theme.fontMedium
                        font.family: Theme.font
                        font.bold: true
                        color: Appearance.bar
                    }
                }
            }
        }
    }
}
