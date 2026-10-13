pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Hyprland state changes (AGENTS.md, Hyprland events): a brief notice
// when a submap starts or ends, when the keyboard layout changes, and
// "Workspace N" on a workspace switch. Nothing persistent: no workspace
// list.
Singleton {
    id: root

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!Config.hyprlandEvents)
                return
            if (event.name === "submap")
                root.submapEvent(event.data)
            else if (event.name === "activelayout")
                root.layoutEvent(event.data)
        }
    }

    function submit(spec) {
        ActivityQueue.submit(Object.assign({
            transient: true,
            profile: "hyprland",
            timeout: Config.hyprlandTimeout,
            face: "",
            progress: -1,
        }, spec))
    }

    // ── Submap ──
    // Hyprland sends the submap's name on entering it and "" on leaving.
    property string submap: ""

    function submapEvent(name) {
        if (name === submap)
            return
        const left = submap
        submap = name
        submit({
            key: "submap",
            icon: "\u{f0328}",
            label: name !== "" ? `Submap – ${name}` : `Submap – ${left} off`,
        })
    }

    // ── Keyboard layout ──
    // activelayout comes as "keyboard,layout" from every keyboard device,
    // each with a layout of its own; only a change from that same
    // keyboard's last layout counts, and a keyboard's first report only
    // sets it. Comparing against one "main" keyboard flashes whenever
    // another one (the volume keys' device, a virtual keyboard) is used.
    // Virtual keyboards (wtype, dictation typing) are left out.
    property var layouts: ({})

    Process {
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                const known = Object.assign({}, root.layouts)
                for (const k of JSON.parse(text).keyboards ?? [])
                    if (known[k.name] === undefined)
                        known[k.name] = k.active_keymap
                root.layouts = known
            }
        }
    }

    function layoutEvent(data) {
        const i = data.indexOf(",")
        const keyboard = data.slice(0, i)
        const layout = data.slice(i + 1)
        if (i <= 0 || layout === "" || keyboard.startsWith("hl-virtual-keyboard"))
            return
        const before = layouts[keyboard]
        if (before === layout)
            return
        const known = Object.assign({}, layouts)
        known[keyboard] = layout
        layouts = known
        if (before !== undefined)
            submit({ key: "layout", icon: "\u{f030c}", label: `Layout – ${layout}` })
    }

    // ── Workspace ──
    // The dynamic-island's flash, at the user's request: switching to a
    // workspace shows "Workspace N" (its id, never its name) for
    // `Config.workspaceTimeout`, sliding in from the side switched
    // towards. Special workspaces (id below 1) are skipped. Follows the
    // focused workspace, so focusing another monitor counts too.
    property int lastWorkspace: Hyprland.focusedWorkspace?.id ?? 0
    readonly property int focusedWorkspace: Hyprland.focusedWorkspace?.id ?? 0

    onFocusedWorkspaceChanged: workspaceEvent(focusedWorkspace)

    function workspaceEvent(id) {
        if (!Config.workspaces || id < 1 || id === lastWorkspace)
            return
        const direction = id > lastWorkspace ? 1 : -1
        lastWorkspace = id
        submit({
            key: "workspace",
            face: "workspace",
            timeout: Config.workspaceTimeout,
            icon: "",
            label: `Workspace ${id}`,
            number: id,
            direction,
            // The island slides it in on arrival instead of fading, at the
            // idle clock's size (the dynamic-island's 24 high, 32 in).
            slide: direction,
            small: true,
        })
    }

    // ── Event tests ──
    // Feeds made-up events through the same handling (AGENTS.md, Testing).
    IpcHandler {
        target: "hyprland"

        // "" leaves the submap.
        function submap(name: string): void { root.submapEvent(name) }
        // The raw event data, "keyboard,layout".
        function layout(data: string): void { root.layoutEvent(data) }
        // What switching to workspace `id` shows; nothing switches.
        function workspace(id: int): void { root.workspaceEvent(id) }
    }
}
