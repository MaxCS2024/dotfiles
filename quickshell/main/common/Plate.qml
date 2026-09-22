import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../config"

// The shared popout-plate recipe every popout surface builds on:
// one card (ground, border, radius, elevation, optional header) so each
// surface only ever declares its own rows. "Rows are separated by
// hairlines, never by fills" is a convention for those rows,
// not something this component can enforce — it only draws the header's
// own hairline; each surface adds its own `Divider {}` between rows the
// same way it already did under `DropdownPanel`.
Rectangle {
    id: root

    // Ink ground (`#191715`@96%) is the power-menu variant;
    // every other popout stays on the paper ground (`Theme.plateBg`,
    // `#f7f6f5` — lighter than the bar's own `Theme.surface`).
    property bool ink: false
    // Docked (anchored under the bar module that opened it) vs floating
    // (centred overlays like the launcher) — the design specifies
    // genuinely different elevation for the two, not the same shadow at a
    // different size.
    property bool floating: false
    // 10px all-small-caps header with a hairline underneath — the
    // recipe repeated for every popout in the mockup (Quick settings,
    // Audio mixer, Networks, Bluetooth, Now playing, Clipboard). Leave
    // empty for a surface with its own bespoke top row instead (e.g. the
    // calendar's month/year line).
    property string header: ""

    default property alias content: body.data
    readonly property alias body: body
    readonly property bool hovered: hoverHandler.hovered

    implicitWidth: body.implicitWidth + Theme.platePaddingH * 2
    implicitHeight: column.implicitHeight + Theme.platePaddingV * 2

    color: root.ink ? Theme.plateBgInk : Theme.plateBg
    radius: Theme.radiusLarge
    border.width: 1
    border.color: root.ink ? Theme.plateBorderInk : Theme.border

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: root.floating ? Theme.shadowColor : Theme.shadowColorDocked
        shadowBlur: root.floating ? Theme.shadowBlurPopup : Theme.shadowBlurDocked
        shadowVerticalOffset: root.floating ? Theme.shadowVerticalOffsetPopup : Theme.shadowVerticalOffsetDocked
        shadowHorizontalOffset: 0
    }

    HoverHandler { id: hoverHandler }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.leftMargin: Theme.platePaddingH
        anchors.rightMargin: Theme.platePaddingH
        anchors.topMargin: Theme.platePaddingV
        anchors.bottomMargin: Theme.platePaddingV
        spacing: 0

        ColumnLayout {
            visible: root.header !== ""
            Layout.fillWidth: true
            spacing: Theme.plateHeaderGap

            Text {
                text: root.header
                Layout.fillWidth: true
                color: root.ink ? Theme.fgHeaderInk : Theme.fgHeader
                font.family: Theme.fontHeading
                font.pixelSize: Theme.fontTiny
                font.capitalization: Font.SmallCaps
                font.letterSpacing: Theme.tracking(Theme.fontTiny, 0.16)
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: root.ink ? Theme.dividerInk : Theme.separator
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.topMargin: root.header !== "" ? Theme.plateHeaderGap : 0
            spacing: Theme.space2
        }
    }
}
