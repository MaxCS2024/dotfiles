// The power profile, as the battery rail's one control — saver, balanced,
// performance, set through power-profiles-daemon.
//
// Quickshell's PowerProfiles singleton rather than shelling out to
// `relay power set`: relay's own header says ppd is the backend worth
// having precisely because a widget can read the same state off D-Bus,
// and this is that widget. Writing `PowerProfiles.profile` is the same
// polkit-authorised call `powerprofilesctl set` makes, so no password,
// and a change made from a terminal shows up here without polling.
//
// The shape is the network rail's tab track (network/NetworkPanel.qml),
// deliberately: one of three, picked by a `selected` plate that slides
// behind the labels. A profile is not a tab, but "exactly one of these
// few is current" is the same control, and this shell should draw it
// the same way twice.
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"

ColumnLayout {
    id: root

    spacing: Theme.space2

    // In ladder order, least power to most, and PowerProfile's own enum
    // is in the same order — so while all three are offered, a profile's
    // value is also its slot. Performance is left out on hardware that
    // has no such profile (ppd reports it), rather than drawn as a
    // segment that does nothing.
    readonly property var profiles: PowerProfiles.hasPerformanceProfile
        ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
        : [PowerProfile.PowerSaver, PowerProfile.Balanced]
    readonly property int current: root.profiles.indexOf(PowerProfiles.profile)

    function label(p) {
        switch (p) {
        case PowerProfile.PowerSaver: return "Power saver"
        case PowerProfile.Balanced: return "Balanced"
        case PowerProfile.Performance: return "Performance"
        }
        return PowerProfile.toString(p)
    }

    // The marks GNOME's own profile picker settled on: a leaf, a
    // balance, a speedometer (Nerd Font md-leaf, md-scale-balance,
    // md-speedometer).
    function icon(p) {
        switch (p) {
        case PowerProfile.PowerSaver: return "󰌪"
        case PowerProfile.Balanced: return "󰗑"
        case PowerProfile.Performance: return "󰓅"
        }
        return ""
    }

    // Taller than the network rail's tabs (user request 2026-09-28): this
    // is the rail's one control, and each segment now carries an icon
    // beside its label.
    readonly property int segmentHeight: 40

    Rectangle {
        id: track
        Layout.fillWidth: true
        implicitHeight: root.segmentHeight + 2 * track.pad
        radius: Theme.radius
        color: Appearance.trackBg
        border.width: 1
        border.color: Appearance.border

        readonly property int pad: Theme.space1

        // Behind the Repeater, so it paints under the labels. Placed by
        // arithmetic on the slot for the reason the network rail gives:
        // itemAt() doesn't notify, and the segments are equal width.
        Rectangle {
            readonly property real slot: (row.width - row.spacing * (segments.count - 1)) / Math.max(1, segments.count)
            visible: root.current >= 0
            x: row.x + Math.max(0, root.current) * (slot + row.spacing)
            y: row.y
            width: slot
            height: row.height
            radius: Theme.radius
            color: Appearance.selected

            Behavior on x {
                NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingDecel }
            }
        }

        RowLayout {
            id: row
            anchors.fill: parent
            anchors.margins: track.pad
            spacing: track.pad

            Repeater {
                id: segments
                model: root.profiles

                delegate: Rectangle {
                    id: segment
                    required property int index
                    required property var modelData

                    readonly property bool active: root.current === segment.index

                    Layout.fillWidth: true
                    implicitHeight: root.segmentHeight
                    radius: Theme.radius
                    color: !segment.active && hover.hovered
                        ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong)

                    readonly property color ink: segment.active ? Appearance.fgStrong : Appearance.fgSoft

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                    }

                    // Icon and label in the label's colour: the plate is
                    // the one signal for "current" (STYLE §8), so the
                    // glyph doesn't turn accent on top of it.
                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.space2

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.icon(segment.modelData)
                            color: segment.ink
                            font.pixelSize: Theme.iconSize
                            font.family: Theme.font
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.label(segment.modelData)
                            color: segment.ink
                            font.pixelSize: Theme.fontNormal
                            font.family: Theme.font
                        }
                    }

                    HoverHandler { id: hover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PowerProfiles.profile = segment.modelData
                    }
                }
            }
        }
    }

    // ppd keeps the profile at performance but tells the firmware to
    // back off when the machine is on a lap or running hot. Without a
    // word here the segment says Performance while the machine isn't
    // giving it, so the reason goes under the track — only while it
    // applies to the profile that's actually picked.
    Text {
        visible: PowerProfiles.profile === PowerProfile.Performance
              && PowerProfiles.degradationReason !== PerformanceDegradationReason.None
        text: "Held back: " + (PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected
              ? "on your lap" : "running hot")
        color: Appearance.fgSoft
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        elide: Text.ElideRight
    }
}
