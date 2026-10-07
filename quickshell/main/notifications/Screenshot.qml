// Screen capture for the Print key, the Conf menu's Capture rows and the
// "screenshot" IPC target.
//
// No window of its own. The result goes out as an ordinary notification
// card (Notifications.post), like every other shell event; this used to be
// ScreenshotPopup.qml, a separate thumbnail popup in the same corner that
// looked like nothing else up there. Clicking the card opens the image,
// which is what clicking the thumbnail did.
import Quickshell
import Quickshell.Io
import QtQuick
import "../services"

Scope {
    id: root

    // Three ways to choose what gets captured, one path afterwards: every
    // mode saves to the same folder, copies to the clipboard, prints the
    // path for the handler below, and so lands the same card and the
    // same history row. Region is what the Print key has always used;
    // window and screen came in with the Conf menu's Capture branch
    // (menu/ConfMenu.qml) and are reachable over IPC too.
    //
    // Both geometry lookups ask hyprctl for the numbers separately and
    // reassemble them in the shell rather than having jq interpolate the
    // "X,Y WxH" string: jq's \(...) syntax inside a nested double-quoted
    // command substitution is three levels of escaping deep, and this is
    // the same information.
    //
    // slurp gets /dev/null for stdin. Given a pipe, it reads predefined
    // boxes from it and draws nothing until the pipe closes, and the one
    // Quickshell hands a Process stays open: slurp sat there invisible
    // and every later press found a capture already running.
    //
    // Exit 3 means "the user cancelled" (Escape out of slurp) and is
    // deliberately silent; exit 4 means the compositor had nothing to
    // point at — no focused window, no focused monitor — and reports.
    Process {
        id: captureProc

        // "region" | "window" | "screen"
        property string mode: "region"

        readonly property string _head:
            'dir="$HOME/Pictures/Screenshots"; ' +
            'mkdir -p "$dir"; ' +
            'f="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"; '
        readonly property string _tail:
            ' && wl-copy --type image/png < "$f" && printf "%s" "$f"'

        // Only the grab itself varies by mode; the folder, the filename,
        // the clipboard copy and the path on stdout are common to all
        // three.
        readonly property string _grab: {
            if (captureProc.mode === "window")
                return 'set -- $(hyprctl activewindow -j | jq -r ".at[0],.at[1],.size[0],.size[1]"); ' +
                    '[ $# -eq 4 ] || exit 4; ' +
                    'case "$1" in null) exit 4;; esac; ' +
                    'grim -g "$1,$2 $3x$4" "$f"'
            if (captureProc.mode === "screen")
                return 'out="$(hyprctl monitors -j | jq -r ".[] | select(.focused) | .name")"; ' +
                    '[ -n "$out" ] || exit 4; ' +
                    'grim -o "$out" "$f"'
            return 'sel="$(slurp </dev/null)"; ' +
                'if [ -z "$sel" ]; then exit 3; fi; ' +
                'grim -g "$sel" "$f"'
        }

        readonly property string _script: captureProc._head + captureProc._grab + captureProc._tail

        command: ["sh", "-c", captureProc._script]

        stdout: StdioCollector { id: captureStdout }

        property int _lastExitCode: -1

        // "The capture is over" arrives in two halves that don't agree on
        // an order: onExited carries the status, the collector's
        // streamFinished carries the path. The stream can finish first —
        // reliably so on the first run of a shell instance — and reading
        // the status there used to report a perfectly good screenshot as
        // failed, because _lastExitCode was still its initial -1. So
        // whichever half lands second is the one that reports.
        property bool _exited: false
        property bool _collected: false

        onExited: (exitCode, exitStatus) => {
            captureProc._lastExitCode = exitCode
            captureProc._exited = true
            if (captureProc._collected) root._report()
        }
    }

    Connections {
        target: captureStdout
        function onStreamFinished() {
            captureProc._collected = true
            if (captureProc._exited) root._report()
        }
    }

    function _report() {
        if (captureProc._lastExitCode === 3) return   // cancelled out of slurp

        const path = captureStdout.text.trim()
        if (captureProc._lastExitCode === 0 && path.length > 0) {
            Notifications.post("Screenshot captured", "Saved and copied to clipboard",
                "normal", "Screenshot", "", ["xdg-open", path])
        } else if (captureProc._lastExitCode === 4) {
            Notifications.post("Couldn't take a screenshot",
                captureProc.mode === "window"
                    ? "No focused window to capture"
                    : "No focused monitor to capture",
                "critical", "Screenshot", "")
        } else {
            Notifications.post("Couldn't take a screenshot",
                "Check that grim, slurp and jq are installed",
                "critical", "Screenshot", "")
        }
    }

    // One capture at a time. Restarting the process mid-capture used to
    // kill the sh around slurp but not slurp itself, which stayed up
    // under the new one — a held Print key stacked an overlay per repeat.
    // Instead a press while a selection is open cancels it, whether it
    // is this one or SHIFT+Print's (hypr/modules/binds/media.lua): Print
    // again is as good as Escape, and nothing can wedge the next press.
    // pkill exits 0 when it closed a selection, and that press was the
    // cancel; only a press that found none (and no capture mid-grab)
    // starts one.
    Process {
        id: cancelProc
        property string pendingMode: "region"
        command: ["pkill", "-x", "slurp"]
        onExited: (exitCode) => {
            if (exitCode !== 0 && !captureProc.running) root._start(cancelProc.pendingMode)
        }
    }

    function capture(mode) {
        if (cancelProc.running) return
        cancelProc.pendingMode = mode || "region"
        cancelProc.running = true
    }

    function _start(mode) {
        captureProc.mode = mode
        captureProc._exited = false
        captureProc._collected = false
        captureProc.running = false
        captureProc.running = true
    }

    Connections {
        target: Panels
        function onCaptureRequested(mode) { root.capture(mode) }
    }

    // Unlike the LazyLoader-wrapped windows whose IPC moved to
    // services/Panels.qml, this is built eagerly in shell.qml, so its own
    // handler is reachable from the first press of a shell run — which is
    // what hypr/modules/binds/media.lua's Print bind relies on. The
    // window and screen modes the Conf menu added live here too, rather
    // than under a second target for the same feature.
    IpcHandler {
        target: "screenshot"
        function capture(): void { root.capture("region") }
        function window(): void { root.capture("window") }
        function screen(): void { root.capture("screen") }
    }
}
