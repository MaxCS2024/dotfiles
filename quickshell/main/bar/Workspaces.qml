import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../config"

RowLayout {
    id: root
    spacing: 4

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

    Repeater {
        model: root.wsIds

        delegate: WorkspacePill {
            id: wsItem
            required property int modelData

            readonly property var ws: Hyprland.workspaces.values.find(w => w.id === wsItem.modelData)

            active: Hyprland.focusedWorkspace
                ? Hyprland.focusedWorkspace.id === wsItem.modelData : false
            occupied: wsItem.ws !== undefined && wsItem.ws.toplevels.values.length > 0
            label: wsItem.modelData
            labelBold: wsItem.active
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
