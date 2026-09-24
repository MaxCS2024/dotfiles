pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// What the voxtype dictation daemon is doing: "idle", "recording",
// "transcribing", or "stopped" when the daemon isn't running. SUPER+V
// (hypr/modules/binds/apps.lua) is what starts and stops a recording;
// osd/VoxtypeOsd.qml is what shows it.
//
// `voxtype status --follow` prints one state per line whenever it
// changes, and it outlives the daemon: stopping the systemd unit prints
// "stopped", starting it again prints "idle" (checked 2026-09-24 against
// voxtype 1.1.0). So one process for the life of the shell covers
// everything, with no polling of $XDG_RUNTIME_DIR/voxtype/state.
//
// Exit 127 from the wrapper means voxtype isn't installed, and that is
// the end of it: retrying would put a failed spawn in the log every few
// seconds on a machine that doesn't use dictation. Any other exit
// (voxtype upgraded under it, killed) is retried.
Singleton {
    id: root

    property string state: "stopped"
    readonly property bool recording: root.state === "recording"
    readonly property bool transcribing: root.state === "transcribing"
    readonly property bool busy: root.recording || root.transcribing

    function toggle() { Quickshell.execDetached(["voxtype", "record", "toggle"]) }
    function cancel() { Quickshell.execDetached(["voxtype", "record", "cancel"]) }

    Process {
        id: follow
        running: true
        command: ["sh", "-c", "command -v voxtype >/dev/null || exit 127; exec voxtype status --follow"]
        stdout: SplitParser {
            onRead: (line) => root.state = line.trim()
        }
        onExited: (exitCode) => {
            root.state = "stopped"
            if (exitCode !== 127) retry.start()
        }
    }

    Timer {
        id: retry
        interval: 5000
        onTriggered: follow.running = true
    }
}
