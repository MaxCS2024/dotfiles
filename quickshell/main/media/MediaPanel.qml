// The media player — a card that hangs under the bar's media module.
//
// It replaces the hover dropdown bar/MediaPlayer.qml used to carry (user
// request 2026-09-22): the same art, identity, seek bar and transport
// row, but on a surface you can reach into instead of one that answered
// to nothing but the pointer and went the moment you left it. The same
// call bar/Clock.qml made for the calendar a day earlier, and the one
// bar/VolumeButton.qml and bar/NetworkButton.qml made for their rails.
//
// Geometry and motion are calendar/CalendarPanel.qml's, because it is
// the same kind of surface: a layer-shell card in the toasts' material,
// with a focus grab, Escape and a height that is its content's, hanging
// from the module that opens it rather than from the right edge. The
// media module ships in the bar's left row, so this usually opens near
// the left of the screen — Panels.mediaAnchor is what puts it under the
// pill wherever that row actually places it.
//
// What the card has that the dropdown did not:
//   · the whole thing is keyable — space plays, Left/Right seek,
//     PageUp/PageDown change track, Up/Down set the player's volume,
//     Tab walks players, and Escape closes
//   · an elapsed time that advances (services/Media.qml's `position`
//     explains why the dropdown's did not)
//
// The layout (2026-09-28, from a reference the user sent) is a terminal-
// style "media link": a spaced caps header, the art square and full width,
// title and artist under it, a flat seek bar with a block handle, a row
// of five equal square buttons (shuffle, prev, play, next, repeat) and
// the player's own volume. Shuffle, repeat and volume had been dropped on
// 2026-09-23 and came back with this layout, by user request. The
// reference outlines every button; here they are fills, per STYLE.md §1.
//
// Which player all this is about is services/Media.qml's, not this
// file's: the pill in the bar shows the same one, and pinning a player
// here has to move that too.
import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Services.Mpris
import "../common"
import "../config"
import "../services"
import "../theme"

ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:media"
    surfaceName: "media"
    focusTarget: card

    // 380: narrower than the 400 rails — nothing here is a list — and it
    // sets the art's size too, which is the card's width less its padding.
    readonly property int cardWidth: 380

    // Room below and beside the card for its own shadow, which a
    // layer-shell surface clips like anything else.
    readonly property int shadowPad: 24

    // Content, plus the padding either side of it — the same contract as
    // calendar/CalendarPanel.qml and volume/VolumePanel.qml, and the same
    // reason it doesn't loop: a ColumnLayout's implicitHeight comes from
    // its children, and nothing in `body` fills height.
    readonly property int cardHeight: body.implicitHeight + Theme.cardPadding * 2

    // Up and behind the bar, not sideways: this card belongs to a module
    // in the bar, and the bar is where it should come from and go back
    // to. Far enough that the shadow clears too.
    readonly property int slideDistance: panel.cardHeight + panel.inset + 24

    readonly property var player: Media.activePlayer

    function seekToFraction(f) {
        if (!panel.player || !panel.player.canSeek || panel.player.length <= 0) return
        panel.player.position = Math.max(0, Math.min(1, f)) * panel.player.length
    }

    function nudgeSeek(seconds) {
        if (!panel.player || !panel.player.canSeek || panel.player.length <= 0) return
        panel.player.position = Math.max(0, Math.min(panel.player.length,
            Media.position + seconds))
    }

    function stepVolume(delta) {
        if (!panel.player || !panel.player.volumeSupported) return
        panel.player.volume = Math.max(0, Math.min(1, panel.player.volume + delta))
    }

    function cycleLoop() {
        if (!panel.player || !panel.player.loopSupported) return
        const states = [MprisLoopState.None, MprisLoopState.Playlist, MprisLoopState.Track]
        const i = states.indexOf(panel.player.loopState)
        panel.player.loopState = states[(i + 1) % states.length]
    }

    // The seek bar and the volume bar: a flat groove, an accent fill, and
    // a block handle at the fill's end. Square, like the rest of the card.
    component FlatBar: Item {
        id: bar

        property real value: 0      // 0..1
        property bool interactive: true
        signal moved(real value)

        readonly property real clamped: Math.max(0, Math.min(1, bar.value))

        implicitHeight: 16

        Rectangle {
            id: groove
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            // `sunken`, not `trackBg`: at 4px, trackBg barely separates
            // from the card's surface, and the reference's groove reads
            // as cut into it.
            color: Appearance.sunken

            Rectangle {
                width: groove.width * bar.clamped
                height: parent.height
                color: Appearance.accent
            }
        }

        Rectangle {
            width: 8
            height: 16
            anchors.verticalCenter: parent.verticalCenter
            x: Math.round(Math.max(0, Math.min(bar.width - width, groove.width * bar.clamped - width / 2)))
            color: Appearance.accent
            visible: bar.interactive
        }

        MouseArea {
            anchors.fill: parent
            anchors.topMargin: -4
            anchors.bottomMargin: -4
            enabled: bar.interactive
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            function setFromX(x) { bar.moved(Math.max(0, Math.min(1, x / width))) }
            onPressed: (mouse) => setFromX(mouse.x)
            onPositionChanged: (mouse) => { if (pressed) setFromX(mouse.x) }
        }
    }

    // One cell of the transport row. The play cell is the row's one
    // accent fill; shuffle and repeat show "on" by stepping up to
    // `selected` with an accent glyph (STYLE.md §2), never with a ring.
    component TransportButton: Rectangle {
        id: btn

        property string glyph: ""
        property bool primary: false
        property bool active: false
        property bool available: true
        signal activated()

        Layout.fillWidth: true
        implicitWidth: 40
        implicitHeight: 40
        radius: Theme.radius
        color: btn.primary ? Appearance.accent
             : btn.active ? Appearance.selected
             : (tap.containsMouse && btn.available) ? Appearance.hover
             : Appearance.surfaceAlt
        scale: tap.pressed ? 0.94 : 1

        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingDecel } }

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            color: btn.primary ? Appearance.bar
                 : !btn.available ? Appearance.disabled
                 : btn.active ? Appearance.accent
                 : Appearance.fg
            font.pixelSize: btn.primary ? Theme.fontLarge : Theme.iconSize
            font.family: Theme.font
        }

        MouseArea {
            id: tap
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.available ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: btn.available
            onClicked: btn.activated()
        }
    }

    // A full-width strip under the bar, not the screen: the card hangs
    // from the top of it, and the height is the card's own plus the room
    // its shadow needs. exclusiveZone 0 reserves nothing and respects
    // what the bar reserves, which is what puts this strip's top edge
    // under the bar rather than behind it.
    anchors { top: true; left: true; right: true }
    implicitHeight: panel.inset + panel.cardHeight + panel.shadowPad

    exclusiveZone: 0
    mask: cardMask
    Region { id: cardMask; item: cardSlot }

    // The input region is taken from THIS, an empty item pinned where the
    // card comes to rest, and never from `card` itself, which carries the
    // slide-in Translate — network/NetworkPanel.qml has the full account
    // of what goes wrong when a mask item is being transformed.
    //
    // Centred on the media module, via the fraction that module publishes
    // (Panels.mediaAnchor), and clamped to the inset so a pill parked at
    // either end still opens a card that is fully on screen. Rounded for
    // the reason the calendar's is: the anchor is a fraction of a bar row
    // that can land on a half pixel, and the card renders into a texture
    // for its shadow, so an unrounded x is resampled rather than nudged.
    Item {
        id: cardSlot
        anchors.top: parent.top
        anchors.topMargin: panel.inset
        width: panel.cardWidth
        height: panel.cardHeight
        x: Math.round(Math.max(panel.inset,
             Math.min(panel.width - panel.cardWidth - panel.inset,
                      Panels.mediaAnchor * panel.width - panel.cardWidth / 2)))

        // The card changes height when a player with no album line is
        // replaced by one that has it, when the switcher row appears on a
        // second player, and when a stream with no length hides the seek
        // bar. Animated for the same reason the slide is.
        Behavior on height {
            NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard }
        }
    }

    // Keeps the media module's hover pill lit while its card is up, which
    // is what the dropdown's own `visible` used to do for it — and keeps
    // services/Media.qml ticking when the bar is hidden and this card is
    // the only thing watching.
    Binding {
        target: Panels
        property: "mediaShown"
        value: panel.shown
        when: panel.shown
    }

    Rectangle {
        id: card

        anchors.fill: cardSlot

        radius: Theme.radius
        color: Appearance.surface
        border.width: Theme.hyprBorderWidth
        border.color: Appearance.border
        clip: true

        focus: true
        Keys.onPressed: (event) => {
            switch (event.key) {
            case Qt.Key_Escape:
                panel.close()
                break
            case Qt.Key_Space:
                if (panel.player && panel.player.canTogglePlaying)
                    panel.player.togglePlaying()
                break
            // Seeking in fives, the step a keyboard seek is worth on a
            // card whose pointer path is a bar you click anywhere on.
            case Qt.Key_Left:
                panel.nudgeSeek(-5)
                break
            case Qt.Key_Right:
                panel.nudgeSeek(5)
                break
            // The player's volume, the one control on the card with no
            // other key; the pill's wheel is the same gesture.
            case Qt.Key_Up:
                panel.stepVolume(0.05)
                break
            case Qt.Key_Down:
                panel.stepVolume(-0.05)
                break
            // Track, not player: the two arrows that walk players sit in
            // their own row and are rare enough to be worth the reach.
            case Qt.Key_PageDown:
                if (panel.player && panel.player.canGoNext) panel.player.next()
                break
            case Qt.Key_PageUp:
                if (panel.player && panel.player.canGoPrevious) panel.player.previous()
                break
            case Qt.Key_Tab:
                Media.switchPlayer(1)
                break
            default:
                return
            }
            event.accepted = true
        }

        opacity: panel.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: panel.shown ? panel.enterDuration : panel.exitDuration
                easing.type: panel.shown ? Theme.easingDecel : Easing.InCubic
            }
        }

        transform: Translate {
            y: panel.shown ? 0 : -panel.slideDistance
            Behavior on y {
                NumberAnimation {
                    duration: panel.shown ? panel.enterDuration : panel.exitDuration
                    easing.type: panel.shown ? Theme.easingDecel : Easing.InCubic
                }
            }
        }

        layer.enabled: true
        layer.effect: PopupShadow {}
        // The Hyprland window border (common/HyprFrame.qml), declared
        // first so everything else paints over it — the toasts, the
        // rails, the calendar and the Conf menu all wear this same ring.
        HyprFrame {
            frameWidth: card.border.width
            targetRadius: card.radius
        }

        ColumnLayout {
            id: body

            anchors.fill: parent
            anchors.margins: Theme.cardPadding
            spacing: Theme.space2

            // ── Header ───────────────────────────────────
            // A spaced caps label, and the player switch at the other end
            // when there is more than one player to switch between. The
            // reference ends the label on 音; no CJK font is installed,
            // so it's a Nerd Font note (nf-md-music_note) instead.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                Text {
                    text: "MEDIA.LINK // \u{f075a}"
                    color: Appearance.fgMuted
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    font.letterSpacing: 2
                }

                Item { Layout.fillWidth: true }

                Text {
                    visible: Media.players.length > 1
                    text: "\u{f0141}"
                    color: prevPlayerTap.containsMouse ? Appearance.accent : Appearance.fgSoft
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font

                    MouseArea {
                        id: prevPlayerTap
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Media.switchPlayer(-1)
                    }
                }

                Text {
                    visible: Media.players.length > 1
                    text: panel.player ? panel.player.identity.toUpperCase() : ""
                    color: Appearance.fgMuted
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    font.letterSpacing: 1
                    Layout.maximumWidth: 140
                    elide: Text.ElideRight
                }

                Text {
                    visible: Media.players.length > 1
                    text: "\u{f0142}"
                    color: nextPlayerTap.containsMouse ? Appearance.accent : Appearance.fgSoft
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font

                    MouseArea {
                        id: nextPlayerTap
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Media.switchPlayer(1)
                    }
                }
            }

            // ── Nothing playing ──────────────────────────
            // The bar module hides itself when no player exists, so the
            // usual way in is gone before this can be seen — but the IPC
            // target and its shortcut are not, and a card that opened
            // empty with no explanation would read as broken.
            Text {
                visible: !panel.player
                text: "Nothing is playing"
                color: Appearance.fgDim
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
            }

            // ── Art ──────────────────────────────────────
            // Square and the card's full width: the art is what the card
            // is for.
            Rectangle {
                visible: panel.player !== null
                Layout.fillWidth: true
                Layout.preferredHeight: width
                radius: Theme.radius
                color: Appearance.surfaceAlt

                // Masked rather than clipped: a rounded Rectangle does
                // not round what an Image inside it paints. Both sources
                // are invisible on their own and exist only to feed the
                // effect.
                Image {
                    id: art
                    anchors.fill: parent
                    source: panel.player && panel.player.trackArtUrl ? panel.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: width
                    sourceSize.height: height
                    visible: false
                    layer.enabled: true
                }

                Rectangle {
                    id: artMask
                    anchors.fill: parent
                    radius: Theme.radius
                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    anchors.fill: parent
                    source: art
                    maskEnabled: true
                    maskSource: artMask
                    visible: art.status === Image.Ready
                }

                // U+F001 (nf-fa-music), the same stand-in the volume
                // rail's stream rows wear when a client names no icon.
                Text {
                    anchors.centerIn: parent
                    text: "\u{f001}"
                    color: Appearance.fgDim
                    font.pixelSize: Theme.fontHuge
                    font.family: Theme.font
                    visible: art.status !== Image.Ready
                }
            }

            // ── Identity ─────────────────────────────────
            ColumnLayout {
                visible: panel.player !== null
                Layout.fillWidth: true
                Layout.topMargin: Theme.space1
                spacing: Theme.space1

                // Up to two lines, then elided, so a podcast episode
                // titled like a sentence cannot push the controls off.
                Text {
                    text: panel.player ? (panel.player.trackTitle || "Unknown") : ""
                    color: Appearance.fgStrong
                    font.bold: true
                    font.pixelSize: Theme.fontLarge
                    font.family: Theme.font
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Text {
                    text: panel.player ? (panel.player.trackArtist || "").toUpperCase() : ""
                    color: Appearance.fgSoft
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    font.letterSpacing: 1
                    visible: text !== ""
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }
            }

            // ── Seek ─────────────────────────────────────
            // Position is written directly as an absolute value (seconds)
            // rather than via seek() — confirmed live against a real MPRIS
            // session that a direct `position =` assignment routes to the
            // player's SetPosition, and seconds is the right unit for both
            // (Quickshell normalizes MPRIS's native microseconds either
            // way; also confirmed live).
            FlatBar {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space1
                visible: panel.player && panel.player.length > 0
                value: Media.progressFraction
                interactive: panel.player !== null && panel.player.canSeek
                onMoved: (v) => panel.seekToFraction(v)
            }

            RowLayout {
                Layout.fillWidth: true
                visible: panel.player && panel.player.length > 0

                Text {
                    text: Media.fmtTime(Media.position)
                    color: Appearance.fgMuted
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.font
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: panel.player ? Media.fmtTime(panel.player.length) : "0:00"
                    color: Appearance.fgMuted
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.font
                }
            }

            // ── Transport ────────────────────────────────
            RowLayout {
                visible: panel.player !== null
                Layout.fillWidth: true
                Layout.topMargin: Theme.space1
                spacing: Theme.space2

                TransportButton {
                    // nf-md-shuffle_variant / shuffle_disabled
                    glyph: panel.player && panel.player.shuffle ? "\u{f049d}" : "\u{f049e}"
                    available: panel.player !== null && panel.player.shuffleSupported
                    active: available && panel.player.shuffle
                    onActivated: panel.player.shuffle = !panel.player.shuffle
                }

                TransportButton {
                    glyph: "\u{f04ae}"
                    available: panel.player !== null && panel.player.canGoPrevious
                    onActivated: panel.player.previous()
                }

                TransportButton {
                    primary: true
                    glyph: panel.player && panel.player.isPlaying ? "\u{f03e4}" : "\u{f040a}"
                    available: panel.player !== null && panel.player.canTogglePlaying
                    onActivated: panel.player.togglePlaying()
                }

                TransportButton {
                    glyph: "\u{f04ad}"
                    available: panel.player !== null && panel.player.canGoNext
                    onActivated: panel.player.next()
                }

                TransportButton {
                    // nf-md-repeat / repeat_once / repeat_off; a click
                    // walks off → playlist → track.
                    glyph: !panel.player ? "\u{f0457}"
                         : panel.player.loopState === MprisLoopState.Track ? "\u{f0458}"
                         : panel.player.loopState === MprisLoopState.Playlist ? "\u{f0456}"
                         : "\u{f0457}"
                    available: panel.player !== null && panel.player.loopSupported
                    active: available && panel.player.loopState !== MprisLoopState.None
                    onActivated: panel.cycleLoop()
                }
            }

            // ── This player's volume ─────────────────────
            // Not the system volume — that is the sink, and the volume
            // rail owns it. This is the player's own level, the one the
            // pill's wheel changes. Only drawn for a player that supports
            // it; MPRIS makes the property optional.
            RowLayout {
                visible: panel.player !== null && panel.player.volumeSupported
                Layout.fillWidth: true
                Layout.topMargin: Theme.space1
                spacing: Theme.space3

                Text {
                    text: "VOL"
                    color: Appearance.fgMuted
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    font.letterSpacing: 2
                    Layout.preferredWidth: 40
                }

                FlatBar {
                    Layout.fillWidth: true
                    value: panel.player ? panel.player.volume : 0
                    onMoved: (v) => { if (panel.player) panel.player.volume = v }
                }

                Text {
                    text: Math.round((panel.player ? panel.player.volume : 0) * 100) + "%"
                    color: Appearance.fg
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 32
                }
            }
        }
    }
}
