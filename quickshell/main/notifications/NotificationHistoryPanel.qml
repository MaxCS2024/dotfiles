// The notification rail — the right-edge slide-out over the history.
//
// Geometry, motion and material are network/NetworkPanel.qml's, because
// the two are the same kind of surface: a card held 8px off the screen
// edges it touches, which is the overhang notifications/
// NotificationPopups.qml has always had against Hyprland's `gaps_out` of
// 15 (hypr/modules/decorations.lua) — a toast, and now a rail, overhangs
// the tiled window column by 7px and reads as part of the desktop's
// furniture rather than of the tiling grid.
//
// It differs from the network rail in two ways, both because of what it
// holds. It runs the full column between the bar and the screen floor
// rather than three fifths of it: the network rail is a fixed set of
// readings that stops where it stops, and this is one list that is worth
// exactly as many rows as the screen will give it. And the surface is a
// strip the width of the card rather than the whole screen — the network
// rail went full-screen so its QR sheet could centre itself on the
// monitor, and nothing here needs to leave the card.
//
// Rows are notifications/NotificationHistoryRow.qml, the same delegate
// quicksettings/NotificationsTab.qml and dashboard/
// DashboardNotifications.qml draw, deliberately not restyled for the
// rail: a notification looks the same wherever this shell shows it.
//
// Colours come from theme/Appearance.qml rather than config/Theme.qml,
// like every surface written since the bento dashboard — it falls
// through to the same Theme tokens by default but also honours a pinned
// custom palette. Geometry, motion and the Hyprland frame still come
// from Theme/common so the card material is the toasts'.
import Quickshell
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:notifications"
    surfaceName: "notification-history"
    focusTarget: card

    // 400, where the network rail is 450 and a toast is 320. The rail's
    // extra width is paying for SSIDs that elide in the middle; a
    // notification body wraps to two lines and then stops, so the width
    // only has to be comfortable rather than generous.
    readonly property int cardWidth: 400

    // Room on the left of the card for its own shadow, which a
    // layer-shell surface clips like anything else — the same pad, for
    // the same reason, as the toast stack's. Nothing is needed on the
    // right: that edge is the screen's, and the card is held `inset` off
    // it, which is already more than the blur reaches.
    readonly property int shadowPad: 24

    // Far enough that the card *and* its shadow are past the screen edge.
    readonly property int slideDistance: panel.cardWidth + panel.inset + 24

    // A strip, not the screen. Anchored top and bottom so the height is
    // whatever the bar leaves (exclusiveZone 0 reserves nothing and
    // respects what the bar reserves), and the width is ours to state.
    anchors { top: true; bottom: true; right: true }
    implicitWidth: panel.shadowPad + panel.cardWidth + panel.inset
    exclusiveZone: 0
    // Only the card takes clicks, so the shadow gutter beside it stays
    // click-through — the same idiom the toast stack and the OSDs use.
    mask: cardMask
    Region { id: cardMask; item: cardSlot }

    // The input region is taken from THIS, an empty item pinned where the
    // card comes to rest, and never from `card` itself, which carries the
    // slide-in Translate. A mask whose item is being transformed leaves
    // the compositor and Qt disagreeing about where the surface accepts
    // input, and the failure is specific and ugly: a click during the
    // slide reaches the QML scene while Hyprland treats it as landing
    // outside the grabbed surface and clears the grab, closing the rail
    // under the pointer. network/NetworkPanel.qml has the full account —
    // it was found there, and this is the shape that fixed it.
    Item {
        id: cardSlot
        anchors.fill: parent
        anchors.leftMargin: panel.shadowPad
        anchors.topMargin: panel.inset
        anchors.rightMargin: panel.inset
        anchors.bottomMargin: panel.inset
    }

    // Claim the corner. Why these four are exclusive, and why the rail
    // that loses the claim closes itself rather than being closed, is
    // Panels.claimRightRail's to explain.
    //
    // Opening the list is also reading it: that was the rule the quick
    // settings tab and the dashboard card kept before both were deleted
    // on 2026-09-21, and this is the surface that inherited it. It
    // clears the bar's unread badge, which is the thing that sent you
    // here.
    onSurfaceOpened: {
        Panels.claimRightRail("notificationHistory")
        Notifications.markAllSeen()
    }

    Connections {
        target: Panels
        // Another rail took the corner. See Panels.claimRightRail.
        function onRightRailClaimed(name) {
            if (name !== "notificationHistory") panel.close()
        }

    }

    // Tells the toast stack how much of the right edge to keep clear —
    // see Panels.rightRailWidth. Tied to `shown`, not to `visible`, so
    // the toasts start moving back as the rail begins sliding out rather
    // than after it has gone. A new notification arriving while the
    // history is open is the ordinary case here, not the rare one the
    // network rail was written for.
    Binding {
        target: Panels
        property: "rightRailWidth"
        value: panel.inset + panel.cardWidth
        when: panel.shown
    }

    Rectangle {
        id: card

        // Fills cardSlot above, so the drawn card and the region this
        // surface claims for input are the same rectangle by
        // construction — the overhang geometry is stated once, up there.
        anchors.fill: cardSlot

        radius: Theme.radius
        color: Appearance.surface
        // 2px to match Hyprland's own `border_size`, exactly as a toast
        // does — the colour here is what shows if HyprFrame is hidden.
        border.width: Theme.hyprBorderWidth
        border.color: Appearance.border
        clip: true

        focus: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                panel.close()
                event.accepted = true
            }
        }

        opacity: panel.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: panel.shown ? panel.enterDuration : panel.exitDuration
                easing.type: panel.shown ? Theme.easingDecel : Easing.InCubic
            }
        }

        // Translate rather than `x`, so the slide never argues with the
        // anchors about where the card belongs — the same reason the
        // toast slots translate instead of moving.
        transform: Translate {
            x: panel.shown ? 0 : panel.slideDistance
            Behavior on x {
                NumberAnimation {
                    duration: panel.shown ? panel.enterDuration : panel.exitDuration
                    easing.type: panel.shown ? Theme.easingDecel : Easing.InCubic
                }
            }
        }

        layer.enabled: true
        layer.effect: PopupShadow {}
        // The Hyprland window border (common/HyprFrame.qml), declared
        // first so everything else paints over it — a toast, the network
        // rail and the Conf menu all wear this same ring.
        HyprFrame {
            frameWidth: card.border.width
            targetRadius: card.radius
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            // ── Header ───────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // U+F0F3 is nf-fa-bell, the glyph bar/
                // NotificationsButton wears in the bar — so the button you
                // pressed and the card it opened are showing you the same
                // mark. It follows DND the way that button does, since a
                // rail opened while nothing can reach the screen should
                // say so at the top rather than only in the switch at the
                // other end of the row.
                //
                // A badge standing beside the whole header, rather than a
                // glyph on the title's own line at the title's own size
                // (user request 2026-09-18). The network rail made the
                // opposite call and says so in its own header — but what
                // it was avoiding is a mark competing with an SSID for a
                // row that also carries three controls. This title is one
                // fixed word that will never elide, and the thing worth
                // recognising at the top of this card is the bell.
                //
                // fontHuge, which is the size the dashboard card draws its
                // own empty-state bell at, and about the height of the two
                // text lines it now stands beside.
                Text {
                    text: Settings.dnd ? "\uf1f6" : "\uf0f3"
                    color: Settings.dnd ? Appearance.orange : Appearance.fgStrong
                    font.pixelSize: Theme.fontHuge
                    font.family: Theme.font
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1

                    SectionTitle { text: "Notifications" }

                    // The caption under the title, the same slot the
                    // network rail keeps for the one fact you opened it
                    // to learn. Here that is how much there is, and —
                    // because the switch at the end of this row is
                    // unlabelled, like the airplane switch it is modelled
                    // on — this line is also the only thing that names
                    // Do Not Disturb once it is on.
                    //
                    // No unread count: open() marks the history seen, so
                    // by the time this is readable everything in it is
                    // read. The bar's badge is where unread lives.
                    Text {
                        text: Settings.dnd ? "Do not disturb"
                            : Notifications.history.length === 0 ? "Nothing waiting"
                            : Notifications.history.length === 1 ? "1 notification"
                            : Notifications.history.length + " notifications"
                        // fgSoft rather than fgMuted — muted reads too dim
                        // to be a caption under a name (see bar/Clock.qml).
                        color: Settings.dnd ? Appearance.orange : Appearance.fgSoft
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }
                }

                // Clear the history. Hidden rather than disabled on an
                // empty list: a dimmed button over "Nothing waiting" is
                // saying the same thing twice, and the empty state below
                // already says it better.
                //
                // U+F1F8 is nf-fa-trash, as in the dashboard card's own
                // clear control. Danger tones, because this is the one
                // thing on the card that destroys something — a row's
                // own close glyph takes one notification away, this takes
                // all hundred.
                Rectangle {
                    visible: Notifications.history.length > 0
                    implicitWidth: 26
                    implicitHeight: 24
                    radius: Theme.radius
                    color: clearHover.hovered ? Appearance.dangerBg : "transparent"
                    border.width: 1
                    // Neutral at rest, danger only under the pointer. The
                    // quick settings tab outlines its Clear button red the
                    // whole time, which works in a row of two buttons and
                    // not here: beside an unlabelled switch, a permanently
                    // red edge is the loudest thing on a card whose job is
                    // the list underneath it.
                    border.color: clearHover.hovered ? Appearance.dangerBorder : Appearance.border

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "\uf1f8"
                        color: clearHover.hovered ? Appearance.red : Appearance.fgSoft
                        font.pixelSize: Theme.fontMedium
                        font.family: Theme.font

                        Behavior on color {
                            ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                        }
                    }

                    HoverHandler { id: clearHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifications.clearHistory()
                    }
                }

                // Do Not Disturb, a switch for the reason airplane mode
                // is one in the network rail: the button beside it does
                // something once and is finished, this puts the session
                // into a state and leaves it there. A switch says that at
                // rest, not only for the moment after it is pressed.
                //
                // Last in the row, and unlabelled — the title glyph and
                // the caption above both answer to it, which is more than
                // a word beside it would add.
                ToggleSwitch {
                    checked: Settings.dnd
                    trackOffColor: Appearance.trackBg
                    trackOnColor: Appearance.accent
                    borderColor: Appearance.border
                    knobColor: Appearance.fgStrong
                    onToggled: Notifications.toggleDnd()
                }
            }

            // ── History ──────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: Notifications.history.length > 0
                spacing: 4

                ListView {
                    id: historyList

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: Notifications.history
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: NotificationHistoryRow {
                        id: histRow
                        required property var modelData

                        width: ListView.view.width
                        entry: histRow.modelData
                        onRemoveRequested: Notifications.removeHistoryEntry(histRow.modelData.id)
                    }
                }

                ListScrollBar {
                    view: historyList
                    Layout.fillHeight: true
                    trackColor: Appearance.scrollTrack
                    thumbColor: Appearance.scrollThumb
                }
            }

            // The empty state, taking the list's place rather than
            // sitting under it, so the card doesn't hold a hundred rows
            // of blank column above one line of text. Wording and glyph
            // are the dashboard card's — the same absence should read the
            // same way in both places.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: Notifications.history.length === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: "\uf0f3"
                        color: Appearance.fgDim
                        font.pixelSize: Theme.fontHuge
                        font.family: Theme.font
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "All caught up"
                        color: Appearance.fgDim
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

        }
    }
}
