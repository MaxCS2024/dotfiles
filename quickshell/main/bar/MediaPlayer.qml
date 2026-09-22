import QtQuick
import QtQuick.Layouts
import "../config"
import "../services"
import "../theme"

// The player in the bar, and the thing that opens the media card.
//
// It carried the whole player in a hover DropdownPanel until 2026-09-22,
// when the user asked for that to go and for a real card in its place:
// media/MediaPanel.qml, a click away, which can be seeked, keyed and
// left open while you do something else. What stays here is the glance,
// and the three controls worth having with no surface in between: the
// art, the title, prev/play/next, and a progress line along the pill's
// own bottom edge.
//
// Which player all that is about is services/Media.qml's now, not this
// file's. The card shows the same one and neither surface can see the
// other, so player selection, the position tick and the time formatter
// went there with the dropdown — this module reads `player` and nothing
// else.
Item {
    id: root

    property var barWindow

    // bar/Bar.qml builds its roving-focus order from the modules that
    // declare this property (see BarModuleLoader's `keyboardNavigable`),
    // and Enter there fires the focused module's `tapped()`. Both are
    // what bar/Clock.qml declares, for the reason it found when its own
    // dropdown became a card: a module the keyboard cannot reach is the
    // one bar surface SUPER+B skips, and a module that opens something
    // is worth reaching.
    property bool keyboardFocused: false

    signal tapped()
    onTapped: Panels.toggle("media")

    readonly property var player: Media.activePlayer

    // Takes up bar space whenever a player exists at all — paused
    // players stay visible (dimmed, see pill.opacity below) rather than
    // vanishing outright, so pausing to check something else doesn't
    // lose one-click access to resume. Closing the last player gives the
    // slot back: BarModuleLoader hides itself off this, and why it is
    // this and not `visible` is in that file.
    readonly property bool hasContent: root.player !== null

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    // Where this module's middle sits across the bar, as a fraction of
    // the bar's width — what the card centres itself on, since it is a
    // separate layer-shell surface that cannot see this one's geometry
    // (see Panels.mediaAnchor).
    //
    // `root.x`, `root.width` and the bar's width are read into `moved`
    // and otherwise unused on purpose: mapToItem is a function call, not
    // a tracked binding dependency, so without naming the geometry this
    // expression depends on it would be evaluated once and never again —
    // and a module moved to another row would open its card wherever it
    // happened to be at startup. bar/Clock.qml found that the hard way.
    readonly property real anchorFraction: {
        const bw = root.barWindow
        if (!bw || bw.width <= 0) return Panels.mediaAnchor
        const moved = root.x + root.width + bw.width
        return root.mapToItem(bw.contentItem, root.width / 2, 0).x / bw.width
    }

    Binding {
        target: Panels
        property: "mediaAnchor"
        value: root.anchorFraction
        when: root.barWindow !== null
    }

    HoverPill {
        id: pill
        // Was "+ 16" — see bar/BarButton.qml's note on the same bump,
        // made when HoverPill went fully round.
        implicitWidth: content.implicitWidth + 22
        implicitHeight: content.implicitHeight + 6
        // Lit while the card is up, which is what `dropdown.visible`
        // did for this pill before the card replaced the dropdown.
        active: hover.hovered || Panels.mediaShown || root.keyboardFocused
        anchors.centerIn: parent

        // Dim (not hide) while paused — keeps the pill legible as "not
        // currently playing" without making it disappear.
        opacity: (root.player && root.player.isPlaying) ? 1.0 : 0.55
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard } }

        RowLayout {
            id: content
            anchors.centerIn: parent
            spacing: 6

            Item {
                id: artBox
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16

                // The art and the title open the card; the three
                // transport glyphs between them keep their own clicks.
                // A single TapHandler on the module would read better
                // and be wrong: with the default DragThreshold policy a
                // handler responds without needing an exclusive grab, so
                // a press one of those MouseAreas had already accepted
                // would reach this too and "next track" would also open
                // a card.
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: root.tapped()
                }

                Image {
                    id: art
                    anchors.fill: parent
                    source: (root.player && root.player.trackArtUrl) ? root.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    text: ""
                    color: Appearance.fgDim
                    font.pixelSize: Theme.iconSize - 3
                    font.family: Theme.font
                    visible: art.status !== Image.Ready
                }
            }

            Text {
                text: "󰒮"
                color: (root.player && !root.player.canGoPrevious)
                    ? Appearance.disabled : Appearance.fg
                font.pixelSize: Theme.iconSize
                font.family: Theme.font

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.player && root.player.canGoPrevious
                    onClicked: root.player.previous()
                }
            }

            Text {
                text: (root.player && root.player.isPlaying) ? "󰏤" : "󰐊"
                color: Appearance.fg
                font.pixelSize: Theme.iconSize
                font.family: Theme.font

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.player && root.player.canTogglePlaying
                    onClicked: root.player.togglePlaying()
                }
            }

            Text {
                text: "󰒭"
                color: (root.player && !root.player.canGoNext)
                    ? Appearance.disabled : Appearance.fg
                font.pixelSize: Theme.iconSize
                font.family: Theme.font

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.player && root.player.canGoNext
                    onClicked: root.player.next()
                }
            }

            // Track titles run from a single word to a full sentence,
            // so this is the one part of the pill that can't simply size
            // to its content. It gets a width-capped viewport that clips,
            // and the title scrolls inside it when it doesn't fit.
            //
            // The cap is the same 220 the elide used to apply, and it's
            // still a cap rather than a fixed width: a short title sizes
            // the pill to itself exactly as before, a long one stops
            // growing it and scrolls instead.
            Item {
                id: titleViewport

                // `title` is deliberately left unconstrained — no
                // anchors, no Layout width — so its implicitWidth stays
                // the text's *natural* width. Binding its width to this
                // viewport would both close a loop through
                // Layout.preferredWidth and leave nothing to scroll.
                Layout.preferredWidth: Math.min(title.implicitWidth, 220)
                Layout.preferredHeight: title.implicitHeight
                clip: true

                // The card's other click target — see artBox above.
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: root.tapped()
                }

                readonly property real overflow: Math.max(0, title.implicitWidth - width)
                readonly property bool scrolling: titleViewport.overflow > 0
                // Constant speed (~20px/s), not a constant duration, so a
                // title that only just overflows doesn't crawl and a very
                // long one doesn't race. Was 25ms/px (~40px/s) — halved per
                // user request, still fast enough that a long title doesn't
                // outstay its own dwell pauses.
                readonly property int scrollDuration:
                    Math.max(Theme.animPanel, Math.round(titleViewport.overflow * 50))

                Text {
                    id: title
                    text: root.player ? (root.player.trackTitle || "Unknown") : ""
                    color: Appearance.fgSoft
                    font.pixelSize: Theme.fontMedium
                    font.family: Theme.font
                    // No elide any more: the viewport's clip is what
                    // truncates now, and an ellipsis would cut off the
                    // very text the marquee exists to reveal.

                    // Start a new track from the left instead of
                    // inheriting the previous one's offset. This also
                    // covers the case where the new title *doesn't*
                    // overflow — the animation stops, and a stale
                    // negative x would otherwise shift a short title out
                    // of the pill.
                    onTextChanged: title.x = 0
                }

                // Dwell at both ends: a marquee that turns around the
                // instant it arrives never leaves either the start or
                // the end of the title readable standing still.
                SequentialAnimation {
                    // Stops with the bar. `shown` is the *requested*
                    // state, so this lands as the bar starts sliding out
                    // rather than animating on through a strip nobody can
                    // see — bar/Bar.qml's note on `shown` names this
                    // marquee as the reason it's kept separate from
                    // `occupying`. barWindow is unset until
                    // BarModuleLoader forwards it, hence the null guard,
                    // same as the progress tick above.
                    running: titleViewport.scrolling
                        && (!root.barWindow || root.barWindow.shown)
                    loops: Animation.Infinite

                    // Every cycle starts from the left, so a track change
                    // that lands mid-scroll is corrected here at the
                    // latest even though onTextChanged already reset x.
                    ScriptAction { script: title.x = 0 }
                    PauseAnimation { duration: 1600 }
                    NumberAnimation {
                        target: title
                        property: "x"
                        to: -titleViewport.overflow
                        duration: titleViewport.scrollDuration
                        easing.type: Theme.easingStandard
                    }
                    PauseAnimation { duration: 1600 }
                    NumberAnimation {
                        target: title
                        property: "x"
                        to: 0
                        duration: titleViewport.scrollDuration
                        easing.type: Theme.easingStandard
                    }
                }
            }
        }

        // Thin progress line along the pill's own bottom edge, not a
        // separate row below it — the bar is 35px tall (bar/Bar.qml,
        // and a monitor may override it downward) and the pill alone
        // already nearly fills that (see HoverPill's own sizing note),
        // confirmed live: stacking this as a second row under the pill
        // put its top at y=31, which leaves too little beneath it to
        // draw a line in, and less than that on a shorter
        // bar. Overlaying keeps total height
        // exactly at the pill's own, so there's no bar-height budget to
        // find room in. Only shown once the player actually reports a
        // length — a stream with no known duration has nothing to draw
        // a fraction of.
        //
        // Spans art-to-title rather than the full pill width, per user
        // request: x/width are content.x (content's own centering offset
        // within `pill`) plus artBox/titleViewport's x/width — both are
        // children of `content`, not siblings of this item, so their own
        // x is relative to content rather than pill.
        //
        // Built from plain x/width properties rather than
        // artBox.mapToItem(pill, ...), which reads as more direct but
        // isn't tracked as a binding dependency — confirmed live, it froze
        // at its pre-layout value (x=0, width=156) and never updated again
        // once real content laid out.
        Rectangle {
            x: content.x + artBox.x
            width: titleViewport.x + titleViewport.width - artBox.x
            anchors.bottom: parent.bottom
            height: 2
            radius: 1
            color: Appearance.fgDim
            visible: root.player && root.player.length > 0

            Rectangle {
                width: parent.width * Media.progressFraction
                height: parent.height
                radius: parent.radius
                color: Appearance.fg
                Behavior on width { NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard } }
            }
        }
    }

    HoverHandler { id: hover }

    // Scroll adjusts this player's volume. Player-switching (the other
    // thing scroll-on-the-pill could plausibly mean) is instead a pair
    // of arrows in the dropdown next to the track identity — volume is
    // the more frequent action of the two and matches every other
    // scrollable bar item's convention (Volume/Brightness), so it gets
    // the low-friction gesture; switching players is rare enough that
    // a deliberate click is the right amount of friction for it.
    property real _lastWheelTime: 0
    WheelHandler {
        onWheel: (event) => {
            if (!root.player || !root.player.volumeSupported) return
            const now = Date.now()
            if (now - root._lastWheelTime < 40) return
            root._lastWheelTime = now

            const step = 0.05
            const delta = event.angleDelta.y > 0 ? step : -step
            root.player.volume = Math.max(0, Math.min(1, root.player.volume + delta))
        }
    }
}
