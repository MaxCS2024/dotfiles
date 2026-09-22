import Quickshell
import QtQuick
import "../config"
import "../theme"
import "../services"

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
    // cannot reach is the one bar surface SUPER+B skips (found
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
    // the bar's width — what the calendar card centres itself on, since
    // it is a separate layer-shell surface that cannot see this one's
    // geometry (see Panels.clockAnchor).
    //
    // `root.x`, `root.width` and the bar's width are read into `moved`
    // and otherwise unused on purpose: mapToItem is a function call, not
    // a tracked binding dependency, so without naming the geometry this
    // expression depends on it would be evaluated once and then never
    // again — and a clock moved to the left or right row would open its
    // card wherever it happened to be at startup.
    readonly property real anchorFraction: {
        const bw = root.barWindow
        if (!bw || bw.width <= 0) return 0.5
        const moved = root.x + root.width + bw.width
        return root.mapToItem(bw.contentItem, root.width / 2, 0).x / bw.width
    }

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
        implicitWidth: row.implicitWidth + 22
        implicitHeight: row.implicitHeight + 6
        // Lit while the calendar is up, which is what `dropdown.visible`
        // did for this pill before the card replaced the dropdown.
        active: hover.hovered || Panels.calendarShown || root.keyboardFocused
        anchors.centerIn: parent

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6

            Text {
                id: weekdayText
                anchors.verticalCenter: parent.verticalCenter
                text: root.weekdayLabel
                // Appearance.fg, not fgMuted: muted read too dim against
                // the time beside it. That call is why quicksettings/ and
                // systemsettings/ point back at this note; it survived the
                // stint as a fixed white that bar/HoverPill.qml describes.
                color: Appearance.fg
                font.pixelSize: Theme.fontBig
                font.family: Theme.font
            }

            Text {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: Appearance.fg
                font.pixelSize: Theme.fontBig
                font.family: Theme.font
            }
        }
    }

    HoverHandler { id: hover }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.tapped()
    }
}
