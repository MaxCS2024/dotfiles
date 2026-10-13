import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// The island: one pill at the top centre of the focused monitor that
// morphs between idle, compact, transient and expanded (AGENTS.md,
// Visual design), and the privacy dots beside it. It only reads
// ActivityQueue and Privacy; what it draws comes from there.
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
    // Overlay, so the privacy dots stay over fullscreen windows; the pill
    // hides itself there instead (see Fullscreen).
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: Config.reserveSpace ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: Config.topMargin + Config.compactHeight
    color: "transparent"

    // Room for the largest state, the dots beside it and the spring's
    // overshoot. Only the pill and the dots take input; the rest of the
    // window lets clicks through. Hidden over fullscreen, the pill leaves
    // the mask and only the dots remain.
    implicitWidth: Config.expandedWidth + 2 * 72
    implicitHeight: Config.topMargin + Config.expandedHeight + 24
    mask: Region {
        Region { item: root.pillHidden ? null : pill; radius: pill.radius }
        Region { item: dots }
    }

    // ── Fullscreen ──
    // A fullscreen window on the focused workspace hides the pill, unless
    // a privacy announcement is up; the dots stay. `fullscreenTest`
    // overrides it for testing.
    property var fullscreenTest: null
    readonly property bool fullscreen: fullscreenTest ?? (Hyprland.focusedWorkspace?.hasFullscreen ?? false)
    readonly property bool pillHidden: fullscreen && !Privacy.announcement
    onPillHiddenChanged: if (pillHidden) expanded = false

    // ── State ──
    property bool expanded: false

    readonly property var transientActivity: ActivityQueue.shownTransient
    readonly property var persistentActivity: ActivityQueue.topPersistent

    // A privacy announcement comes before everything, the expanded state
    // included; the island goes back to that state after it. The generic
    // face, with the device's glyph in white: the coloured dot beside the
    // pill already marks it.
    readonly property var privacyActivity: Privacy.announcement ? {
        key: "privacy:" + Privacy.announcement.serial,
        face: "",
        icon: Privacy.glyph(Privacy.announcement.kind),
        label: Privacy.announcement.text,
        progress: -1,
    } : null

    readonly property string islandState: privacyActivity ? "privacy"
        : expanded ? "expanded"
        : transientActivity ? "transient"
        : persistentActivity ? "compact"
        : "idle"
    readonly property var activity: islandState === "privacy" ? privacyActivity
        : islandState === "transient" ? transientActivity
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
    // changes the content in place without a fade. A change of face (the
    // OSD's level handing over to the mic notice) fades like a new one.
    readonly property string targetKey: islandState + ":" + (activity?.key ?? "") + ":" + (activity?.face ?? "")
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
    Face {
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
        case "privacy":
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
        case "privacy":
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

        opacity: root.pillHidden ? 0 : 1
        scale: root.pillHidden ? 0.8 : 1
        transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Behavior on width { SpringAnimation { spring: 4; damping: 0.36; epsilon: 0.25 } }
        Behavior on height { SpringAnimation { spring: 4; damping: 0.36; epsilon: 0.25 } }

        // ── Pointer ──
        // Under the content, so a face's own buttons (the media controls)
        // take their clicks first; a click anywhere else opens or closes.
        // Hover comes from a HoverHandler, which buttons don't hide.
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (Config.expandOn === "click" && root.persistentActivity && root.islandState !== "privacy")
                    root.expanded = !root.expanded
            }
        }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) {
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

            Face {
                visible: root.shownState !== "idle"
                anchors.fill: parent
                activity: root.shownActivity
                mode: root.shownState
            }
        }
    }

    // ── Privacy dots ──
    // One per device in use (microphone, camera, screen), in that order,
    // just right of the pill, centred on its first line, so they move
    // with it in every state. Never hidden: not by fullscreen, not by the
    // expanded state. A click names every app on that device.
    Row {
        id: dots
        x: pill.x + pill.width + 4
        y: pill.y + (Math.min(pill.height, Config.compactHeight) - height) / 2

        Repeater {
            model: Privacy.kinds

            Item {
                id: dot
                required property string modelData
                readonly property bool active: Privacy.users[modelData].length > 0

                visible: active
                width: 16
                height: 16

                Rectangle {
                    id: mark
                    anchors.centerIn: parent
                    width: Config.dotSize
                    height: Config.dotSize
                    radius: width / 2
                    color: Config.privacyColor(dot.modelData)
                }

                onActiveChanged: if (active) appear.restart()
                NumberAnimation {
                    id: appear
                    target: mark
                    property: "scale"
                    from: 0
                    to: 1
                    duration: 160
                    easing.type: Easing.OutBack
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Privacy.list(dot.modelData)
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
            return root.islandState + (root.pillHidden ? " (hidden)" : "")
        }
        // Pretends a fullscreen window is (or isn't) focused.
        function fullscreen(on: bool): void {
            root.fullscreenTest = on
        }
        // Back to Hyprland's word on it.
        function fullscreenReal(): void {
            root.fullscreenTest = null
        }
    }
}
