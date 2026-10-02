// The earbuds card — hangs under the bar's earbuds module.
//
// Left bud, right bud and the case, each a ring filled to its charge with
// the part drawn in the middle (earbuds/EarbudRing.qml). The readings are
// services/Earbuds.qml's. The case only reports with a bud in it and the
// lid open, so its ring appears once it has said something this connection
// and stays, as "last seen", after it goes quiet.
//
// Its own card rather than a section of the battery rail (user request
// 2026-09-24): with both, the bar's earbuds and battery modules opened the
// same rail. Geometry and motion are media/MediaPanel.qml's — a card in
// the toasts' material hanging from the module that opens it, placed by
// the fraction that module publishes (Panels.earbudsAnchor).
import Quickshell
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:earbuds"
    surfaceName: "earbuds"
    focusTarget: card

    readonly property var parts: {
        const out = [
            { kind: "left", title: "Left", part: Earbuds.left },
            { kind: "right", title: "Right", part: Earbuds.right }
        ]
        if (Earbuds.caseBattery !== null)
            out.push({ kind: "case", title: "Case", part: Earbuds.caseBattery })
        return out
    }

    // Each ring sits in a cell a little wider than itself so "last seen"
    // under it has room; the card is as wide as its rings.
    readonly property int ringCell: 88
    readonly property int cardWidth: panel.parts.length * panel.ringCell
        + (panel.parts.length - 1) * Theme.space4 + Theme.cardPadding * 2
    readonly property int cardHeight: body.implicitHeight + Theme.cardPadding * 2

    // Room below and beside the card for its own shadow.
    readonly property int shadowPad: 24
    readonly property int slideDistance: panel.cardHeight + panel.inset + 24

    // The earbuds going away takes the card with them: there is nothing
    // left for it to be about, and the module that opened it is gone.
    Connections {
        target: Earbuds
        function onReadyChanged() {
            if (!Earbuds.ready) panel.close()
        }
    }

    anchors { top: true; left: true; right: true }
    implicitHeight: panel.inset + panel.cardHeight + panel.shadowPad

    exclusiveZone: 0
    mask: cardMask
    Region { id: cardMask; item: cardSlot }

    // Pinned where the card comes to rest, for the input region — see
    // network/NetworkPanel.qml on why the mask is never the moving card.
    // Rounded for the calendar's reason: the card renders into a texture
    // for its shadow, and an x on a half pixel is resampled.
    Item {
        id: cardSlot
        anchors.top: parent.top
        anchors.topMargin: panel.inset
        width: panel.cardWidth
        height: panel.cardHeight
        x: Math.round(Math.max(panel.inset,
             Math.min(panel.width - panel.cardWidth - panel.inset,
                      Panels.earbudsAnchor * panel.width - panel.cardWidth / 2)))

        // A third ring when the case first reports.
        Behavior on width {
            NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard }
        }
    }

    Binding {
        target: Panels
        property: "earbudsShown"
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
        HyprFrame {
            frameWidth: card.border.width
            targetRadius: card.radius
        }

        ColumnLayout {
            id: body

            anchors.fill: parent
            anchors.margins: Theme.cardPadding
            spacing: Theme.space4

            SectionTitle {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: Earbuds.name || "Earbuds"
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.space4

                Repeater {
                    model: panel.parts

                    delegate: EarbudRing {
                        required property var modelData
                        Layout.preferredWidth: panel.ringCell
                        kind: modelData.kind
                        title: modelData.title
                        part: modelData.part
                    }
                }
            }
        }
    }
}
