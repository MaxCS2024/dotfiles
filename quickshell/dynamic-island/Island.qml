import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

// Shows the time. Three views sit side by side, song | time | today:
// dragging right moves one to the left (towards the song), dragging left
// one to the right (towards the date and battery). A workspace
// switch shows "Workspace N" over any of them for 1.5 seconds, and a
// volume or brightness change shows its percentage and a filling circle
// for as long. Plugging in the charger, or the battery running low,
// shows a battery notice for 3 seconds. A left click
// opens the full media player, a right click a small settings panel
// (whose network, Bluetooth and battery segments turn it into a page of
// their own), a middle click a power menu; a click on any of them, or anywhere
// else, closes it. It hides and shows with the main bar: the sides close in
// to an orb that fades out, and the reverse.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    anchors.top: true
    // 7, not 8: the same as the gap between the pill and the window
    // border below it, so the pill sits evenly in its strip.
    margins.top: 7
    // Windows stay below the collapsed pill: the window is 288px tall for
    // the panels to grow into, so only a strip is reserved. Hyprland adds
    // the margin to it and gaps_out (15) below that, so a window's border
    // starts 24 + 15 - 32 = 7px under the pill, whatever the margin is.
    // 32 here left too much room. An open panel still overlaps windows.
    // While main's bar is on screen it reserves the strip and the island
    // sits over its centre; reserving here too would stack the island
    // below the bar.
    exclusionMode: Controls.mainBarUp ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: 24
    color: "transparent"

    // Big enough for the pill to grow into; only the pill takes clicks.
    // A fixed size, so the window isn't resized every frame of the opening:
    // the largest panel, the wallpaper gallery, decides it.
    implicitWidth: Math.max(400, galleryWidth)
    implicitHeight: Math.max(288, galleryHeight)
    // The wallpaper gallery: exactly three whole images wide (the middle
    // one and one to each side, none cut off), and only as tall as its
    // row: images 12% of the screen's height, the middle one's 16px lift,
    // 16px padding.
    readonly property real galleryWidth: 3 * gallery.tileW + 2 * gallery.gap + 32
    readonly property real galleryTileHeight: Math.round(modelData.height * 0.12)
    readonly property real galleryHeight: galleryTileHeight + gallery.lift + 32
    mask: Region { item: pill }
    // Keyboard focus while the settings panel (or one of its pages) is
    // open, for the Wi-Fi page's password field. Set as the panel opens,
    // before the focus grab: changing it while the grab is on clears the
    // grab, which closes the island.
    // The wallpaper gallery takes it outright, so the arrows work without a
    // click first.
    WlrLayershell.keyboardFocus: phase === "collapsed" || panel === "player" || panel === "power"
        ? WlrKeyboardFocus.None
        : panel === "wallpaper" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    // Unmapped once the hide animation has run, so it takes no clicks.
    visible: !gone

    // Which expanded panel opens: "player", "settings" or "power", or the
    // settings panel's "wifi", "bluetooth" and "battery" pages. Set while collapsed,
    // or by switchTo() while open, which eases the size from one to the
    // other.
    property string panel: "player"
    readonly property real expandedWidth: panel === "power" ? 304
        : panel === "wallpaper" ? galleryWidth : 360
    property real expandedHeight: panel === "wallpaper" ? galleryHeight
        : panel === "settings" ? 156
        : panel === "power" ? 88
        : panel === "wifi" || panel === "bluetooth" ? 288
        : panel === "battery" ? 200 : 128
    Behavior on expandedHeight {
        enabled: root.phase === "open"
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    // "collapsed", "opening", "open" or "closing". The three animated
    // values below are what the open and close sequences step through.
    property string phase: "collapsed"
    property real compactOpacity: 1
    property real sizeProgress: 0
    property real panelOpacity: 0

    // Hiding with the main bar. `orbing` turns the width Behavior off for
    // the whole hide/show, so it can't fight shrinkProgress; it is set
    // before either animation starts and cleared only once the pill is
    // whole. shrinkProgress 0 is the pill, 1 nothing: the sides close in
    // to a circle and the circle keeps shrinking to a point.
    readonly property bool wanted: Controls.mainBarVisible
    property bool orbing: false
    property bool gone: false
    property real shrinkProgress: 0
    property real orbTextOpacity: 1

    onWantedChanged: wanted ? appear() : disappear()

    function disappear() {
        appearAnim.stop()
        // A panel closes first; closeAnim's onFinished comes back here.
        if (phase !== "collapsed") {
            close()
            return
        }
        orbing = true
        disappearAnim.start()
    }

    function appear() {
        disappearAnim.stop()
        gone = false
        appearAnim.start()
    }

    // The text fades as the pill shrinks away; accelerating, so it doesn't
    // linger as a dot.
    ParallelAnimation {
        id: disappearAnim
        NumberAnimation { target: root; property: "orbTextOpacity"; to: 0; duration: 80 }
        NumberAnimation { target: root; property: "shrinkProgress"; to: 1; duration: 220; easing.type: Easing.InCubic }
        onFinished: root.gone = true
    }

    // The reverse: it grows from a point to a circle and opens out to the
    // pill, and the text comes back into that.
    ParallelAnimation {
        id: appearAnim
        NumberAnimation { target: root; property: "shrinkProgress"; to: 0; duration: 260; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PauseAnimation { duration: 140 }
            NumberAnimation { target: root; property: "orbTextOpacity"; to: 1; duration: 120 }
        }
        onFinished: root.orbing = false
    }

    property bool showWorkspace: false
    // -1 song, 0 time, 1 today: the views' order from left to right.
    property int view: 0
    property int workspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0

    // Prefer whichever player is playing, else the first one with a title.
    readonly property var player: {
        const players = Mpris.players.values.filter(p =>
            p.playbackState !== MprisPlaybackState.Stopped || p.trackTitle !== "")
        return players.find(p => p.isPlaying) ?? players[0] ?? null
    }
    // With no player, the song view and the player say "Nothing playing"
    // rather than being blocked.
    readonly property int shownView: view

    function labelFor(v) {
        return v === -1 ? mediaLabel : v === 1 ? todayLabel : clockLabel
    }
    // The view a drag in `dir` (1 right, -1 left) brings in, or null at
    // either end.
    function viewTowards(dir) {
        const v = shownView - dir
        return v > 1 || v < -1 ? null : v
    }

    // Set by the drag handlers. release() turns widthTracksDrag off before
    // dragging, so the width animation is back on before the width changes.
    property bool dragging: false
    property bool widthTracksDrag: false

    // The view a drag is pulling in, shown beside the text being dragged.
    readonly property Item peek: {
        if (!dragging || dragArea.dx === 0)
            return null
        const v = viewTowards(dragArea.dx > 0 ? 1 : -1)
        return v === null ? null : labelFor(v)
    }
    readonly property real peekGap: 16

    // Named workspaces still read "Workspace N"; special ones (id < 1) are skipped.
    //
    // Two labels take turns. A switch slides whatever text is showing out
    // and the new name in beside it, like the drag views: to a higher
    // number they move left (the new name comes in from the right), to a
    // lower one they move right. That goes for the time, song and today
    // views as much as an earlier name. Only the OSD and battery faces,
    // an open panel and a drag still get the plain fade.
    property Text workspaceLabel: workspaceLabelA
    property int lastWorkspace: 0

    onWorkspaceIdChanged: {
        if (workspaceId < 1)
            return
        const name = "Workspace " + workspaceId
        const out = pill.shown
        const slides = phase === "collapsed" && !dragging
            && !slideOut.running && !slideIn.running
            && out !== osdFace && out !== batteryFace && out !== displayFace
            && out !== layoutFace
            && !(out === workspaceLabel && workspaceLabel.text === name)
        if (slides) {
            const inn = out === workspaceLabelA ? workspaceLabelB : workspaceLabelA
            const dir = workspaceId > lastWorkspace ? -1 : 1
            wsSlideOut.stop()
            wsSlideIn.stop()
            inn.text = name
            const distance = out.width / 2 + peekGap + inn.width / 2
            workspaceLabel = inn
            wsSlideOut.target = out
            wsSlideOut.from = out.shift
            wsSlideOut.to = dir * distance
            wsSlideOut.start()
            wsSlideIn.target = inn
            wsSlideIn.from = -dir * distance
            wsSlideIn.start()
        } else {
            workspaceLabel.text = name
            workspaceLabel.shift = 0
        }
        lastWorkspace = workspaceId
        // The newest flash wins.
        showOsd = false
        showBattery = false
        showDisplay = false
        showLayout = false
        showWorkspace = true
        hideTimer.restart()
    }

    NumberAnimation {
        id: wsSlideOut
        property: "shift"
        duration: 160
        easing.type: Easing.OutCubic
        onFinished: target.shift = 0
    }

    NumberAnimation {
        id: wsSlideIn
        property: "shift"
        to: 0
        duration: 160
        easing.type: Easing.OutCubic
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.showWorkspace = false
    }

    // The OSD face: a volume or brightness change, from anywhere, while
    // the island is collapsed. An open settings panel has its own sliders.
    property bool showOsd: false
    property string osdKind: "volume"
    property real osdValue: 0

    Connections {
        target: Controls
        function onChanged(kind, value) {
            if (root.phase !== "collapsed" || root.dragging)
                return
            root.osdKind = kind
            root.osdValue = value
            root.showWorkspace = false
            root.showBattery = false
            root.showDisplay = false
            root.showLayout = false
            root.showOsd = true
            osdTimer.restart()
        }
    }

    Timer {
        id: osdTimer
        interval: 1500
        onTriggered: root.showOsd = false
    }

    // The battery notice: "Charging" when the charger goes in, "Low
    // battery" below 20% and 10%. Nobody asked for it, so it stays twice
    // as long as the other flashes, 3 seconds, to be noticed.
    property bool showBattery: false
    property string batteryKind: "charging"

    Connections {
        target: Controls
        function onBatteryNotice(kind) {
            if (root.phase !== "collapsed" || root.dragging)
                return
            root.batteryKind = kind
            root.showWorkspace = false
            root.showOsd = false
            root.showDisplay = false
            root.showLayout = false
            root.showBattery = true
            batteryTimer.restart()
        }
    }

    Timer {
        id: batteryTimer
        interval: 3000
        onTriggered: root.showBattery = false
    }

    // The display notice: "Display connected – DELL U2720Q" when an
    // external screen is plugged in. 3 seconds, like the battery notice;
    // a click on it opens the settings window's Displays section.
    property bool showDisplay: false
    property string displayLabel: ""

    Connections {
        target: Displays
        function onConnected(label) {
            if (root.phase !== "collapsed" || root.dragging)
                return
            root.displayLabel = label
            root.showWorkspace = false
            root.showOsd = false
            root.showBattery = false
            root.showLayout = false
            root.showDisplay = true
            displayTimer.restart()
        }
    }

    Timer {
        id: displayTimer
        interval: 3000
        onTriggered: root.showDisplay = false
    }

    // The layout notice: "Layout – English (US)" when the layout
    // changes. 1.5 seconds, like the workspace name: the user did it.
    property bool showLayout: false
    property string layoutName: ""

    Connections {
        target: Controls
        function onLayoutNotice(name) {
            if (root.phase !== "collapsed" || root.dragging)
                return
            root.layoutName = name
            root.showWorkspace = false
            root.showOsd = false
            root.showBattery = false
            root.showDisplay = false
            root.showLayout = true
            layoutTimer.restart()
        }
    }

    Timer {
        id: layoutTimer
        interval: 1500
        onTriggered: root.showLayout = false
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Outside the pill so the drag reads the cursor against the screen,
    // and under it so the player's buttons get their clicks first.
    // The mask limits presses to the pill anyway.
    MouseArea {
        id: dragArea

        property real startX: 0
        property real pressX: 0
        property real dx: 0
        // Past 4px a press is a drag; short of it, a click.
        property bool moved: false
        // The press landed on the display notice: a click opens Displays.
        property bool onDisplayNotice: false

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: mouse => {
            pressX = mouse.x
            moved = false
            onDisplayNotice = root.showDisplay
            if (root.phase !== "collapsed" || mouse.button !== Qt.LeftButton)
                return
            // Grabbing the pill drops the workspace name straight away.
            hideTimer.stop()
            root.showWorkspace = false
            osdTimer.stop()
            root.showOsd = false
            batteryTimer.stop()
            root.showBattery = false
            displayTimer.stop()
            root.showDisplay = false
            layoutTimer.stop()
            root.showLayout = false
            // Catch the text mid-slide where it is; park the other one.
            slideOut.stop()
            slideIn.stop()
            for (const label of [clockLabel, mediaLabel, todayLabel])
                if (label !== pill.shown)
                    label.shift = 0
            dx = pill.shown.shift
            startX = mouse.x - dx
            root.widthTracksDrag = true
            root.dragging = true
        }
        onPositionChanged: mouse => {
            if (!root.dragging)
                return
            if (Math.abs(mouse.x - pressX) > 4)
                moved = true
            dx = mouse.x - startX
            pill.shown.shift = dx
            if (root.peek)
                root.peek.shift = root.besideShift(pill.shown, root.peek, dx > 0 ? 1 : -1)
        }
        onReleased: mouse => {
            if (root.phase === "open") {
                root.close()
            } else if (mouse.button === Qt.RightButton) {
                if (root.phase === "collapsed")
                    root.open("settings")
            } else if (mouse.button === Qt.MiddleButton) {
                if (root.phase === "collapsed")
                    root.open("power")
            } else if (root.dragging) {
                root.release(moved ? dx : 0)
                if (!moved && onDisplayNotice)
                    SettingsWindow.open("displays")
                else if (!moved)
                    root.open("player")
            }
        }
        onCanceled: if (root.dragging) root.release(0)
    }

    Rectangle {
        id: pill

        readonly property real padX: 32
        // The OSD face sits tighter to the ends than the text views.
        readonly property real shownPadX: shown === osdFace ? 24 : padX
        readonly property Item shown: root.showLayout ? layoutFace
            : root.showDisplay ? displayFace
            : root.showBattery ? batteryFace
            : root.showOsd ? osdFace
            : root.showWorkspace ? root.workspaceLabel
            : root.labelFor(root.shownView)

        anchors.horizontalCenter: parent.horizontalCenter
        // Mid-drag the width moves from the dragged text's towards the
        // incoming text's, in step with how far the drag has carried it.
        readonly property real dragProgress: root.peek
            ? Math.min(1, Math.abs(dragArea.dx)
                / (shown.width / 2 + root.peekGap + root.peek.width / 2))
            : 0
        readonly property real textWidth: root.peek
            ? shown.width + (root.peek.width - shown.width) * dragProgress
            : shown.width

        readonly property real fullWidth: textWidth + shownPadX * 2
            + (root.expandedWidth - textWidth - shownPadX * 2) * root.sizeProgress
        // Hiding: the width shrinks to nothing, and once it is less than the
        // height the height follows, so the pill becomes a circle that
        // shrinks to a point, centred where the pill was.
        width: fullWidth * (1 - root.shrinkProgress)
        readonly property real fullHeight: 32 + (root.expandedHeight - 32) * root.sizeProgress
        height: Math.min(fullHeight, width)
        y: Math.max(0, (32 - height) / 2)
        // Fully round as a pill, softer corners as the player.
        radius: Math.min(height / 2, 32)
        color: "black"

        // Off while dragging, so the width tracks the cursor without lag,
        // while the player opens or closes, which drives it itself, and
        // while hiding or showing with the main bar.
        Behavior on width {
            enabled: !root.widthTracksDrag && root.phase === "collapsed" && !root.orbing
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        // The labels slide inside this. Inset so sliding text is cut off
        // inside the black, never past the rounded ends.
        Item {
            id: track
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            clip: true
            opacity: root.compactOpacity * root.orbTextOpacity

            Text {
                id: clockLabel
                property real shift: 0
                anchors.centerIn: parent
                transform: Translate { x: clockLabel.shift }
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: "white"
                font.family: "JetBrainsMono Nerd Font"
                font.weight: Font.Bold
                font.pixelSize: 13
                opacity: pill.shown === clockLabel || root.peek === clockLabel ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            Text {
                id: mediaLabel
                property real shift: 0
                anchors.centerIn: parent
                transform: Translate { x: mediaLabel.shift }
                // Long titles are cut with "…" so the pill stays inside the window.
                width: Math.min(implicitWidth, root.implicitWidth - pill.padX * 2)
                elide: Text.ElideRight
                text: {
                    if (!root.player)
                        return "\u{f075a} Nothing playing"
                    const title = root.player.trackTitle || "Unknown"
                    const artist = root.player.trackArtist
                    // A music note in front.
                    // "Title – Artist", an en dash between.
                    return "\u{f075a} " + (artist ? title + " – " + artist : title)
                }
                color: "white"
                font.family: "JetBrainsMono Nerd Font"
                font.weight: Font.Bold
                font.pixelSize: 13
                opacity: pill.shown === mediaLabel || root.peek === mediaLabel ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            Text {
                id: todayLabel
                property real shift: 0
                anchors.centerIn: parent
                transform: Translate { x: todayLabel.shift }
                // "tors 8 okt – [battery] 46%". The battery is left out with
                // no battery. Rich text so the glyph can be 16px, to sit
                // level with the bold text.
                textFormat: Text.RichText
                text: {
                    const glyph = g => "<span style=\"font-size: 16px\">" + g + "</span>"
                    // Swedish short months end in a dot ("okt."); it goes.
                    const parts = [Qt.locale("sv_SE").toString(clock.date, "ddd d MMM").replace(/\./g, "")]
                    if (Controls.batteryPercent >= 0)
                        parts.push(glyph(Controls.batteryIcon) + " " + Math.round(Controls.batteryPercent) + "%")
                    return parts.join(" – ")
                }
                color: "white"
                font.family: "JetBrainsMono Nerd Font"
                font.weight: Font.Bold
                font.pixelSize: 13
                opacity: pill.shown === todayLabel || root.peek === todayLabel ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            // The OSD face: the speaker or sun icon and the percentage,
            // then 16px on a circle that fills clockwise from the top like
            // a pie, all white.
            Row {
                id: osdFace
                anchors.centerIn: parent
                spacing: 8
                opacity: pill.shown === osdFace ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }

                // Eases between readings, so a held key fills smoothly.
                property real value: root.osdValue
                Behavior on value { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.osdKind === "brightness" ? Controls.brightnessIcon : Controls.volumeIcon
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                }

                Text {
                    // As wide as "100%", so the circle stays put while the
                    // number changes.
                    width: osdWidest.width
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(root.osdValue * 100) + "%"
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.Bold
                    font.pixelSize: 13

                    TextMetrics {
                        id: osdWidest
                        text: "100%"
                        font.family: "JetBrainsMono Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: 13
                    }
                }

                Canvas {
                    id: pie
                    width: 16
                    height: 16
                    anchors.verticalCenter: parent.verticalCenter

                    property real value: osdFace.value
                    onValueChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        const r = width / 2
                        // A 3px ring, stroked on its centre line so its
                        // outer edge stays at the 16px circle.
                        const lw = 3
                        const ring = r - lw / 2
                        ctx.reset()
                        ctx.lineWidth = lw
                        // The empty ring, white at 20%.
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.2)
                        ctx.beginPath()
                        ctx.arc(r, r, ring, 0, 2 * Math.PI)
                        ctx.stroke()
                        // The filled arc, from 12 o'clock clockwise.
                        if (value > 0) {
                            ctx.strokeStyle = "white"
                            ctx.beginPath()
                            ctx.arc(r, r, ring, -Math.PI / 2, -Math.PI / 2 + value * 2 * Math.PI)
                            ctx.stroke()
                        }
                    }
                }
            }

            // The battery notice: the battery icon at 16px, then
            // "Charging – 46%" or "Low battery – 18%".
            Row {
                id: batteryFace
                anchors.centerIn: parent
                spacing: 8
                opacity: pill.shown === batteryFace ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Controls.batteryIcon
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.batteryKind === "low" ? "Low battery" : "Charging")
                        + " – " + Math.round(Controls.batteryPercent) + "%"
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.Bold
                    font.pixelSize: 13
                }
            }

            // The display notice: a monitor icon at 16px, then
            // "Display connected – DELL U2720Q".
            Row {
                id: displayFace
                anchors.centerIn: parent
                spacing: 8
                opacity: pill.shown === displayFace ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f0379}"
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Display connected – " + root.displayLabel
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.Bold
                    font.pixelSize: 13
                }
            }

            // The layout notice: a keyboard icon at 16px, then
            // "Layout – English (US)".
            Row {
                id: layoutFace
                anchors.centerIn: parent
                spacing: 8
                opacity: pill.shown === layoutFace ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f030c}"
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Layout – " + root.layoutName
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.Bold
                    font.pixelSize: 13
                }
            }

            // The two workspace labels; root.workspaceLabel is the current one.
            Text {
                id: workspaceLabelA
                property real shift: 0
                anchors.centerIn: parent
                transform: Translate { x: workspaceLabelA.shift }
                color: "white"
                font.family: "JetBrainsMono Nerd Font"
                font.weight: Font.Bold
                font.pixelSize: 13
                opacity: pill.shown === workspaceLabelA ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            Text {
                id: workspaceLabelB
                property real shift: 0
                anchors.centerIn: parent
                transform: Translate { x: workspaceLabelB.shift }
                color: "white"
                font.family: "JetBrainsMono Nerd Font"
                font.weight: Font.Bold
                font.pixelSize: 13
                opacity: pill.shown === workspaceLabelB ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }
        }

        // The full player. Laid out at its final size; it only fades in
        // once the pill has grown to fit it.
        Item {
            id: playerView
            x: 16
            y: 16
            width: root.expandedWidth - 32
            height: root.expandedHeight - 32
            opacity: root.panel === "player" ? root.panelOpacity : 0
            visible: opacity > 0

            ClippingRectangle {
                id: art
                width: parent.height
                height: parent.height
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.1)

                Image {
                    id: artImage
                    anchors.fill: parent
                    source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                // A music note where there's no cover, or no player.
                Text {
                    anchors.centerIn: parent
                    visible: artImage.status !== Image.Ready
                    text: "\u{f075a}"
                    color: "white"
                    opacity: 0.4
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.Bold
                    font.pixelSize: 40
                }
            }

            Column {
                anchors.left: art.right
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.player ? root.player.trackTitle || "Unknown" : "Nothing playing"
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.bold: true
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.player ? root.player.trackArtist : "No media player open"
                    color: "white"
                    opacity: 0.6
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.Bold
                    font.pixelSize: 13
                }

                Item { width: 1; height: 4 }

                Rectangle {
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Qt.rgba(1, 1, 1, 0.2)

                    Rectangle {
                        width: parent.width * root.progress
                        height: parent.height
                        radius: 2
                        color: "white"
                    }
                }

                Item {
                    width: parent.width
                    height: 16

                    Text {
                        anchors.left: parent.left
                        text: root.formatTime(root.position)
                        color: "white"
                        opacity: 0.6
                        font.family: "JetBrainsMono Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: 11
                    }

                    Text {
                        anchors.right: parent.right
                        text: root.formatTime(root.player ? root.player.length : 0)
                        color: "white"
                        opacity: 0.6
                        font.family: "JetBrainsMono Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: 11
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16

                    Repeater {
                        model: [
                            { glyph: "\u{f04ae}", action: () => root.player.previous() },
                            { glyph: "", action: () => root.player.togglePlaying() },
                            { glyph: "\u{f04ad}", action: () => root.player.next() }
                        ]

                        delegate: Text {
                            required property var modelData
                            required property int index
                            width: 24
                            height: 24
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            // The middle button shows pause while playing.
                            text: index !== 1 ? modelData.glyph
                                : root.player && root.player.isPlaying ? "\u{f03e4}" : "\u{f040a}"
                            color: "white"
                            // Dimmed, and inert, with no player.
                            opacity: root.player ? 1 : 0.3
                            font.family: "JetBrainsMono Nerd Font"
                            font.weight: Font.Bold
                            font.pixelSize: 18

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.player !== null
                                onClicked: parent.modelData.action()
                            }
                        }
                    }
                }
            }
        }

        // The settings panel: network, Bluetooth, volume and battery fused
        // into one pill; under it a volume row and a brightness row, each
        // an icon, a slider and the value.
        Column {
            id: settingsView
            x: 16
            y: 16
            width: root.expandedWidth - 32
            spacing: 8
            opacity: root.panel === "settings" ? root.panelOpacity : 0
            visible: opacity > 0

            Row {
                // 12px above the sliders: the 8px column gap plus 4.
                bottomPadding: 4
                spacing: 8

                // Network, Bluetooth, volume and battery fused into one
                // pill, as the main bar groups them on one island. Network,
                // Bluetooth and battery turn the panel into their page; the
                // speaker mutes in place.
                TileGroup {
                    width: settingsView.width
                    model: [
                        {
                            icon: () => Controls.networkIcon,
                            active: () => false,
                            tap: () => root.switchTo("wifi")
                        },
                        {
                            icon: () => Controls.bluetoothIcon,
                            active: () => Controls.bluetoothOn,
                            tap: () => root.switchTo("bluetooth")
                        },
                        {
                            icon: () => Controls.volumeIcon,
                            active: () => false,
                            tap: () => Controls.toggleMute()
                        },
                        {
                            icon: () => Controls.batteryIcon,
                            active: () => false,
                            tap: () => root.switchTo("battery")
                        }
                    ]
                }
            }

            Repeater {
                model: [
                    {
                        icon: () => Controls.volumeIcon,
                        value: () => Controls.muted ? 0 : Controls.volume,
                        set: v => Controls.setVolume(v),
                        // Clicking the speaker mutes and unmutes.
                        tap: () => Controls.toggleMute()
                    },
                    {
                        icon: () => Controls.brightnessIcon,
                        value: () => Controls.brightness,
                        set: v => Controls.setBrightness(v),
                        tap: null
                    }
                ]

                delegate: Item {
                    id: row
                    required property var modelData
                    width: settingsView.width
                    height: 32

                    Text {
                        id: rowIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        horizontalAlignment: Text.AlignHCenter
                        text: row.modelData.icon()
                        color: "white"
                        font.family: "JetBrainsMono Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: 18

                        MouseArea {
                            anchors.fill: parent
                            enabled: row.modelData.tap !== null
                            onClicked: row.modelData.tap()
                        }
                    }

                    Slider {
                        anchors.left: rowIcon.right
                        anchors.leftMargin: 12
                        anchors.right: rowValue.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        value: row.modelData.value()
                        onMoved: v => row.modelData.set(v)
                    }

                    Text {
                        id: rowValue
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(row.modelData.value() * 100) + "%"
                        color: "white"
                        opacity: 0.6
                        font.family: "JetBrainsMono Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: 13
                    }
                }
            }
        }

        // The settings panel's three pages, opened from its network,
        // Bluetooth and battery segments; back returns to the panel.
        WifiPage {
            id: wifiPage
            x: 16
            y: 16
            width: root.expandedWidth - 32
            opacity: root.panel === "wifi" ? root.panelOpacity : 0
            visible: opacity > 0
            onBack: root.switchTo("settings")
            onOpenSettings: root.openSettings("network")
        }

        BluetoothPage {
            x: 16
            y: 16
            width: root.expandedWidth - 32
            opacity: root.panel === "bluetooth" ? root.panelOpacity : 0
            visible: opacity > 0
            onBack: root.switchTo("settings")
            onOpenSettings: root.openSettings("bluetooth")
        }

        BatteryPage {
            x: 16
            y: 16
            width: root.expandedWidth - 32
            opacity: root.panel === "battery" ? root.panelOpacity : 0
            visible: opacity > 0
            onBack: root.switchTo("settings")
            onOpenSettings: root.openSettings("power")
        }

        // The wallpaper gallery (WallpaperGallery.qml): Enter sets the middle
        // image on every screen and closes the island.
        WallpaperGallery {
            id: gallery
            x: 16
            y: 16
            width: root.expandedWidth - 32
            height: root.expandedHeight - 32
            images: Wallpapers.images
            tileH: root.galleryTileHeight
            opacity: root.panel === "wallpaper" ? root.panelOpacity : 0
            visible: root.panel === "wallpaper" && root.phase !== "collapsed"
            onPicked: path => {
                Wallpapers.apply(path)
                root.close()
            }
            onCancelled: root.close()
        }

        // The power menu: four round icon orbs in a row. The main bar's power menu's commands and icons,
        // and like it, no confirmation: a click runs the action.
        Row {
            id: powerView
            x: 16
            y: 16
            spacing: 16
            opacity: root.panel === "power" ? root.panelOpacity : 0
            visible: opacity > 0

            Repeater {
                model: [
                    { icon: "\uf023", label: "Lock", cmd: "pidof hyprlock || hyprlock" },
                    { icon: "\uf021", label: "Reboot", cmd: "systemctl reboot" },
                    { icon: "\uf2f5", label: "Log out",
                        cmd: "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'" },
                    { icon: "\uf011", label: "Power off", cmd: "systemctl poweroff" }
                ]

                // An orb: white at 12%, solid white with a black icon while
                // hovered.
                delegate: Rectangle {
                    id: orbItem
                    required property var modelData
                    width: 56
                    height: 56
                    radius: width / 2
                    color: orbArea.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.12)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: orbItem.modelData.icon
                        color: orbArea.containsMouse ? "black" : "white"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 20
                    }

                    MouseArea {
                        id: orbArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.close()
                            // Detached, so a running hyprlock outlives any
                            // reload of the island.
                            Quickshell.execDetached(["sh", "-c", orbItem.modelData.cmd])
                        }
                    }
                }
            }
        }
    }

    // Opening: the compact text fades out, the pill grows, then the
    // panel fades in.
    SequentialAnimation {
        id: openAnim
        NumberAnimation { target: root; property: "compactOpacity"; to: 0; duration: 120 }
        NumberAnimation { target: root; property: "sizeProgress"; to: 1; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "panelOpacity"; to: 1; duration: 160 }
        onFinished: root.phase = "open"
    }

    // Closing, the reverse: the panel fades out, the compact text fades
    // in at the middle of the still-large box, then the box shrinks.
    SequentialAnimation {
        id: closeAnim
        NumberAnimation { target: root; property: "panelOpacity"; to: 0; duration: 120 }
        NumberAnimation { target: root; property: "compactOpacity"; to: 1; duration: 160 }
        NumberAnimation { target: root; property: "sizeProgress"; to: 0; duration: 220; easing.type: Easing.OutCubic }
        onFinished: {
            root.phase = "collapsed"
            // A hide that waited for the panel to close.
            if (!root.wanted)
                root.disappear()
        }
    }

    function open(which) {
        if (phase !== "collapsed")
            return
        panel = which
        closeAnim.stop()
        phase = "opening"
        // The gallery's exclusive keyboard focus reaches Hyprland a moment
        // after this; a grab already on by then is cleared by it, which
        // closed the gallery as it opened. So its grab waits for that.
        if (which === "wallpaper")
            grabSoon.restart()
        else
            focusGrab.active = true
        openAnim.start()
    }

    Timer {
        id: grabSoon
        interval: 150
        onTriggered: if (root.phase === "opening" || root.phase === "open") focusGrab.active = true
    }

    // From one open panel to another (the settings panel and its pages):
    // the panel fades out, the box eases to the new size, the new one
    // fades in.
    SequentialAnimation {
        id: switchAnim
        property string to: ""
        NumberAnimation { target: root; property: "panelOpacity"; to: 0; duration: 120 }
        ScriptAction { script: root.panel = switchAnim.to }
        PauseAnimation { duration: 220 }
        NumberAnimation { target: root; property: "panelOpacity"; to: 1; duration: 160 }
    }

    function switchTo(which) {
        if (phase !== "open" || panel === which)
            return
        switchAnim.stop()
        switchAnim.to = which
        switchAnim.start()
    }

    // The pages scan (Wi-Fi) or discover (Bluetooth) only while they are
    // the open panel.
    Binding {
        target: Controls
        property: "wifiScan"
        value: true
        when: root.panel === "wifi" && root.phase !== "collapsed"
    }

    Binding {
        target: Controls
        property: "bluetoothScan"
        value: true
        when: root.panel === "bluetooth" && root.phase !== "collapsed"
    }

    // SUPER+ALT+W: the focused screen's island opens the wallpaper gallery,
    // or closes it if it is the one open.
    Connections {
        target: Wallpapers
        function onToggleRequested() {
            if (!Hyprland.focusedMonitor || Hyprland.focusedMonitor.name !== root.modelData.name)
                return
            if (root.phase === "collapsed") {
                Wallpapers.refresh()
                root.open("wallpaper")
                gallery.reset(Wallpapers.current)
            } else if (root.panel === "wallpaper") {
                root.close()
            }
        }
    }

    // A page's gear: the island closes and the settings window opens on
    // the matching section (Network, Bluetooth or Power).
    function openSettings(section) {
        close()
        SettingsWindow.open(section)
    }

    function close() {
        if (phase === "collapsed" || phase === "closing")
            return
        openAnim.stop()
        switchAnim.stop()
        phase = "closing"
        grabSoon.stop()
        focusGrab.active = false
        closeAnim.start()
    }

    // A click anywhere outside the island closes the panel.
    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onCleared: root.close()
    }

    // Mpris only reports position on a seek, so it is re-read every
    // second while the player is open. `tick` is what forces the re-read.
    property int tick: 0
    Timer {
        interval: 1000
        repeat: true
        running: root.phase !== "collapsed" && root.player !== null
        onTriggered: root.tick++
    }
    readonly property real position: {
        tick
        return player ? player.position : 0
    }
    readonly property real progress: player && player.length > 0
        ? Math.max(0, Math.min(1, position / player.length)) : 0

    function formatTime(seconds) {
        const s = Math.max(0, Math.floor(seconds))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    NumberAnimation {
        id: slideOut
        property: "shift"
        duration: 160
        easing.type: Easing.OutCubic
        onFinished: target.shift = 0
    }

    NumberAnimation {
        id: slideIn
        property: "shift"
        to: 0
        duration: 160
        easing.type: Easing.OutCubic
    }

    // Where `other` sits when it lines up beside `from`, on the side the
    // drag (dir) is pulling it in from.
    function besideShift(from, other, dir) {
        return from.shift - dir * (from.width / 2 + peekGap + other.width / 2)
    }

    // A drag past 48px towards the other view slides the text across;
    // anything shorter slides it back to the middle.
    function release(dx) {
        slideOut.stop()
        slideIn.stop()
        widthTracksDrag = false
        const out = pill.shown
        const dir = dx > 0 ? 1 : -1
        const next = Math.abs(dx) > 48 ? viewTowards(dir) : null
        if (next !== null) {
            view = next
            const inn = pill.shown
            // The two stay side by side as the new text slides to the middle.
            slideOut.target = out
            slideOut.from = out.shift
            slideOut.to = dir * (out.width / 2 + peekGap + inn.width / 2)
            slideOut.start()
            slideIn.target = inn
        } else {
            slideIn.target = out
        }
        dragging = false
        slideIn.from = slideIn.target.shift
        slideIn.start()
    }

}
