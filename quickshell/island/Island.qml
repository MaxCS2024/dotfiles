import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// The island: one pill at the top centre of the focused monitor that
// morphs between idle, compact, transient and expanded (AGENTS.md,
// Visual design). It only reads ActivityQueue; what it draws comes from
// there.
PanelWindow {
    id: root

    screen: focusedScreen()

    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name
        for (const s of Quickshell.screens)
            if (s.name === name)
                return s
        return Quickshell.screens[0]
    }

    anchors.top: true
    WlrLayershell.namespace: "quickshell:island"
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: Config.reserveSpace ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: Config.topMargin + Config.compactHeight
    color: "transparent"

    // Room for the largest state plus the spring's overshoot. Only the
    // pill takes input; the rest of the window lets clicks through.
    implicitWidth: Config.expandedWidth + 48
    implicitHeight: Config.topMargin + Config.expandedHeight + 24
    mask: Region { item: pill; radius: pill.radius }

    // ── State ──
    property bool expanded: false

    readonly property var transientActivity: ActivityQueue.shownTransient
    readonly property var persistentActivity: ActivityQueue.topPersistent

    readonly property string islandState: expanded ? "expanded"
        : transientActivity ? "transient"
        : persistentActivity ? "compact"
        : "idle"
    readonly property var activity: islandState === "transient" ? transientActivity
        : islandState === "idle" ? null
        : persistentActivity

    // Transients wait while the island is open, so the controls under the
    // pointer don't swap out.
    Binding {
        target: ActivityQueue
        property: "holdTransients"
        value: root.expanded
    }

    // Nothing left to show expanded: close.
    onPersistentActivityChanged: if (!persistentActivity) expanded = false

    // ── Content swap ──
    // The size follows the state at once; the content fades out, swaps,
    // and fades back in while the pill is still moving. `shownKey` names
    // what is drawn, so an update to the same activity (a new progress)
    // changes the content in place without a fade.
    readonly property string targetKey: islandState + ":" + (activity?.key ?? "")
    property string shownKey: ""
    property string shownState: "idle"
    property var shownActivity: null

    Component.onCompleted: {
        shownKey = targetKey
        shownState = islandState
        shownActivity = activity
    }

    onTargetKeyChanged: swap.restart()
    onActivityChanged: if (targetKey === shownKey) shownActivity = activity

    SequentialAnimation {
        id: swap
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: 80 }
        ScriptAction {
            script: {
                root.shownKey = root.targetKey
                root.shownState = root.islandState
                root.shownActivity = root.activity
            }
        }
        NumberAnimation { target: content; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
    }

    // ── Size per state ──
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Measures the content the pill is heading for, before it is drawn.
    ActivityFace {
        id: measure
        visible: false
        activity: root.activity
        mode: root.islandState === "idle" ? "compact" : root.islandState
    }

    function fit(w) {
        return Math.max(Config.minWidth, Math.min(Config.maxWidth, w + Config.padX * 2))
    }

    readonly property int targetWidth: {
        switch (islandState) {
        case "idle":
            return Config.idle === "notch" ? Config.notchWidth : clockText.implicitWidth + Config.padX * 2
        case "compact":
        case "transient":
            return fit(measure.implicitWidth)
        default:
            return Config.expandedWidth
        }
    }
    readonly property int targetHeight: {
        switch (islandState) {
        case "idle":
            return Config.idle === "notch" ? Config.notchHeight : Config.idleHeight
        case "compact":
            return Config.compactHeight
        case "transient":
            return Config.transientHeight
        default:
            return Config.expandedHeight
        }
    }

    // ── The pill ──
    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: Config.topMargin
        width: root.targetWidth
        height: root.targetHeight
        radius: Math.min(height / 2, Config.expandedRadius)
        color: Config.background
        clip: true

        Behavior on width { SpringAnimation { spring: 4; damping: 0.36; epsilon: 0.25 } }
        Behavior on height { SpringAnimation { spring: 4; damping: 0.36; epsilon: 0.25 } }

        Item {
            id: content
            anchors.fill: parent

            Text {
                id: clockText
                anchors.centerIn: parent
                visible: root.shownState === "idle" && Config.idle === "clock"
                text: Qt.formatTime(clock.date, Config.clockFormat)
                color: Config.foreground
                font.family: Config.font
                font.weight: Font.Bold
                font.pixelSize: Config.fontSize
            }

            ActivityFace {
                visible: root.shownState !== "idle"
                anchors.fill: parent
                activity: root.shownActivity
                mode: root.shownState
            }
        }

        // ── Pointer ──
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true

            onClicked: {
                if (Config.expandOn === "click" && root.persistentActivity)
                    root.expanded = !root.expanded
            }
            onContainsMouseChanged: {
                if (containsMouse) {
                    collapseTimer.stop()
                    if (Config.expandOn === "hover")
                        hoverTimer.restart()
                } else {
                    hoverTimer.stop()
                    if (root.expanded)
                        collapseTimer.restart()
                }
            }
        }
    }

    Timer {
        id: hoverTimer
        interval: Config.hoverDelay
        onTriggered: if (root.persistentActivity) root.expanded = true
    }

    Timer {
        id: collapseTimer
        interval: Config.collapseDelay
        onTriggered: root.expanded = false
    }

    // ── View tests ──
    // Opens and closes the island without a pointer, for test-queue.sh.
    IpcHandler {
        target: "view"

        function expand(): void {
            if (root.persistentActivity)
                root.expanded = true
        }
        function collapse(): void {
            root.expanded = false
        }
        function current(): string {
            return root.islandState
        }
    }
}
