import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"
import "../common"
import "../theme"

PanelWindow {
    id: osd

    anchors { top: true; right: true }
    implicitWidth: 300
    implicitHeight: 112
    color: "transparent"
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:osd-screenshot"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0
    mask: Region {}

    property bool shown: false
    property string imagePath: ""
    property bool captureFailed: false
    property string failureMessage: ""

    function show() {
        osd.visible = true
        osd.shown = true
        displayTimer.restart()
    }

    Timer {
        id: displayTimer
        interval: 4000
        running: !cardHover.hovered
        onTriggered: osd.shown = false
    }

    Timer {
        id: hideTimer
        interval: Theme.animPanel
        onTriggered: if (!osd.shown) osd.visible = false
    }

    onShownChanged: if (!shown) hideTimer.restart()

    HoverHandler { id: cardHover }

    // Three ways to choose what gets captured, one path afterwards: every
    // mode saves to the same folder, copies to the clipboard, prints the
    // path for the handler below, and so lands the same thumbnail and the
    // same history row. Region is what the Print key has always used;
    // window and screen came in with the Conf menu's Trigger branch
    // (menu/ConfMenu.qml) and are reachable over IPC too.
    //
    // Both geometry lookups ask hyprctl for the numbers separately and
    // reassemble them in the shell rather than having jq interpolate the
    // "X,Y WxH" string: jq's \(...) syntax inside a nested double-quoted
    // command substitution is three levels of escaping deep, and this is
    // the same information.
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
            return 'sel="$(slurp)"; ' +
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
            if (captureProc._collected) osd._report()
        }
    }

    Connections {
        target: captureStdout
        function onStreamFinished() {
            captureProc._collected = true
            if (captureProc._exited) osd._report()
        }
    }

    function _report() {
        if (captureProc._lastExitCode === 3) return   // cancelled out of slurp

        const path = captureStdout.text.trim()
        if (captureProc._lastExitCode === 0 && path.length > 0) {
            osd.imagePath = path
            osd.captureFailed = false
            osd.show()
            Notifications.addManual("Screenshot captured",
                "Saved and copied to clipboard", "normal", "Screenshot", path)
        } else {
            osd.captureFailed = true
            osd.failureMessage = captureProc._lastExitCode === 4
                ? (captureProc.mode === "window"
                    ? "No focused window to capture"
                    : "No focused monitor to capture")
                : "Screenshot failed — check that grim, slurp and jq are installed"
            osd.show()
            Notifications.addManual("Screenshot Failed",
                osd.failureMessage, "critical", "Screenshot")
        }
    }

    function capture(mode) {
        captureProc.mode = mode || "region"
        captureProc._exited = false
        captureProc._collected = false
        captureProc.running = false
        captureProc.running = true
    }

    Connections {
        target: Panels
        function onCaptureRequested(mode) { osd.capture(mode) }
    }

    Process { id: openProc }
    function openImage() {
        if (osd.imagePath === "") return
        openProc.command = ["xdg-open", osd.imagePath]
        openProc.running = false
        openProc.running = true
    }

    Rectangle {
        id: box
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: osd.shown ? 12 : 0
        anchors.topMargin: osd.shown ? 12 : -height

        width: 300
        implicitHeight: content.implicitHeight + 20
        radius: Theme.radius
        // Opaque, not panelGlass (user request 2026-09-11). Only
        // "quickshell:bar" gets compositor blur — and blur is switched off
        // outright in hypr/modules/decorations.lua — so alpha here was
        // never frosted glass, just the desktop showing through the
        // thumbnail and its caption. wallpaper/WallpaperPopup.qml made the
        // same change for the same reason; this popup stacks in the same
        // top-right corner as that one and as the notification cards,
        // which have always been opaque, so it was the last surface up
        // there still see-through.
        color: Appearance.surface
        border.color: Appearance.border
        border.width: 1
        opacity: osd.shown ? 1 : 0

        layer.enabled: true
        layer.effect: PopupShadow {}
        Behavior on anchors.topMargin {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingDecel }
        }
        Behavior on opacity { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard } }

        MouseArea {
            anchors.fill: parent
            cursorShape: osd.captureFailed ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: if (!osd.captureFailed) osd.openImage()
        }

        RowLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Theme.space2
            spacing: Theme.space2

            Rectangle {
                visible: !osd.captureFailed
                Layout.preferredWidth: 72
                Layout.preferredHeight: 72
                radius: Theme.radius
                color: Appearance.surfaceAlt
                clip: true

                Image {
                    anchors.fill: parent
                    source: osd.imagePath !== "" ? ("file://" + osd.imagePath) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            Text {
                visible: osd.captureFailed
                text: "\uf071"
                color: Appearance.red
                font.pixelSize: 22
                font.family: Theme.font
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2

                    Text {
                        text: osd.captureFailed ? "Screenshot Failed" : "Screenshot Captured"
                        color: Appearance.fgStrong
                        font.bold: true
                        font.pixelSize: Theme.fontNormal
                        font.family: Theme.font
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "\uf00d"
                        color: Appearance.fgDim
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: osd.shown = false
                        }
                    }
                }

                Text {
                    text: osd.captureFailed ? osd.failureMessage : "Saved and copied to clipboard"
                    color: Appearance.fgMuted
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
    }

    // Unlike the LazyLoader-wrapped windows whose IPC moved to
    // services/Panels.qml, this popup is built eagerly in shell.qml, so
    // its own handler is reachable from the first press of a shell run —
    // which is what hypr/modules/binds/media.lua's Print bind relies on.
    // The window and screen modes the Conf menu added live here too,
    // rather than under a second target for the same feature.
    IpcHandler {
        target: "screenshot"
        function capture(): void { osd.capture("region") }
        function window(): void { osd.capture("window") }
        function screen(): void { osd.capture("screen") }
    }
}
