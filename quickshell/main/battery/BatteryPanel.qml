// The battery rail — the right-edge slide-out over power.
//
// The third of volume/VolumePanel.qml's shape and the fourth of the
// network rail's: a card held 8px off the screen edges it touches, the
// toasts' material and curves, and — like the volume rail, and unlike the
// two list rails — only as tall as what is in it. That fit matters more
// here than anywhere else, because what is in it is a few readings and
// the power profile switch.
//
// The charge is UPower.displayDevice, the aggregate: on this ThinkPad it
// combines BAT0 and BAT1 into one number, which is the one that answers
// "how long have I got". The two packs used to be listed under it; the
// user had that removed on 2026-09-28 as redundant with the header.
//
// Peripherals, when UPower has any, are rows in the volume rail's mixer
// shape (battery/BatteryDeviceRow.qml): a name, a faint line of detail,
// a bar.
//
// Colours come from theme/Appearance.qml rather than config/Theme.qml,
// like every surface written since the bento dashboard. Geometry, motion
// and the Hyprland frame still come from Theme/common so the card
// material is the toasts'.
import Quickshell
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
    // Also re-reads the charge limit — see Battery.maxChargeText.
    onSurfaceOpened: {
        Panels.claimRightRail("battery")
        Battery.refreshMaxCharge()
    }

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

        radius: Theme.radiusCard
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
            // The network rail's stat grid (network/WifiTab.qml), in its
            // colours and spacing since 2026-09-28 (user request): two
            // label/value pairs to a line instead of one InfoRow each.
            // A hidden pair drops out of the grid whole, so the rest
            // close up without leaving a gap.
            GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: Theme.space3
                rowSpacing: Theme.space1

                StatLabel { text: Battery.remainingLabel }
                StatValue { text: Battery.remainingText }
                StatLabel { text: Battery.charging ? "Charge rate" : "Draw" }
                StatValue { text: Battery.rateText }

                // Was "Power source", Battery or AC adapter; the state
                // says the same and more — "Not charging" is on AC too.
                // Green while taking or holding charge, as the power
                // source was on AC.
                StatLabel { text: "Battery State" }
                StatValue {
                    text: Battery.statusText
                    color: (Battery.charging || Battery.full) ? Appearance.green : Appearance.fg
                }
                // Where charging stops, if the kernel exposes it: a
                // charge limit is why "Not charging" can mean 80% on AC.
                StatLabel {
                    visible: Battery.maxChargeText !== ""
                    text: "Max Charge"
                }
                StatValue {
                    visible: Battery.maxChargeText !== ""
                    text: Battery.maxChargeText
                }

                // Hidden rather than dashed when the aggregate device has
                // no wear data — which is this machine, where the
                // composite carries none and each pack carries its own. A
                // dash reads as a fault rather than as "not reported", and
                // on a single-pack laptop, where the display device *is*
                // the battery, the figure is real and the pair is here.
                StatLabel {
                    visible: Battery.health > 0
                    text: "Health"
                }
                StatValue {
                    visible: Battery.health > 0
                    text: Battery.healthText
                }
            }

            // ── Power profile ────────────────────────────
            // The rail's one control, and the first thing on it you set
            // rather than read — which is why it comes after the
            // readings and not in the header. Hidden where
            // power-profiles-daemon isn't running (Battery.
            // profilesAvailable), like every other section here that
            // would otherwise be empty.
            Text {
                visible: Battery.profilesAvailable
                text: "Power profile"
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

            PowerProfileSwitch {
                visible: Battery.profilesAvailable
                Layout.fillWidth: true
            }

            // ── Peripherals ──────────────────────────────
            // No per-pack list above this (removed 2026-09-28, user
            // request): the combined charge in the header is the one the
            // user reads, and BAT0/BAT1 drawn again underneath it was
            // clutter.
            //
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
