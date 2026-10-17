import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

// Shows the time. While something plays, the song view sits beside it and
// the two loop: dragging either way switches between them. A workspace
// switch shows "Workspace N" over any of them for 1.5 seconds, and a
// volume or brightness change shows its percentage and a filling circle
// for as long. Plugging in the charger, or the battery running low,
// shows a battery notice for 3 seconds. While voxtype records or
// transcribes, the dictation face covers all of that. While music plays
// and the pill shows anything but the song, the album art sits in a
// small circle beside it. A left click
// opens the full media player, a middle click a small settings panel
// (whose network, Bluetooth and battery segments turn it into a page of
// their own); a click on either, or anywhere else, closes it.
// SUPER+ALT+SPACE hides and shows it: the sides close in to an orb that
// fades out, and the reverse. Hidden, it still pops up for a flash
// (anything but the workspace name) and goes again after it.
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
    // Hidden, it reserves nothing, even while the privacy dots keep the
    // window up or a flash pops it up.
    exclusionMode: reserves ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: 24
    color: "transparent"

    // Big enough for the pill to grow into; only the pill takes clicks.
    // A fixed size, so the window isn't resized every frame of the opening:
    // the largest panel, the wallpaper gallery, decides it.
    // Room beside the widest pill for the song's circle (8 + 32) and the
    // privacy dots after it (4 + 3 × 16) too.
    implicitWidth: Math.max(400 + 2 * 92, galleryWidth)
    implicitHeight: Math.max(288, galleryHeight)
    // The wallpaper gallery: exactly three whole images wide (the middle
    // one and one to each side, none cut off), and only as tall as its
    // row: images 12% of the screen's height, the middle one's 16px lift,
    // 16px padding.
    readonly property real galleryWidth: 3 * gallery.tileW + 2 * gallery.gap + 32
    readonly property real galleryTileHeight: Math.round(modelData.height * 0.12)
    readonly property real galleryHeight: galleryTileHeight + gallery.lift + 32
    // The pill, the song's circle and the privacy dots take clicks; the
    // rest passes through.
    // Popped up while hidden, the pill takes no clicks either.
    mask: Region {
        Region { item: root.wanted ? pill : null }
        Region { item: root.songReach > 0 ? songCircle : null; radius: songCircle.radius }
        Region { item: privacyDots }
    }
    // Keyboard focus while the settings panel (or one of its pages) is
    // open, for the Wi-Fi page's password field. Set as the panel opens,
    // before the focus grab: changing it while the grab is on clears the
    // grab, which closes the island.
    // The wallpaper gallery takes it outright, so the arrows work without a
    // click first.
    WlrLayershell.keyboardFocus: phase === "collapsed" || panel === "player"
        ? WlrKeyboardFocus.None
        : panel === "wallpaper" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    // Unmapped once the hide animation has run, so it takes no clicks.
    // Hidden, the window goes, unless a privacy dot is lit: nothing hides
    // those. The pill has shrunk to a point by then, so only the dots
    // show, at its centre.
    readonly property bool privacyOn: Privacy.kinds.some(k => Privacy.users[k].length > 0)
    visible: !gone || privacyOn

    // Which expanded panel opens: "player" or "settings", or the
    // settings panel's "wifi", "bluetooth" and "battery" pages. Set while collapsed,
    // or by switchTo() while open, which eases the size from one to the
    // other.
    property string panel: "player"
    readonly property real expandedWidth: panel === "wallpaper" ? galleryWidth : 360
    property real expandedHeight: panel === "wallpaper" ? galleryHeight
        : panel === "settings" ? 156 + quickRowHeight * quickReveal
        : panel === "wifi" || panel === "bluetooth" ? 288
        : panel === "battery" ? 200 : 128
    Behavior on expandedHeight {
        // Not while the quick settings row is dragged or eased open: the
        // height follows quickReveal itself then.
        enabled: root.phase === "open" && !root.quickDragging && !quickAnim.running
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    // The quick settings row under the settings panel's notch: 0 hidden,
    // 1 shown, in between while it is dragged. It stays as it was left
    // until the next drag, also across openings.
    readonly property real quickRowHeight: 52
    property real quickReveal: 0
    property bool quickDragging: false

    NumberAnimation {
        id: quickAnim
        target: root
        property: "quickReveal"
        duration: 160
        easing.type: Easing.OutCubic
    }

    function revealQuick(to) {
        quickAnim.stop()
        quickAnim.to = to
        quickAnim.start()
    }

    // "collapsed", "opening", "open" or "closing". The three animated
    // values below are what the open and close sequences step through.
    property string phase: "collapsed"
    property real compactOpacity: 1
    property real sizeProgress: 0
    property real panelOpacity: 0

    // Hiding (SUPER+ALT+SPACE). `orbing` turns the
    // width Behavior off for the whole hide/show, so it can't fight
    // shrinkProgress; it is set before either animation starts and
    // cleared only once the pill is whole. shrinkProgress 0 is the pill, 1 nothing: the sides close in
    // to a circle and the circle keeps shrinking to a point.
    readonly property bool wanted: Controls.barVisible
    property bool orbing: false
    property bool gone: false
    property real shrinkProgress: 0
    property real orbTextOpacity: 1

    // Hidden, a flash pops the pill up for as long as it lasts, then it
    // goes again: minimised rather than gone. Not the workspace name,
    // which comes with every switch.
    readonly property bool flashing: showOsd || showBattery || showDisplay
        || showLayout || showNotice
    readonly property bool popped: !wanted && flashing
    readonly property bool up: wanted || popped
    // Windows make room only when it is shown for good, not for a pop,
    // and keep it until the hide has run.
    property bool reserves: true

    onUpChanged: up ? appear() : disappear()
    onWantedChanged: if (wanted) reserves = true

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
        onFinished: {
            root.gone = true
            root.reserves = false
        }
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
    // -1 song, 0 time.
    property int view: 0
    property int workspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0

    // Prefer whichever player is playing, else the first one with a title.
    readonly property var player: {
        const players = Mpris.players.values.filter(p =>
            p.playbackState !== MprisPlaybackState.Stopped || p.trackTitle !== "")
        return players.find(p => p.isPlaying) ?? players[0] ?? null
    }
    // With no player, neither the song view nor the media player opens,
    // and both go away when the player does: the player closes, the song
    // view gives way to the time.
    onPlayerChanged: {
        if (player)
            return
        if (panel === "player")
            close()
        if (view === -1)
            view = 0
    }
    readonly property int shownView: view

    function labelFor(v) {
        return v === -1 ? mediaLabel : clockLabel
    }
    // The view a drag in `dir` (1 right, -1 left) brings in, or null for
    // none. Song and time loop while something plays: a drag either way
    // brings in the other, from the side it is dragged from. With nothing
    // playing only the time is left, and a drag rubber-bands.
    function viewTowards(dir) {
        if (!player)
            return null
        return shownView === -1 ? 0 : -1
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
    // lower one they move right. That goes for the time and song
    // views as much as an earlier name. Only the OSD and battery faces,
    // an open panel and a drag still get the plain fade.
    property Text workspaceLabel: workspaceLabelA
    property int lastWorkspace: 0

    onWorkspaceIdChanged: {
        if (workspaceId < 1)
            return
        const name = "Workspace " + workspaceId
        // Hidden, the name doesn't flash, nor cut short a flash that
        // popped the pill up.
        if (!wanted) {
            showWorkspace = false
            workspaceLabel.text = name
            workspaceLabel.shift = 0
            lastWorkspace = workspaceId
            return
        }
        const out = pill.shown
        const slides = phase === "collapsed" && !dragging
            && !slideOut.running && !slideIn.running
            && out !== osdFace && out !== batteryFace && out !== displayFace
            && out !== layoutFace && out !== noticeFace && out !== dictationFace
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
        showNotice = false
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
            root.showNotice = false
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
    // battery" below 20% and 10%, "Battery critical" below 5%. Nobody asked for it, so it stays twice
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
            root.showNotice = false
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
            root.showNotice = false
            root.showDisplay = true
            displayTimer.restart()
        }
    }

    Timer {
        id: displayTimer
        interval: 3000
        onTriggered: root.showDisplay = false
    }

    // The layout and Caps Lock notices: "Layout – English (US)" when
    // the layout changes, "Caps Lock – on" or "– off" when it toggles.
    // 1.5 seconds, like the workspace name: the user did it. They share
    // one face (layoutFace).
    property bool showLayout: false
    property string layoutIcon: ""
    property string layoutBefore: ""
    property string layoutName: ""

    Connections {
        target: Controls
        function onLayoutNotice(name) {
            root.flashShort("\u{f030c}", "Layout – ", name)
        }
        function onCapsNotice(on) {
            root.flashShort("\u{f0632}", "Caps Lock – ", on ? "on" : "off")
        }
        function onMicNotice(muted) {
            root.flashShort(muted ? "\u{f036d}" : "\u{f036c}", "Microphone – ", muted ? "muted" : "on")
        }
    }

    function flashShort(icon, before, name) {
        if (phase !== "collapsed" || dragging)
            return
        layoutIcon = icon
        layoutBefore = before
        layoutName = name
        showWorkspace = false
        showOsd = false
        showBattery = false
        showDisplay = false
        showNotice = false
        showLayout = true
        layoutTimer.restart()
    }

    Timer {
        id: layoutTimer
        interval: 1500
        onTriggered: root.showLayout = false
    }

    // The network and Bluetooth notices (Controls.notice): an icon and a
    // line, "Connected – Telia-3D6C57", "Wi-Fi lost", "Nothing Ear (3)
    // connected – 80%", the name kept apart so only it is cut. 3 seconds,
    // like the battery notice: often nothing the user did just then.
    property bool showNotice: false
    property string noticeIcon: ""
    property string noticeBefore: ""
    property string noticeName: ""
    property string noticeAfter: ""

    Connections {
        target: Controls
        function onNotice(icon, before, name, after) {
            if (root.phase !== "collapsed" || root.dragging)
                return
            root.noticeIcon = icon
            root.noticeBefore = before
            root.noticeName = name
            root.noticeAfter = after
            root.showWorkspace = false
            root.showOsd = false
            root.showBattery = false
            root.showDisplay = false
            root.showLayout = false
            root.showNotice = true
            noticeTimer.restart()
        }
    }

    Timer {
        id: noticeTimer
        interval: 3000
        onTriggered: root.showNotice = false
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
        // Right only closes an open panel; it opens nothing.
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onPressed: mouse => {
            pressX = mouse.x
            moved = false
            onDisplayNotice = root.showDisplay
            if (root.phase !== "collapsed" || mouse.button !== Qt.LeftButton)
                return
            // The dictation face has its own buttons; the rest of it
            // neither drags nor opens the player.
            if (Dictation.busy)
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
            noticeTimer.stop()
            root.showNotice = false
            // Catch the text mid-slide where it is; park the other one.
            slideOut.stop()
            slideIn.stop()
            for (const label of [clockLabel, mediaLabel])
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
            const raw = mouse.x - startX
            // Towards an end of the row (or the song view while nothing
            // plays) the text gives a little and resists, like a list's
            // edge, rather than following the cursor into nothing.
            dx = root.viewTowards(raw > 0 ? 1 : -1) === null ? root.rubberBand(raw) : raw
            pill.shown.shift = dx
            if (root.peek)
                root.peek.shift = root.besideShift(pill.shown, root.peek, dx > 0 ? 1 : -1)
        }
        onReleased: mouse => {
            if (root.phase === "open") {
                root.close()
            } else if (mouse.button === Qt.MiddleButton) {
                if (root.phase === "collapsed")
                    root.open("settings")
            } else if (mouse.button === Qt.RightButton) {
                return
            } else if (root.dragging) {
                root.release(moved ? dx : 0)
                if (!moved && onDisplayNotice)
                    SettingsWindow.open("displays")
                // Only with something to play: no empty player.
                else if (!moved && root.player)
                    root.open("player")
            }
        }
        onCanceled: if (root.dragging) root.release(0)
    }

    // ── The song's circle ──
    // Two things at once: while music plays and the pill shows something
    // else (the time, a flash, dictation), the album art sits in a small
    // circle 8px right of the pill. It grows out from under the pill's
    // right end (250ms) and tucks back under it (150ms) when the song view
    // comes up, a panel opens, the island hides, or the music stops: at
    // once with no player, 60 seconds after a pause. A click opens the
    // player. Declared before the pill, which covers it while tucked in.
    readonly property bool songPlaying: player !== null && player.isPlaying
    // Playing, or paused less than a minute ago. Set at start, not bound:
    // a binding would drop it the moment the music pauses.
    property bool songRecent: false
    Component.onCompleted: songRecent = songPlaying
    onSongPlayingChanged: {
        if (songPlaying) {
            songPausedTimer.stop()
            songRecent = true
        } else {
            songPausedTimer.restart()
        }
    }

    Timer {
        id: songPausedTimer
        interval: 60000
        onTriggered: root.songRecent = false
    }

    readonly property bool songSplit: player !== null && songRecent
        && (view !== -1 || Dictation.busy)
        && phase === "collapsed" && wanted && !gone && !orbing
    // How far the circle (with the gap before it) reaches out of the pill:
    // 0 tucked under it, songFull out. The privacy dots ride on it.
    readonly property real songFull: 8 + 32
    property real songReach: 0

    onSongSplitChanged: {
        songAnim.stop()
        songAnim.to = songSplit ? songFull : 0
        songAnim.duration = songSplit ? 250 : 150
        songAnim.start()
    }

    NumberAnimation {
        id: songAnim
        target: root
        property: "songReach"
        easing.type: Easing.OutCubic
    }

    Rectangle {
        id: songCircle
        x: pill.x + pill.width + root.songReach - width
        y: pill.y + (Math.min(pill.height, 32) - height) / 2
        width: 32
        height: 32
        radius: 16
        color: "black"
        visible: root.songReach > 0
        scale: 0.5 + 0.5 * root.songReach / root.songFull

        // The cover, round, or a music note while there is none.
        ClippingRectangle {
            anchors.centerIn: parent
            width: 20
            height: 20
            radius: 10
            color: Qt.rgba(1, 1, 1, 0.1)

            Text {
                anchors.centerIn: parent
                visible: songCover.status !== Image.Ready
                text: "\u{f075a}"
                color: "white"
                font.family: "JetBrainsMono Nerd Font"
                font.weight: Font.Bold
                font.pixelSize: 13
            }

            Image {
                id: songCover
                anchors.fill: parent
                source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
                sourceSize.width: 40
                sourceSize.height: 40
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.open("player")
        }
    }

    Rectangle {
        id: pill

        readonly property real padX: 32
        // A notice's icon and line together, so the pill is at most 400px.
        readonly property real noticeMaxWidth: 400 - padX * 2
        // The OSD face sits tighter to the ends than the text views.
        // The dictation face's buttons sit 4px from the rounded ends.
        readonly property real shownPadX: shown === osdFace ? 24
            : shown === dictationFace ? 4 : padX
        // Dictation isn't a flash: it stays up over everything for as long
        // as it lasts, and a flash that comes meanwhile waits behind it.
        readonly property Item shown: Dictation.busy ? dictationFace
            : root.showNotice ? noticeFace
            : root.showLayout ? layoutFace
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
        // while hiding or showing.
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

            // The song view: a music note, then "Title – Artist". The pill
            // stays within 400px like the notices; a longer line scrolls
            // behind the note like Spotify's: it rests at the start for
            // 1.8 s, glides to its end at 30px a second, rests, and glides
            // back. A new track starts it over. It runs only while the song
            // view is on screen.
            Item {
                id: mediaLabel
                property real shift: 0
                anchors.centerIn: parent
                transform: Translate { x: mediaLabel.shift }
                width: Math.min(mediaNote.implicitWidth + mediaTitle.implicitWidth, pill.noticeMaxWidth)
                height: mediaTitle.implicitHeight
                opacity: pill.shown === mediaLabel || root.peek === mediaLabel ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }

                Text {
                    id: mediaNote
                    // The space is part of the note, as it was in one line.
                    text: "\u{f075a} "
                    color: "white"
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.Bold
                    font.pixelSize: 13
                }

                Item {
                    id: titleBox
                    x: mediaNote.implicitWidth
                    width: parent.width - x
                    height: parent.height
                    clip: true

                    readonly property real overflow: Math.max(0, mediaTitle.implicitWidth - width)
                    property real scroll: 0
                    readonly property bool scrolls: overflow > 0 && pill.shown === mediaLabel
                        && root.phase === "collapsed" && !root.gone
                    onScrollsChanged: restartScroll()
                    onOverflowChanged: restartScroll()

                    function restartScroll() {
                        titleScroll.stop()
                        scroll = 0
                        if (scrolls)
                            titleScroll.start()
                    }

                    Text {
                        id: mediaTitle
                        x: -titleBox.scroll
                        text: {
                            if (!root.player)
                                return "Nothing playing"
                            const title = root.player.trackTitle || "Unknown"
                            const artist = root.player.trackArtist
                            // "Title – Artist", an en dash between.
                            return artist ? title + " – " + artist : title
                        }
                        onTextChanged: titleBox.restartScroll()
                        color: "white"
                        font.family: "JetBrainsMono Nerd Font"
                        font.weight: Font.Bold
                        font.pixelSize: 13
                    }

                    SequentialAnimation {
                        id: titleScroll
                        loops: Animation.Infinite
                        PauseAnimation { duration: 1800 }
                        NumberAnimation {
                            target: titleBox
                            property: "scroll"
                            from: 0
                            to: titleBox.overflow
                            duration: titleBox.overflow / 30 * 1000
                        }
                        PauseAnimation { duration: 1800 }
                        NumberAnimation {
                            target: titleBox
                            property: "scroll"
                            from: titleBox.overflow
                            to: 0
                            duration: titleBox.overflow / 30 * 1000
                        }
                    }
                }
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

            // The notices (NoticeFace.qml): an icon, then a line whose
            // name part is cut with "…" so the pill stays within 400px.
            NoticeFace {
                id: batteryFace
                shown: pill.shown === batteryFace
                maxWidth: pill.noticeMaxWidth
                icon: Controls.batteryIcon
                before: root.batteryKind === "full" ? "Fully charged"
                    : root.batteryKind === "charged" ? "Charged to " + Math.round(Controls.batteryPercent) + "%"
                    : (root.batteryKind === "critical" ? "Battery critical"
                        : root.batteryKind === "low" ? "Low battery" : "Charging")
                    + " – " + Math.round(Controls.batteryPercent) + "%"
            }

            NoticeFace {
                id: displayFace
                shown: pill.shown === displayFace
                maxWidth: pill.noticeMaxWidth
                icon: "\u{f0379}"
                before: "Display connected – "
                name: root.displayLabel
            }

            NoticeFace {
                id: layoutFace
                shown: pill.shown === layoutFace
                maxWidth: pill.noticeMaxWidth
                icon: root.layoutIcon
                before: root.layoutBefore
                name: root.layoutName
            }

            NoticeFace {
                id: noticeFace
                shown: pill.shown === noticeFace
                maxWidth: pill.noticeMaxWidth
                icon: root.noticeIcon
                before: root.noticeBefore
                name: root.noticeName
                after: root.noticeAfter
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

        // The dictation face (DictationFace.qml), outside the track: its
        // buttons reach closer to the ends than the track's inset.
        Item {
            anchors.fill: parent
            opacity: root.compactOpacity * root.orbTextOpacity

            DictationFace {
                id: dictationFace
                anchors.centerIn: parent
                shown: pill.shown === dictationFace
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

                            // A round 32px fill behind the glyph: white at
                            // 12% while hovered, 20% while pressed, like
                            // the pages' back button. Drawn past the 24px
                            // button, so the row's layout doesn't change;
                            // the 16px spacing leaves 8px between fills.
                            Rectangle {
                                z: -1
                                anchors.centerIn: parent
                                width: 32
                                height: 32
                                radius: 16
                                color: Qt.rgba(1, 1, 1, controlArea.pressed ? 0.2
                                    : controlArea.containsMouse ? 0.12 : 0)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: controlArea
                                // The whole fill takes the pointer, not just the glyph.
                                anchors.centerIn: parent
                                width: 32
                                height: 32
                                hoverEnabled: true
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
                // pill. Network,
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

            // The quick settings, revealed by dragging the notch below
            // (12px under the sliders: the column's 8px gap plus 4).
            Item {
                width: settingsView.width
                height: 44
                opacity: root.quickReveal
                visible: opacity > 0

                TileGroup {
                    y: 4
                    width: parent.width
                    model: [
                        {
                            icon: () => "\u{f0176}",
                            active: () => QuickSettings.stayAwake,
                            tap: () => QuickSettings.toggleStayAwake()
                        },
                        {
                            icon: () => QuickSettings.dnd ? "\uf1f6" : "\uf0f3",
                            active: () => QuickSettings.dnd,
                            tap: () => QuickSettings.toggleDnd()
                        },
                        {
                            icon: () => "\u{f0594}",
                            active: () => QuickSettings.nightLight,
                            tap: () => QuickSettings.toggleNightLight()
                        },
                        {
                            icon: () => QuickSettings.micMuted ? "\u{f036d}" : "\u{f036c}",
                            active: () => false,
                            tap: () => QuickSettings.toggleMic()
                        }
                    ]
                }
            }
        }

        // The notch: a short bar in the settings panel's bottom padding.
        // Dragging it down reveals the quick settings row, up hides it
        // again; past halfway it finishes the way it was going, short of
        // that it eases back. A click opens or closes the row.
        Item {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96
            height: 16
            opacity: root.panel === "settings" ? root.panelOpacity : 0
            visible: opacity > 0

            Rectangle {
                anchors.centerIn: parent
                width: 32
                height: 4
                radius: 2
                color: "white"
                opacity: notchArea.containsMouse || notchArea.pressed ? 0.6 : 0.3
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            MouseArea {
                id: notchArea

                // In the window's coordinates: the notch moves down with
                // the panel's bottom as the row opens.
                property real startY: 0
                property real startReveal: 0
                property bool moved: false

                anchors.fill: parent
                hoverEnabled: true
                enabled: root.panel === "settings" && root.phase === "open"
                onPressed: mouse => {
                    quickAnim.stop()
                    startY = mapToItem(null, mouse.x, mouse.y).y
                    startReveal = root.quickReveal
                    moved = false
                    root.quickDragging = true
                }
                onPositionChanged: mouse => {
                    if (!pressed)
                        return
                    const dy = mapToItem(null, mouse.x, mouse.y).y - startY
                    if (Math.abs(dy) > 4)
                        moved = true
                    root.quickReveal = Math.max(0, Math.min(1, startReveal + dy / root.quickRowHeight))
                }
                onReleased: {
                    root.quickDragging = false
                    root.revealQuick(moved ? (root.quickReveal > 0.5 ? 1 : 0) : (startReveal > 0.5 ? 0 : 1))
                }
                onCanceled: {
                    root.quickDragging = false
                    root.revealQuick(startReveal > 0.5 ? 1 : 0)
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
            if (!root.up)
                root.disappear()
        }
    }

    function open(which) {
        if (phase !== "collapsed")
            return
        panel = which
        if (which === "settings")
            QuickSettings.refresh()
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
    // How far the text goes when pulled `d` px towards nothing: it starts
    // at the cursor's pace and slows, never past `rubberMax`.
    readonly property real rubberMax: 16
    function rubberBand(d) {
        return Math.sign(d) * rubberMax * (1 - Math.exp(-Math.abs(d) / (rubberMax * 1.5)))
    }

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


    // ── Privacy dots ──
    // Brought over from ../island (Privacy.qml): one dot per device in use,
    // microphone (orange), camera (green), screen (red), in that order,
    // never merged; 8px, 8px apart, just right of the pill and centred on
    // its collapsed line, so they ride along as it grows and shrinks.
    // Nothing hides them: not a panel, not hiding the island. A click
    // names the apps on that device.
    Row {
        id: privacyDots
        x: pill.x + pill.width + root.songReach + 4
        y: pill.y + (Math.min(pill.height, 32) - height) / 2

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
                    width: 8
                    height: 8
                    radius: 4
                    color: Privacy.color(dot.modelData)
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
}
