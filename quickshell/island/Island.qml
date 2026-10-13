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

    // Room for the largest state, the split's circle and the dots beside
    // it, and a morph's overshoot. Only the pill, the circle and the dots
    // take input; the rest of the window lets clicks through. Hidden over
    // fullscreen, the pill and the circle leave the mask and only the dots
    // remain.
    implicitWidth: Config.expandedWidth + 2 * (Config.splitGap + Config.compactHeight + 4 + 48 + 8)
    implicitHeight: Config.topMargin + Config.expandedHeight + 24
    mask: Region {
        Region { item: root.pillHidden ? null : pill; radius: pill.radius }
        Region { item: root.splitReach > 0 && !root.pillHidden ? circle : null; radius: circle.radius }
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
    // Opened from the split's circle: that activity, not the top one.
    property string expandTarget: ""
    onExpandedChanged: if (!expanded) expandTarget = ""

    readonly property var transientActivity: ActivityQueue.shownTransient
    readonly property var persistentActivity: ActivityQueue.topPersistent

    // A privacy announcement comes before everything, the expanded state
    // included; the island goes back to that state after it. The generic
    // face, with the device's glyph in white: the coloured dot beside the
    // pill already marks it.
    readonly property var privacyActivity: Privacy.announcement ? {
        key: "privacy:" + Privacy.announcement.serial,
        profile: "privacy",
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
        : islandState === "expanded" && expandTarget
            ? (ActivityQueue.activities.find(a => a.key === root.expandTarget) ?? persistentActivity)
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
    // The content fades out, swaps, and fades back in while the pill
    // morphs, in the same time. `shownKey` names what is drawn, so an
    // update to the same activity (a new progress) changes the content in
    // place without a fade. A change of face (the OSD's level handing
    // over to the mic notice) fades like a new one.
    readonly property string targetKey: islandState + ":" + (activity?.key ?? "") + ":" + (activity?.face ?? "")
    property string shownKey: ""
    property string shownState: "idle"
    property var shownActivity: null

    Component.onCompleted: {
        shownKey = targetKey
        shownState = islandState
        shownActivity = activity
        lastState = islandState
        lastActivity = activity
        pillWidth = targetWidth
        pillHeight = targetHeight
        sized = true
    }

    onTargetKeyChanged: {
        const t = timing()
        lastState = islandState
        lastActivity = activity
        morphTime = t.time
        morphOvershoot = t.overshoot
        keyed = true
        swap.restart()
        Qt.callLater(syncSize)
    }
    onActivityChanged: if (targetKey === shownKey) shownActivity = activity

    SequentialAnimation {
        id: swap
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: Math.round(root.morphTime * 0.3) }
        ScriptAction {
            script: {
                root.shownKey = root.targetKey
                root.shownState = root.islandState
                root.shownActivity = root.activity
            }
        }
        NumberAnimation {
            target: content
            property: "opacity"
            to: 1
            duration: root.morphTime - Math.round(root.morphTime * 0.3)
            easing.type: Easing.OutCubic
        }
    }

    // ── Motion ──
    // How long the pill takes, from the interruption profile of whatever
    // arrives or leaves (AGENTS.md, Interruption and motion): an arrival
    // moves at its enter time, with one slight overshoot if it is a high
    // interruption; falling back after one leaves moves at its (shorter)
    // exit time. Opening and closing the expanded state have their own,
    // and so does the pill fitting new content in place.
    property string lastState: "idle"
    property var lastActivity: null
    property int morphTime: Config.resizeTime
    property bool morphOvershoot: false
    // The pill's size, set once per event-loop turn (syncSize), after
    // morphTime: a Behavior reads its duration when it starts.
    property real pillWidth: 0
    property real pillHeight: 0
    property bool sized: false
    property bool keyed: false

    onTargetWidthChanged: Qt.callLater(syncSize)
    onTargetHeightChanged: Qt.callLater(syncSize)

    function syncSize() {
        if (!keyed) {
            morphTime = Config.resizeTime
            morphOvershoot = false
        }
        keyed = false
        pillWidth = targetWidth
        pillHeight = targetHeight
    }

    // Still in the queue (or still the announcement): outranked, not gone.
    function present(a) {
        return a.profile === "privacy" ? privacyActivity?.key === a.key : ActivityQueue.find(a.key) !== null
    }

    function timing() {
        const from = lastState
        const to = islandState
        const enter = a => ({ time: Config.profile(a.profile).enter, overshoot: Config.profile(a.profile).overshoot })
        const exit = a => ({ time: Config.profile(a.profile).exit, overshoot: false })
        if (from === "privacy" && lastActivity)
            return to === "privacy" ? enter(activity) : exit(lastActivity)
        if (to === "expanded" && from !== "expanded")
            return { time: Config.expandTime, overshoot: false }
        if (from === "expanded" && to !== "privacy")
            return { time: Config.collapseTime, overshoot: false }
        // Arriving: a transient or announcement, or one that outranks
        // what was there.
        if (activity && (to === "transient" || to === "privacy" || !lastActivity || present(lastActivity)))
            return enter(activity)
        if (lastActivity)
            return exit(lastActivity)
        return { time: Config.resizeTime, overshoot: false }
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
            // Taller for a face that needs it (a notification's card).
            return Math.max(Config.transientHeight, measure.implicitHeight)
        default:
            // Each face's expanded height (media and the generic one:
            // Config.expandedHeight).
            return measure.implicitHeight
        }
    }

    // ── Split ──
    // Two persistent activities at once (compact only): the second shows
    // in a small circle beside the pill, the brief's "detached" shape; a
    // third waits. Its circle grows out from under the pill's right end
    // at the activity's enter time and goes back at its exit time;
    // `splitReach` is how far it (and the gap before it) reaches out,
    // and the dots ride on it. A click opens that activity expanded; a
    // right click dismisses it. Declared before the pill, which covers it
    // while it is tucked in.
    readonly property var secondActivity: islandState === "compact" ? (ActivityQueue.persistents[1] ?? null) : null
    readonly property bool split: secondActivity !== null && !pillHidden
    readonly property real splitFull: Config.splitGap + Config.compactHeight
    property real splitReach: 0
    property var shownSecond: null
    readonly property string secondKey: secondActivity ? secondActivity.key + ":" + secondActivity.face : ""

    onSplitChanged: {
        const a = split ? secondActivity : shownSecond
        splitAnim.stop()
        splitAnim.to = split ? splitFull : 0
        splitAnim.duration = split ? Config.profile(a?.profile).enter : Config.profile(a?.profile).exit
        splitAnim.restart()
    }

    // The circle's content follows the second activity, crossfading when
    // another takes its place; it stays through the circle going away.
    onSecondKeyChanged: {
        if (!secondActivity)
            return
        if (shownSecond && splitReach > 0 && shownSecond.key !== secondActivity.key)
            secondSwap.restart()
        else
            shownSecond = secondActivity
    }
    onSecondActivityChanged: if (secondActivity && shownSecond?.key === secondActivity.key) shownSecond = secondActivity

    NumberAnimation {
        id: splitAnim
        target: root
        property: "splitReach"
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: secondSwap
        NumberAnimation { target: secondFace; property: "opacity"; to: 0; duration: 60 }
        ScriptAction { script: root.shownSecond = root.secondActivity }
        NumberAnimation { target: secondFace; property: "opacity"; to: 1; duration: 120; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: circle
        // Tucked under the pill's end at 0, 8px clear of it when out.
        x: pill.x + pill.width + root.splitReach - width
        y: pill.y + (Math.min(pill.height, Config.compactHeight) - height) / 2
        width: Config.compactHeight
        height: width
        radius: width / 2
        color: Config.background
        visible: root.splitReach > 0
        scale: 0.5 + 0.5 * root.splitReach / root.splitFull
        opacity: root.pillHidden ? 0 : 1

        Face {
            id: secondFace
            anchors.fill: parent
            activity: root.shownSecond
            mode: "minimal"
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (!root.shownSecond)
                    return
                if (mouse.button === Qt.RightButton)
                    ActivityQueue.dismiss(root.shownSecond.key)
                else {
                    root.expandTarget = root.shownSecond.key
                    root.expanded = true
                }
            }
        }
    }

    // ── The pill ──
    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: Config.topMargin
        width: root.pillWidth
        height: root.pillHeight
        radius: Math.min(height / 2, Config.expandedRadius)
        color: Config.background
        clip: true

        opacity: root.pillHidden ? 0 : 1
        scale: root.pillHidden ? 0.8 : 1
        transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Behavior on width {
            enabled: root.sized
            NumberAnimation {
                duration: root.morphTime
                easing.type: root.morphOvershoot ? Easing.OutBack : Easing.OutCubic
                easing.overshoot: 0.8
            }
        }
        Behavior on height {
            enabled: root.sized
            NumberAnimation {
                duration: root.morphTime
                easing.type: root.morphOvershoot ? Easing.OutBack : Easing.OutCubic
                easing.overshoot: 0.8
            }
        }

        // ── Pointer ──
        // Under the content, so a face's own buttons (the media controls)
        // take their clicks first; a left click anywhere else opens or
        // closes. A right click dismisses what is showing: an announcement
        // makes way for the next (its dot stays), any other activity
        // leaves the island. A middle click turns the notification hold
        // on or off. Hover comes from a HoverHandler, which buttons don't
        // hide; it also stops a transient's time while the pointer rests
        // on it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    root.dismissShown()
                else if (mouse.button === Qt.MiddleButton)
                    Notifications.setHolding(!Notifications.holding)
                else if (Config.expandOn === "click" && root.persistentActivity && root.islandState !== "privacy")
                    root.expanded = !root.expanded
            }
        }

        HoverHandler {
            id: pillHover
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
        x: pill.x + pill.width + root.splitReach + 4
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

    Binding {
        target: ActivityQueue
        property: "paused"
        value: pillHover.hovered && root.islandState === "transient"
    }

    function dismissShown() {
        if (islandState === "privacy")
            Privacy.dismiss()
        else if (activity) {
            expanded = false
            ActivityQueue.dismiss(activity.key)
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
        // What a click and a right click on the split's circle do.
        function expandSecond(): void {
            if (root.shownSecond && root.splitReach > 0) {
                root.expandTarget = root.shownSecond.key
                root.expanded = true
            }
        }
        function dismissSecond(): void {
            if (root.shownSecond && root.splitReach > 0)
                ActivityQueue.dismiss(root.shownSecond.key)
        }
        function second(): string {
            return root.split ? root.secondActivity.key : ""
        }
        // What a right click on the pill does.
        function dismiss(): void {
            root.dismissShown()
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
