pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Which audio devices have nothing plugged into them. PipeWire makes a
// node for every port the card has, whether or not anything is on the
// other end: this laptop's SOF card (skl_hda_dsp_generic, UCM "HiFi")
// gives three HDMI/DP sinks that exist with no monitor attached, and a
// headset-jack microphone with no headset in it — so the volume rail
// listed four outputs and two inputs where one of each was real
// (found 2026-09-25, first boot on this laptop).
//
// Quickshell's PwNode has no port availability, but pulse does: each
// sink's and source's active port carries "available", "not available"
// or "availability unknown" (built-in speakers and mics report unknown,
// jacks and HDMI report the other two). Only "not available" is hidden,
// so a device the card can't vouch for either way stays listed.
//
// Plugging a cable in changes the port without touching the node, so
// PipeWire's own node list never notices. `pactl subscribe` reports it
// as a change on the card, and a new or removed sink/source covers
// Bluetooth and USB devices; everything else on that stream (clients,
// volume changes) is ignored rather than re-querying on every slider tick.
//
// pactl comes from libpulse, which is optional (DEPENDENCIES.md): without
// it nothing is hidden, and the subscription isn't retried.
Singleton {
    id: root

    // Node names (PwNode.name) whose active port is "not available".
    property var unplugged: []

    function isUnplugged(node) {
        return !!node && root.unplugged.indexOf(node.name) !== -1
    }

    function _refresh() {
        queryProc.running = false
        queryProc.running = true
    }

    Process {
        id: queryProc
        command: ["sh", "-c",
            "pactl -f json list sinks 2>/dev/null; echo; pactl -f json list sources 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = []
                for (const chunk of text.split("\n")) {
                    if (chunk.trim() === "") continue
                    let devices = []
                    try { devices = JSON.parse(chunk) } catch (e) { continue }
                    for (const d of devices) {
                        const port = (d.ports || []).find(p => p.name === d.active_port)
                        if (port && port.availability === "not available") names.push(d.name)
                    }
                }
                root.unplugged = names
            }
        }
    }

    // Several events arrive per plug (card, then each sink/source on it);
    // one query after they settle is enough.
    Timer {
        id: debounce
        interval: 250
        onTriggered: root._refresh()
    }

    Process {
        id: subscribeProc
        running: true
        // Through sh so a missing pactl is exit status 127 rather than a
        // process that never starts.
        command: ["sh", "-c", "exec pactl subscribe"]
        stdout: SplitParser {
            onRead: line => {
                if (/on card #|'(new|remove)' on (sink|source) #/.test(line)) debounce.restart()
            }
        }
        // pipewire-pulse restarting ends the subscription; pick it back up.
        // 127 is no pactl at all, which retrying every 2s won't change.
        onExited: code => { if (code !== 127) restartTimer.start() }
    }

    Timer {
        id: restartTimer
        interval: 2000
        onTriggered: {
            subscribeProc.running = true
            root._refresh()
        }
    }

    Component.onCompleted: root._refresh()
}
