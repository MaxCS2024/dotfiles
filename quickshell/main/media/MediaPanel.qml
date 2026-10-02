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
// The layout is the 2026-09-28 "media link" card (from a reference the
// user sent) turned on its side, picked from three candidates on
// 2026-10-02 because the full-width art made the card ~600px tall for
// something hanging off the bar: the art runs the card's height on the
// left, and the title, caps artist, a flat seek bar with a block handle,
// five equal square buttons (shuffle, prev, play, next, repeat) and the
// player's own volume stack beside it. The reference outlines every
// button; here they are fills, per STYLE.md §1.
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

    // Wide rather than tall: the art sits beside the controls (see the
    // header), and 440 leaves the column right of it room for a title.
    readonly property int cardWidth: 440

    // Room below and beside the card for its own shadow, which a
    // layer-shell surface clips like anything else.
    readonly property int shadowPad: 24

    // Content, plus the padding either side of it — the same contract as
    // calendar/CalendarPanel.qml and volume/VolumePanel.qml, and the same
    // reason it doesn't loop: a ColumnLayout's implicitHeight comes from
    // its children, and nothing in `body` fills height.
    readonly property int cardHeight:
        (panel.player ? body.implicitHeight : emptyText.implicitHeight) + Theme.cardPadding * 2

    // Up and behind the bar, not sideways: this card belongs to a module
    // in the bar, and the bar is where it should come from and go back
    // to. Far enough that the shadow clears too.
    readonly property int slideDistance: panel.cardHeight + panel.inset + 24

    readonly property var player: Media.activePlayer

    function nudgeSeek(seconds) {
        if (!panel.player || !panel.player.canSeek || panel.player.length <= 0) return
        panel.player.position = Math.max(0, Math.min(panel.player.length,
            Media.position + seconds))
    }

    function stepVolume(delta) {
        if (!panel.player || !panel.player.volumeSupported) return
        panel.player.volume = Math.max(0, Math.min(1, panel.player.volume + delta))
    }

    // ── Pieces ───────────────────────────────────────────
    // They talk to Media.activePlayer directly (the same object as
    // panel.player): an inline component cannot see this file's ids.

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
        implicitWidth: 32
        implicitHeight: 32
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
            font.pixelSize: Theme.iconSize
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

    // shuffle, prev, play, next, repeat — five equal cells across the row.
    component TransportRow: RowLayout {
        id: row

        readonly property var player: Media.activePlayer

        spacing: Theme.space2

        TransportButton {
            // nf-md-shuffle_variant / shuffle_disabled
            glyph: row.player && row.player.shuffle ? "\u{f049d}" : "\u{f049e}"
            available: row.player !== null && row.player.shuffleSupported
            active: available && row.player.shuffle
            onActivated: row.player.shuffle = !row.player.shuffle
        }

        TransportButton {
            glyph: "\u{f04ae}"
            available: row.player !== null && row.player.canGoPrevious
            onActivated: row.player.previous()
        }

        TransportButton {
            primary: true
            glyph: row.player && row.player.isPlaying ? "\u{f03e4}" : "\u{f040a}"
            available: row.player !== null && row.player.canTogglePlaying
            onActivated: row.player.togglePlaying()
        }

        TransportButton {
            glyph: "\u{f04ad}"
            available: row.player !== null && row.player.canGoNext
            onActivated: row.player.next()
        }

        TransportButton {
            // nf-md-repeat / repeat_once / repeat_off; a click walks
            // off → playlist → track.
            glyph: !row.player ? "\u{f0457}"
                 : row.player.loopState === MprisLoopState.Track ? "\u{f0458}"
                 : row.player.loopState === MprisLoopState.Playlist ? "\u{f0456}"
                 : "\u{f0457}"
            available: row.player !== null && row.player.loopSupported
            active: available && row.player.loopState !== MprisLoopState.None
            onActivated: {
                const states = [MprisLoopState.None, MprisLoopState.Playlist, MprisLoopState.Track]
                const i = states.indexOf(row.player.loopState)
                row.player.loopState = states[(i + 1) % states.length]
            }
        }
    }

    // The art, square, masked to the card's radius. Masked rather
    // than clipped: a rounded Rectangle does not round what an Image
    // inside it paints.
    component ArtSquare: Rectangle {
        id: artBox

        Layout.preferredWidth: 136
        Layout.preferredHeight: 136
        Layout.alignment: Qt.AlignTop
        radius: Theme.radius
        color: Appearance.surfaceAlt

        Image {
            id: art
            anchors.fill: parent
            source: Media.activePlayer && Media.activePlayer.trackArtUrl ? Media.activePlayer.trackArtUrl : ""
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
            radius: artBox.radius
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            anchors.fill: parent
            source: art
            maskEnabled: true
            maskSource: artMask
            // A soft mask edge instead of the default hard cut-off,
            // which drops the antialiased corner pixels: at a 2px
            // radius that left the art fully square beside buttons
            // that visibly round.
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            visible: art.status === Image.Ready
        }

        // U+F001 (nf-fa-music), the same stand-in the volume rail's
        // stream rows wear when a client names no icon.
        Text {
            anchors.centerIn: parent
            text: "\u{f001}"
            color: Appearance.fgDim
            font.pixelSize: Theme.fontHuge
            font.family: Theme.font
            visible: art.status !== Image.Ready
        }
    }

    // Title on one line, then the artist in spaced caps.
    component TrackIdentity: ColumnLayout {
        id: ident

        readonly property var player: Media.activePlayer

        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: Theme.space1

        Text {
            text: ident.player ? (ident.player.trackTitle || "Unknown") : ""
            color: Appearance.fgStrong
            font.bold: true
            font.pixelSize: Theme.fontBig
            font.family: Theme.font
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
        }

        Text {
            text: ident.player ? (ident.player.trackArtist || "").toUpperCase() : ""
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

    // elapsed ──■──── length, on one line. Position is written directly
    // as seconds: a `position =` assignment routes to the player's
    // SetPosition (confirmed live against a real MPRIS session).
    component SeekRow: RowLayout {
        id: seek

        readonly property var player: Media.activePlayer

        visible: seek.player !== null && seek.player.length > 0
        Layout.fillWidth: true
        spacing: Theme.space2

        Text {
            text: Media.fmtTime(Media.position)
            color: Appearance.fgMuted
            font.pixelSize: Theme.fontTiny
            font.family: Theme.font
            horizontalAlignment: Text.AlignLeft
            Layout.preferredWidth: 28
        }

        FlatBar {
            Layout.fillWidth: true
            value: Media.progressFraction
            interactive: seek.player !== null && seek.player.canSeek
            onMoved: (v) => {
                if (seek.player && seek.player.canSeek && seek.player.length > 0)
                    seek.player.position = v * seek.player.length
            }
        }

        Text {
            text: seek.player ? Media.fmtTime(seek.player.length) : "0:00"
            color: Appearance.fgMuted
            font.pixelSize: Theme.fontTiny
            font.family: Theme.font
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 28
        }
    }

    // This player's own volume — not the sink, which the volume rail
    // owns. Only drawn for a player that supports it; MPRIS makes the
    // property optional.
    component VolumeRow: RowLayout {
        id: vol

        readonly property var player: Media.activePlayer

        visible: vol.player !== null && vol.player.volumeSupported
        Layout.fillWidth: true
        spacing: Theme.space2

        Text {
            text: "VOL"
            color: Appearance.fgMuted
            font.pixelSize: Theme.fontTiny
            font.family: Theme.font
            font.letterSpacing: 1
            Layout.preferredWidth: 28
        }

        FlatBar {
            Layout.fillWidth: true
            value: vol.player ? vol.player.volume : 0
            onMoved: (v) => { if (vol.player) vol.player.volume = v }
        }

        Text {
            text: Math.round((vol.player ? vol.player.volume : 0) * 100) + "%"
            color: Appearance.fgMuted
            font.pixelSize: Theme.fontTiny
            font.family: Theme.font
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 28
        }
    }

    // ‹ PLAYER › — only takes up space when there is something to
    // switch to.
    component PlayerSwitch: RowLayout {
        visible: Media.players.length > 1
        Layout.fillWidth: true
        spacing: Theme.space2

        Item { Layout.fillWidth: true }

        Text {
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
            text: Media.activePlayer ? Media.activePlayer.identity.toUpperCase() : ""
            color: Appearance.fgMuted
            font.pixelSize: Theme.fontSmall
            font.family: Theme.font
            font.letterSpacing: 1
            Layout.maximumWidth: 140
            elide: Text.ElideRight
        }

        Text {
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

        // ── Nothing playing ──────────────────────────
        // The bar module hides itself when no player exists, so the
        // usual way in is gone before this can be seen — but the IPC
        // target and its shortcut are not, and a card that opened empty
        // with no explanation would read as broken.
        Text {
            id: emptyText
            visible: !panel.player
            anchors.fill: parent
            anchors.margins: Theme.cardPadding
            text: "Nothing is playing"
            color: Appearance.fgDim
            font.pixelSize: Theme.fontSmall
            font.family: Theme.font
            elide: Text.ElideRight
        }

        ColumnLayout {
            id: body

            visible: panel.player !== null
            anchors.fill: parent
            anchors.margins: Theme.cardPadding
            spacing: Theme.space3

            PlayerSwitch {}

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space4

                ArtSquare {}

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    spacing: Theme.space2

                    TrackIdentity {}

                    Item { Layout.fillHeight: true }

                    SeekRow {}

                    TransportRow { Layout.fillWidth: true }

                    VolumeRow {}
                }
            }
        }
    }
}
