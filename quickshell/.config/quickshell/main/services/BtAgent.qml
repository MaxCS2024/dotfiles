pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The Bluetooth pairing agent: `relay bluetooth agent`
// (relay/lib/bluetooth-agent.py) registered with BlueZ, its questions shown
// by network/BluetoothPrompt.qml. Without it BlueZ pairs only devices that
// need no code — see the protocol at the top of the Python file.
//
// Always running while the shell is: a phone can ask to pair with the
// panel closed, and the question has to reach somebody. Exit 127 (relay,
// python-dbus or python-gobject missing) is the end of it and pairing falls
// back to "Just Works"; anything else (bluetoothd restarting) is retried,
// as services/Earbuds.qml retries its watcher.
Singleton {
    id: root

    // Open questions, oldest first, each the agent's prompt line as it
    // arrived: { id, kind, address, name, code?, entered? }. The prompt
    // shows the first; a second only arrives if two devices ask at once.
    property var prompts: []
    readonly property var current: root.prompts.length > 0 ? root.prompts[0] : null

    readonly property bool running: agent.running

    // accept: true/false; value: the typed PIN or passkey, else unused.
    // The agent closes the prompt itself once the answer is sent.
    function respond(id, accept, value) {
        if (!agent.running) return
        agent.write(JSON.stringify({ id: id, accept: accept, value: value || "" }) + "\n")
    }

    function _apply(msg) {
        if (msg.event === "prompt") {
            // Same id again is a keyboard reporting keys typed so far;
            // replaced in place so the prompt doesn't jump.
            const rest = root.prompts.filter(p => p.id !== msg.id)
            const at = root.prompts.findIndex(p => p.id === msg.id)
            if (at < 0) root.prompts = rest.concat([msg])
            else { rest.splice(at, 0, msg); root.prompts = rest }
        } else if (msg.event === "close") {
            root.prompts = root.prompts.filter(p => p.id !== msg.id)
        }
    }

    Process {
        id: agent
        running: true
        stdinEnabled: true
        command: ["sh", "-c", "command -v relay >/dev/null || exit 127; exec relay bluetooth agent"]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    root._apply(JSON.parse(line))
                } catch (e) {
                    console.warn("BtAgent: unreadable line from relay bluetooth agent:", line)
                }
            }
        }
        onExited: (exitCode) => {
            root.prompts = []
            if (exitCode !== 127) retry.start()
        }
    }

    Timer {
        id: retry
        interval: 5000
        onTriggered: agent.running = true
    }
}
