import QtQuick
import QtQuick.Layouts
import "../config"

// One editable entry in the themes card's palette editor (theme/
// ThemesPanel.qml): label, live swatch, hex field, and — for the tokens
// that have a fallback — an auto/reset control.
//
// Lived beside systemsettings/SettingsAppearanceTab.qml until the
// settings panel was deleted (2026-09-21) and the editor moved into the
// card, which is now the only surface that switches or edits a palette.
//
// "Derivable" entries are the ones Appearance.qml next door can work out
// on its own (Surface/Border off customBg, the status colors off Theme), so
// their override is clearable back to "": the hex field then goes faint
// and keeps tracking whatever the derivation produces. Background, Text
// and Accent are what everything else is derived *from* and have nothing
// to fall back to, so they're always pinned.
RowLayout {
    id: row

    property string label: ""
    // Live value to show in the swatch — the resolved token, so a
    // derivable row's swatch follows Background as you edit it.
    property color resolved: "transparent"
    // The override as stored: "#rrggbb", or "" when running on the
    // derived default.
    property string overrideHex: ""
    property bool derivable: true

    readonly property bool overridden: row.overrideHex !== ""
    readonly property string displayHex:
        row.overridden ? row.overrideHex : Appearance.toHex(row.resolved)
    readonly property var hexPattern: /^#[0-9a-fA-F]{6}$/

    signal edited(string hex)
    signal cleared

    spacing: 8

    // The field's text is assigned rather than bound: typing into a
    // TextInput overwrites `text` and would break a binding for good,
    // which for a derivable row means it stops tracking Background. The
    // activeFocus guard keeps a refresh from eating what's being typed.
    onDisplayHexChanged: if (!hexField.activeFocus) hexField.text = row.displayHex
    Component.onCompleted: hexField.text = row.displayHex

    Text {
        text: row.label
        color: Appearance.fg
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
        Layout.preferredWidth: 78
    }

    Rectangle {
        implicitWidth: 22
        implicitHeight: 22
        radius: Theme.radius
        color: row.resolved
        border.color: Appearance.border
        border.width: 1
    }

    Rectangle {
        Layout.preferredWidth: 96
        implicitHeight: 22
        radius: Theme.radius
        color: Appearance.surfaceAlt
        border.color: hexField.activeFocus ? Appearance.accent : Appearance.border
        border.width: 1

        TextInput {
            id: hexField
            anchors.fill: parent
            anchors.margins: 5
            // Faint while the value is only derived — the field still
            // shows a real hex, but it isn't one you've chosen.
            color: row.overridden ? Appearance.fg : Appearance.fgFaint
            font.pixelSize: Theme.fontSmall
            font.family: Theme.font
            clip: true
            selectByMouse: true

            onEditingFinished: {
                if (row.hexPattern.test(hexField.text))
                    row.edited(hexField.text.toLowerCase())
                else
                    hexField.text = row.displayHex
            }
        }
    }

    // Held at full width even when there's nothing to show, so every
    // row's fields line up — a hidden item would drop out of the layout.
    Item {
        Layout.preferredWidth: 38
        implicitHeight: 22
        opacity: row.derivable ? 1 : 0
        enabled: row.derivable && row.overridden

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: row.overridden ? "reset" : "auto"
            color: !row.overridden ? Appearance.fgDim
                 : (resetHover.hovered ? Appearance.accent : Appearance.fgSoft)
            font.pixelSize: Theme.fontTiny
            font.family: Theme.font
        }

        HoverHandler { id: resetHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: row.cleared()
        }
    }
}
