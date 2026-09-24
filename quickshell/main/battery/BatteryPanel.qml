// The battery rail — the right-edge slide-out over power.
//
// The third of volume/VolumePanel.qml's shape and the fourth of the
// network rail's: a card held 8px off the screen edges it touches, the
// toasts' material and curves, and — like the volume rail, and unlike the
// two list rails — only as tall as what is in it. That fit matters more
// here than anywhere else, because what is in it is four readings on a
// machine with one pack and a second section on a machine with two.
//
// What it says that the bar and quicksettings/BatteryTab.qml cannot: the
// packs. UPower.displayDevice is an aggregate, and on this ThinkPad it
// averages BAT0 and BAT1 into one percentage that can be a long way from
// either of them — 48% while one sat at 16% and the other at 80%. The
// number at the top of this card is still that average, because it is the
// one that answers "how long have I got"; the section under it is where
// the average comes from. See services/Battery.qml's `packs`, which is
// also why the list is populated before this window is ever built.
//
// The mixer in the volume rail is the model for those rows, deliberately:
// a name, a faint line of detail, a bar. A pack and a playback stream are
// nothing alike, but "one of several things, each with a level" is the
// same row, and this shell should draw it the same way twice.
//
// Colours come from theme/Appearance.qml rather than config/Theme.qml,
// like every surface written since the bento dashboard. Geometry, motion
// and the Hyprland frame still come from Theme/common so the card
// material is the toasts'.
import Quickshell
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:battery"
    surfaceName: "battery"
    focusTarget: card

    // 400, the volume and notification rails' width. Nothing here is
    // wider than a device name beside a percentage.
    readonly property int cardWidth: 400

    // Room on the left of the card for its own shadow, which a
    // layer-shell surface clips like anything else — the same pad, for
    // the same reason, as the toast stack's.
    readonly property int shadowPad: 24

    // Content, plus the padding either side of it, capped at the column
    // the bar leaves. See volume/VolumePanel.qml for why this doesn't
    // loop: a ColumnLayout's implicitHeight comes from its children, not
    // from its own height, and nothing in `body` fills height.
    readonly property int cardHeight: Math.min(
        panel.height - panel.inset * 2,
        body.implicitHeight + Theme.cardPadding * 2)

    // Far enough that the card *and* its shadow are past the screen edge.
    readonly property int slideDistance: panel.cardWidth + panel.inset + 24

    // A strip, not the screen. Anchored top and bottom so the *available*
    // height is whatever the bar leaves — which is only the cap on
    // `cardHeight`, not the card.
    anchors { top: true; bottom: true; right: true }
    implicitWidth: panel.shadowPad + panel.cardWidth + panel.inset
    exclusiveZone: 0
    // Only the card takes clicks, so the shadow gutter beside it and the
    // column below it stay click-through — the same idiom the toast stack
    // and the OSDs use, and the same reason the volume rail gives for
    // caring about it: a content-sized card leaves most of this strip
    // empty, and every pixel of that belongs to what is behind it.
    mask: cardMask
    Region { id: cardMask; item: cardSlot }

    // The input region is taken from THIS, an empty item pinned where the
    // card comes to rest, and never from `card` itself, which carries the
    // slide-in Translate — network/NetworkPanel.qml has the full account
    // of what goes wrong when a mask item is being transformed.
    Item {
        id: cardSlot
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: panel.inset
        anchors.rightMargin: panel.inset
        width: panel.cardWidth
        height: panel.cardHeight

        // The height changes while the card is up — a charger goes in and
        // the caption gains a time, a second pack starts charging and its
        // state line changes width. Animated for the same reason the
        // slide is.
        Behavior on height {
            NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard }
        }
    }

    // Claim the corner. Why these four are exclusive, and why the rail
    // that loses the claim closes itself rather than being closed, is
    // Panels.claimRightRail's to explain.
    onSurfaceOpened: Panels.claimRightRail("battery")

    Connections {
        target: Panels
        // Another rail took the corner. See Panels.claimRightRail.
        function onRightRailClaimed(name) {
            if (name !== "battery") panel.close()
        }

    }

    // Tells the toast stack how much of the right edge to keep clear —
    // see Panels.rightRailWidth.
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
        // construction.
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
        HyprFrame {
            frameWidth: card.border.width
            targetRadius: card.radius
        }

        ColumnLayout {
            id: body

            anchors.fill: parent
            anchors.margins: Theme.cardPadding
            spacing: Theme.space3

            // ── Header ───────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                // Battery.icon, the glyph bar/BatteryButton wears in the
                // bar, in the colour it wears there — so the button you
                // pressed and the card it opened are showing you the same
                // mark, and the one that already turns orange at 25% and
                // red at 10%. fontHuge and inert, like every rail badge.
                Text {
                    text: Battery.icon
                    color: Battery.fillColor
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

                    // The charge, not the word "Battery" — the same call
                    // the other rails make with the SSID and the output
                    // device. It is the number you opened this to read,
                    // and it is the aggregate one on purpose: two packs
                    // discharge as one machine, and "how long have I got"
                    // has a single answer even where "how full is it"
                    // has two.
                    SectionTitle { text: Math.round(Battery.percentage) + "%" }

                    // The caption the other rails keep for the one fact
                    // under the title. Status and the time it implies,
                    // joined only when there is a time to give: UPower
                    // reports 0 for both directions in the minutes after
                    // a charger moves, and "Charging · —" is worse than
                    // "Charging".
                    Text {
                        text: {
                            const time = Battery.remainingText
                            const suffix = Battery.charging ? " to full" : " left"
                            return time === "—" ? Battery.statusText
                                : Battery.statusText + " · " + time + suffix
                        }
                        // fgSoft rather than fgMuted — muted reads too dim
                        // to be a caption under a name (see bar/Clock.qml).
                        // The exception is the state the whole card is
                        // about: under 25% the caption takes the icon's
                        // own warning colour.
                        color: Battery.discharging && Battery.percentage <= 25
                             ? Battery.fillColor : Appearance.fgSoft
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }
                }
            }

            // The charge as a bar, which quicksettings/BatteryTab.qml
            // draws beside a huge percentage and this draws under one.
            // A Slider with no knob and nothing interactive about it:
            // the shell's one track shape, so a battery reads like a
            // volume level rather than like a second kind of meter.
            Slider {
                Layout.fillWidth: true
                trackHeight: 8
                value: Math.max(0, Math.min(1, Battery.percentage / 100))
                trackColor: Appearance.trackBg
                fillColor: Battery.fillColor
            }

            // ── Readings ─────────────────────────────────
            // BatteryTab's four rows, in its order. Status is dropped —
            // it is in the caption above, where the tab has no caption to
            // put it in.
            InfoRow {
                label: Battery.remainingLabel
                value: Battery.remainingText
                labelColor: Appearance.fgMuted
                valueColor: Appearance.fg
            }
            InfoRow {
                label: Battery.charging ? "Charge rate" : "Draw"
                value: Battery.rateText
                labelColor: Appearance.fgMuted
                valueColor: Appearance.fg
            }
            // Hidden rather than dashed when the aggregate device has no
            // wear data — which is this machine, where the composite
            // carries none and each pack carries its own. A row reading
            // "Health —" over a list that says 80% and 88% is worse than
            // no row, and on a single-pack laptop, where the display
            // device *is* the battery, the figure is real and the row is
            // here.
            InfoRow {
                visible: Battery.health > 0
                label: "Health"
                value: Battery.healthText
                labelColor: Appearance.fgMuted
                valueColor: Appearance.fg
            }
            InfoRow {
                label: "Power source"
                value: UPower.onBattery ? "Battery" : "AC adapter"
                labelColor: Appearance.fgMuted
                valueColor: UPower.onBattery ? Appearance.fg : Appearance.green
            }

            // ── Packs ────────────────────────────────────
            // Only when there are two or more. One pack is what the
            // header already is, drawn a second time in a smaller font —
            // and this card is meant to stop where its content stops.
            //
            // Capitals and tracking, the section-label shape the network
            // rail settled on (2026-09-18).
            Text {
                visible: Battery.packs.length > 1
                text: "Batteries"
                color: Appearance.fg
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Theme.tracking(Theme.fontSmall, 0.12)
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 2
                elide: Text.ElideRight
            }

            // A Repeater and not a ListView, unlike the volume rail's two
            // lists: a machine has two battery bays, or one, and never so
            // many that a row cap and a scrollbar would earn their
            // complication. The rows are the mixer's shape all the same.
            ColumnLayout {
                visible: Battery.packs.length > 1
                Layout.fillWidth: true
                spacing: Theme.space1

                Repeater {
                    model: Battery.packs

                    delegate: BatteryDeviceRow {
                        required property var modelData
                        Layout.fillWidth: true
                        device: modelData
                    }
                }
            }

            // ── Peripherals ──────────────────────────────
            // A mouse, a keyboard, a headset — whatever else UPower knows
            // a charge for. Nothing on this machine has ever appeared
            // here; the section is hidden rather than empty, which is
            // also what keeps an untested list from taking space on a
            // card that has none to spare.
            Text {
                visible: Battery.peripherals.length > 0
                text: "Devices"
                color: Appearance.fg
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Theme.tracking(Theme.fontSmall, 0.12)
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 2
                elide: Text.ElideRight
            }

            ColumnLayout {
                visible: Battery.peripherals.length > 0
                Layout.fillWidth: true
                spacing: Theme.space1

                Repeater {
                    model: Battery.peripherals

                    delegate: BatteryDeviceRow {
                        required property var modelData
                        Layout.fillWidth: true
                        device: modelData
                    }
                }
            }

        }
    }
}
