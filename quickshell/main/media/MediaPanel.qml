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
//   · the whole thing is keyable — space plays, arrows seek and walk
//     players, and Escape closes
//   · an elapsed time that advances (services/Media.qml's `position`
//     explains why the dropdown's did not)
//   · art at 96px rather than 64, which is the point of having a card
//     rather than a tooltip
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

    // 380: wider than the 280 dropdown it replaces, because the art grew
    // and a track title deserves more than one word per line, and still
    // narrower than the 400 rails — nothing here is a list.
    readonly property int cardWidth: 380

    readonly property int cardPadding: 14

    // Room below and beside the card for its own shadow, which a
    // layer-shell surface clips like anything else.
    readonly property int shadowPad: 24

    // Content, plus the padding either side of it — the same contract as
    // calendar/CalendarPanel.qml and volume/VolumePanel.qml, and the same
    // reason it doesn't loop: a ColumnLayout's implicitHeight comes from
    // its children, and nothing in `body` fills height.
    readonly property int cardHeight: body.implicitHeight + panel.cardPadding * 2

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
            anchors.margins: panel.cardPadding
            spacing: 10

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

            // ── Identity ─────────────────────────────────
            RowLayout {
                visible: panel.player !== null
                Layout.fillWidth: true
                spacing: 12

                // 96, where the dropdown's was 64. The art is the one
                // thing on this card that is worth the room a card has
                // and a tooltip does not.
                Rectangle {
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: 96
                    Layout.alignment: Qt.AlignTop
                    radius: Theme.radiusMedium
                    color: Appearance.surfaceAlt

                    // Masked rather than clipped: a rounded Rectangle does
                    // not round what an Image inside it paints, so the art
                    // would square off the corners the card just rounded.
                    // Both sources are invisible on their own and exist
                    // only to feed the effect.
                    Image {
                        id: art
                        anchors.fill: parent
                        source: panel.player && panel.player.trackArtUrl ? panel.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                        layer.enabled: true
                    }

                    Rectangle {
                        id: artMask
                        anchors.fill: parent
                        radius: Theme.radiusMedium
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
                        text: ""
                        color: Appearance.fgDim
                        font.pixelSize: Theme.fontHuge
                        font.family: Theme.font
                        visible: art.status !== Image.Ready
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    spacing: 2

                    // Wrapped rather than elided, up to two lines: the
                    // pill in the bar already shows a one-line title and
                    // scrolls it, and a card that repeats that exactly is
                    // not worth opening. Past two lines it elides, so a
                    // podcast episode titled like a sentence cannot push
                    // the transport row off the card.
                    Text {
                        text: panel.player ? (panel.player.trackTitle || "Unknown") : ""
                        color: Appearance.fgStrong
                        font.bold: true
                        font.pixelSize: Theme.fontBig
                        font.family: Theme.font
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Text {
                        text: panel.player ? (panel.player.trackArtist || "") : ""
                        color: Appearance.fgSoft
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                        visible: text !== ""
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }

                    Text {
                        text: panel.player ? (panel.player.trackAlbum || "") : ""
                        color: Appearance.fgMuted
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.font
                        visible: text !== ""
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }
                }
            }

            // ── Player switch ────────────────────────────
            // Only takes up space when there is actually something to
            // switch to, exactly as in the dropdown.
            RowLayout {
                Layout.fillWidth: true
                visible: Media.players.length > 1
                spacing: 8

                Text {
                    text: ""
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
                    text: panel.player ? panel.player.identity : ""
                    color: Appearance.fgMuted
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    text: ""
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

            // ── Seek ─────────────────────────────────────
            // Position is written directly as an absolute value (seconds)
            // rather than via seek() — confirmed live against a real MPRIS
            // session that a direct `position =` assignment routes to the
            // player's SetPosition, and seconds is the right unit for both
            // (Quickshell normalizes MPRIS's native microseconds either
            // way; also confirmed live).
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                visible: panel.player && panel.player.length > 0

                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    // Grows under the pointer: a hover target that visibly
                    // widens reads as "this is draggable" before you have
                    // clicked it.
                    height: seekArea.containsMouse ? 6 : 4
                    radius: height / 2
                    color: Appearance.fgDim

                    Behavior on height {
                        NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                    }

                    Rectangle {
                        width: parent.width * Media.progressFraction
                        height: parent.height
                        radius: parent.radius
                        color: Appearance.accent
                    }
                }

                MouseArea {
                    id: seekArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: panel.player && panel.player.canSeek
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                    onPressed: (mouse) => panel.seekToFraction(mouse.x / width)
                    onPositionChanged: (mouse) => {
                        if (pressed) panel.seekToFraction(mouse.x / width)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: panel.player && panel.player.length > 0

                Text {
                    text: Media.fmtTime(Media.position)
                    color: Appearance.fgSoft
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.font
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: panel.player ? Media.fmtTime(panel.player.length) : "0:00"
                    color: Appearance.fgSoft
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.font
                }
            }

            // ── Transport ────────────────────────────────
            // Three orbs: a filled accent one for play/pause, and quieter
            // filled ones for prev/next either side. Shuffle and loop used
            // to share this row and were dropped by user request
            // (2026-09-23); the player's own controls still have them.
            RowLayout {
                visible: panel.player !== null
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 14

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: width / 2
                    color: transportPrevTap.containsMouse ? Appearance.selected : Appearance.hover
                    scale: transportPrevTap.pressed ? 0.94 : 1

                    Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingDecel } }

                    Text {
                        anchors.centerIn: parent
                        color: (panel.player && !panel.player.canGoPrevious)
                            ? Appearance.disabled : Appearance.fg
                        font.pixelSize: Theme.iconSize
                        font.family: Theme.font
                        text: "\u{f04ae}"
                    }

                    MouseArea {
                        id: transportPrevTap
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: panel.player && panel.player.canGoPrevious
                        onClicked: panel.player.previous()
                    }
                }

                Rectangle {
                    implicitWidth: 42
                    implicitHeight: 42
                    radius: width / 2
                    color: transportPlayTap.containsMouse
                        ? Qt.lighter(Appearance.accent, 1.12) : Appearance.accent
                    scale: transportPlayTap.pressed ? 0.94 : 1

                    Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingDecel } }

                    Text {
                        anchors.centerIn: parent
                        color: Appearance.bar
                        font.pixelSize: Theme.fontLarge
                        font.family: Theme.font
                        text: panel.player && panel.player.isPlaying ? "\u{f03e4}" : "\u{f040a}"
                    }

                    MouseArea {
                        id: transportPlayTap
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: panel.player && panel.player.canTogglePlaying
                        onClicked: panel.player.togglePlaying()
                    }
                }

                Rectangle {
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: width / 2
                    color: transportNextTap.containsMouse ? Appearance.selected : Appearance.hover
                    scale: transportNextTap.pressed ? 0.94 : 1

                    Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingDecel } }

                    Text {
                        anchors.centerIn: parent
                        color: (panel.player && !panel.player.canGoNext)
                            ? Appearance.disabled : Appearance.fg
                        font.pixelSize: Theme.iconSize
                        font.family: Theme.font
                        text: "\u{f04ad}"
                    }

                    MouseArea {
                        id: transportNextTap
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: panel.player && panel.player.canGoNext
                        onClicked: panel.player.next()
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
