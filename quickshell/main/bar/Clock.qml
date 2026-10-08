import Quickshell
import QtQuick
import "../config"
import "../theme"
import "../services"
import "../common/popupAnchor.js" as PopupAnchor

// The time in the bar, and the thing that opens the calendar.
//
// It carried its own month grid in a hover DropdownPanel until
// 2026-09-21, when the user asked for that to go and for a real calendar
// in its place: calendar/CalendarPanel.qml, a click away, which can be
// paged by month and by year, walked with the arrow keys and read for an
// ISO week. All the date arithmetic that used to live here went with it.
Item {
    id: root

    property var barWindow

    // bar/Bar.qml builds its roving-focus order from the
    // modules that declare this property (see BarModuleLoader's
    // `keyboardNavigable`), and Enter there fires the focused module's
    // `tapped()`. Neither existed here while a click on the clock did
    // nothing; now that it opens the calendar, a module the keyboard
    // cannot reach is the one bar surface SUPER+SHIFT+B skips (found
    // 2026-09-21). Both are what BarButton declares, for the same reason.
    property bool keyboardFocused: false

    signal tapped()
    onTapped: Panels.toggle("calendar")

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    // Wakes on the minute boundary. No `date` subprocess, no drift.
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property var swedishWeekdays: ["Söndag", "Måndag", "Tisdag", "Onsdag", "Torsdag", "Fredag", "Lördag"]
    readonly property string weekdayLabel: root.swedishWeekdays[clock.date.getDay()]

    // Where this module's middle sits across the bar, as a fraction of
    // its width, for the calendar card to centre on (common/popupAnchor.js).
    readonly property real anchorFraction: PopupAnchor.centreFraction(root, root.barWindow) ?? 0.5

    Binding {
        target: Panels
        property: "clockAnchor"
        value: root.anchorFraction
        when: root.barWindow !== null
    }

    HoverPill {
        id: pill
        // Was "+ 16" — see bar/BarButton.qml's note on the same bump,
        // made when HoverPill went fully round.
        implicitWidth: row.implicitWidth + 2 * Theme.barItemPadX
        implicitHeight: Theme.barItemHeight
        // Lit while the calendar is up, which is what `dropdown.visible`
        // did for this pill before the card replaced the dropdown.
        active: hover.hovered || Panels.calendarShown || root.keyboardFocused
        anchors.centerIn: parent

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Theme.space2

            Text {
                id: weekdayText
                anchors.verticalCenter: parent.verticalCenter
                text: root.weekdayLabel
                // Appearance.fg, not fgMuted: muted read too dim against
                // the time beside it. That call is why network/
                // NetworkPanel.qml points back at this note; it survived
                // the stint as a fixed white that bar/HoverPill.qml
                // describes.
                color: Appearance.fg
                font.pixelSize: Theme.fontBig
                font.family: Theme.font
                font.weight: Font.DemiBold
            }

            Text {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: Appearance.fg
                font.pixelSize: Theme.fontBig
                font.family: Theme.font
                font.weight: Font.DemiBold
            }
        }
    }

    HoverHandler { id: hover }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.tapped()
    }
}
