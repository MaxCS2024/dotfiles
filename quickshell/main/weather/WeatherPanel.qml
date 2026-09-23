// The weather rail — the right-edge card behind bar/WeatherButton.qml.
//
// It replaced that module's hover dropdown (user request 2026-09-23), so
// weather opens the way the network, volume and battery modules beside it
// do: a click, a card from the right edge. The frame is battery/
// BatteryPanel.qml's, content-sized like it, and it takes the corner
// through Panels.claimRightRail like every rail does.
//
// What is in it is the dropdown's, as the user had trimmed it: the
// weather now as a header, then one row for four hours from now — no
// place name, no separator, no time on that row.
import Quickshell
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:weather"
    surfaceName: "weather"
    focusTarget: card

    // 400, the other rails' width.
    readonly property int cardWidth: 400

    // Room on the left of the card for its own shadow — see
    // battery/BatteryPanel.qml.
    readonly property int shadowPad: 24

    readonly property int cardPadding: 14

    readonly property int cardHeight: Math.min(
        panel.height - panel.inset * 2,
        body.implicitHeight + panel.cardPadding * 2)

    readonly property int slideDistance: panel.cardWidth + panel.inset + 24

    anchors { top: true; bottom: true; right: true }
    implicitWidth: panel.shadowPad + panel.cardWidth + panel.inset
    exclusiveZone: 0
    // Only the card takes clicks — see battery/BatteryPanel.qml, and
    // network/NetworkPanel.qml for why the mask is a still item rather
    // than the sliding card.
    mask: cardMask
    Region { id: cardMask; item: cardSlot }

    Item {
        id: cardSlot
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: panel.inset
        anchors.rightMargin: panel.inset
        width: panel.cardWidth
        height: panel.cardHeight

        // The later row comes and goes with the evening while the card
        // is up.
        Behavior on height {
            NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard }
        }
    }

    // Opening is also when a fetch is worth making: it is the moment
    // someone wants the numbers to be fresh. That was the old left click
    // on the bar module, which this card now answers instead.
    onSurfaceOpened: {
        Panels.claimRightRail("weather")
        Weather.refresh()
    }

    Connections {
        target: Panels
        // Another rail took the corner. See Panels.claimRightRail.
        function onRightRailClaimed(name) {
            if (name !== "weather") panel.close()
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

        anchors.fill: cardSlot

        radius: Theme.radius
        color: Appearance.surface
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
            anchors.margins: panel.cardPadding
            spacing: 12

            // ── Now ──────────────────────────────────────
            // The rails' header: the module's own glyph at fontHuge, a
            // title, one caption under it.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: Weather.now ? Weather.now.icon : ""
                    color: Appearance.fgStrong
                    font.pixelSize: Theme.fontHuge
                    font.family: Theme.font
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1

                    SectionTitle { text: Weather.now ? Weather.now.temp + "°" : "" }

                    // fgSoft, the rails' caption colour (see bar/Clock.qml
                    // for why not fgMuted).
                    Text {
                        text: Weather.now ? Weather.now.desc + " · feels like " + Weather.now.feels + "°" : ""
                        color: Appearance.fgSoft
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }
                }
            }

            // ── Four hours from now ──────────────────────
            RowLayout {
                visible: Weather.later !== null
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: Weather.later ? Weather.later.icon : ""
                    color: Appearance.fg
                    font.pixelSize: Theme.iconSize
                    font.family: Theme.font
                }

                Text {
                    text: Weather.later ? Weather.later.desc : ""
                    color: Appearance.fg
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                }

                Text {
                    text: Weather.later && Weather.later.rain > 0 ? Weather.later.rain + "% ☂" : ""
                    color: Appearance.fgMuted
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font
                }

                Text {
                    text: Weather.later ? Weather.later.temp + "°" : ""
                    color: Appearance.fgStrong
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font
                    horizontalAlignment: Text.AlignRight
                    Layout.minimumWidth: 28
                }
            }
        }
    }
}
