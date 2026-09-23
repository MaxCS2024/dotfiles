// The calendar — a card that hangs under the bar's clock.
//
// It replaces the hover dropdown bar/Clock.qml used to carry (user
// request 2026-09-21): a 26px month grid that opened on hover, could only
// page a month at a time, and answered to nothing but the pointer. This
// is the same surface the four rails are — a layer-shell card in the
// toasts' material, with a focus grab, Escape, and a height that is its
// content's — but it hangs from the middle of the bar instead of the
// right edge, because it belongs to the module that opens it.
//
// What "interactive" buys over the dropdown:
//   · a day can be selected, and the line under the grid says what was
//     selected — full date, ISO week, and whether it is today
//   · the grid is fully keyed: arrows walk days and weeks, PageUp/Down
//     walk months, Home returns to today, Enter picks in the year view
//   · the title is a button into a year view — twelve months at once,
//     with the year itself paged — so a date nine months out is two
//     clicks away rather than nine
//   · the days either side of the month are drawn rather than blanked,
//     and clicking one follows it into its own month
//
// Weeks start on Monday and carry ISO week numbers, which is both what
// this machine's country uses and what an ISO week number means at all.
// Day and month names come from arrays here rather than from
// Qt.formatDate: the system locale is en_US (LANG), so the formatter
// answers in English, and the clock this card hangs from has always
// hardcoded its own Swedish weekday for exactly that reason. One array
// each to change if the language should follow the locale instead.
import Quickshell
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:calendar"
    surfaceName: "calendar"
    focusTarget: card

    // ── Grid metrics ─────────────────────────────────────
    // Every one of these is a whole number, and the card's width is
    // derived from them rather than chosen — because the reverse (a round
    // 300px card with seven columns filling whatever was left) put the
    // cells on fractional widths, and a cell on a fractional width centres
    // its digit on a fractional pixel. The card renders into a texture for
    // its shadow (layer.enabled below), so anything landing off the pixel
    // grid is resampled rather than merely nudged: the whole card came out
    // visibly soft, which is what the user saw (2026-09-21).
    //
    // 8 children in a week row — the week-number gutter and seven days —
    // so seven gaps, not six.
    readonly property int dayCell: 34
    readonly property int daySpacing: 2
    readonly property int weekGutter: 24
    readonly property int gridWidth:
        panel.weekGutter + panel.dayCell * 7 + panel.daySpacing * 7

    readonly property int cardWidth: panel.gridWidth + Theme.cardPadding * 2
    // Room below and beside the card for its own shadow, which a
    // layer-shell surface clips like anything else.
    readonly property int shadowPad: 24

    // Content, plus the padding either side of it — the same contract as
    // volume/VolumePanel.qml and battery/BatteryPanel.qml, and the same
    // reason it doesn't loop: a ColumnLayout's implicitHeight comes from
    // its children, and nothing in `body` fills height.
    readonly property int cardHeight: body.implicitHeight + Theme.cardPadding * 2


    // Up and behind the bar, not sideways: this card belongs to a module
    // in the bar, and the bar is where it should come from and go back
    // to. Far enough that the shadow clears too.
    readonly property int slideDistance: panel.cardHeight + panel.inset + 24


    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ── The month on screen, and the day picked in it ────
    property int viewYear: clock.date.getFullYear()
    property int viewMonth: clock.date.getMonth()

    // Selection as three numbers rather than a Date: every move is
    // arithmetic on a fresh Date anyway (see shiftSelection), and three
    // integers compare without the equality traps a Date has.
    property int selYear: clock.date.getFullYear()
    property int selMonth: clock.date.getMonth()
    property int selDay: clock.date.getDate()

    // The title is a button into this: twelve months at once, the year
    // paged by the same two chevrons.
    property bool yearView: false

    // Swedish, like the weekday the bar's clock draws beside the time —
    // see the header. Indexed by Date.getDay(), Sunday first, which is
    // what getDay() returns; the *grid* is Monday-first, and converts.
    readonly property var dayNames: ["Söndag", "Måndag", "Tisdag", "Onsdag",
                                     "Torsdag", "Fredag", "Lördag"]
    readonly property var dayHeads: ["Må", "Ti", "On", "To", "Fr", "Lö", "Sö"]
    readonly property var monthNames: ["januari", "februari", "mars", "april",
                                       "maj", "juni", "juli", "augusti",
                                       "september", "oktober", "november", "december"]
    readonly property var monthHeads: ["Jan", "Feb", "Mar", "Apr", "Maj", "Jun",
                                       "Jul", "Aug", "Sep", "Okt", "Nov", "Dec"]

    // Swedish months are lower case in a sentence and look wrong as a
    // heading that way, so the title gets one capital and the detail line
    // under the grid keeps the sentence spelling.
    function monthTitle(m) {
        const name = panel.monthNames[m]
        return name.charAt(0).toUpperCase() + name.slice(1)
    }

    // Monday-first offset: Date.getDay() is Sunday-first, so Sunday's 0
    // becomes 6 and every other day drops one.
    function mondayOffset(y, m) {
        return (new Date(y, m, 1).getDay() + 6) % 7
    }

    // ISO 8601: the week containing this date's Thursday, counted from
    // the week containing the 4th of January — the only definition under
    // which week 1 is the week with the year's first Thursday in it.
    // UTC throughout so a DST boundary inside the month can't move a day
    // across midnight and shift the count.
    function isoWeek(date) {
        const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
        d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7) + 3)
        const jan4 = new Date(Date.UTC(d.getUTCFullYear(), 0, 4))
        jan4.setUTCDate(jan4.getUTCDate() - ((jan4.getUTCDay() + 6) % 7) + 3)
        return 1 + Math.round((d - jan4) / (7 * 24 * 3600 * 1000))
    }

    // The date in cell `index` of a 6x7 grid over the month on screen.
    // Always a real date, never a blank: the cells either side of the
    // month belong to the months either side of it, and this is what
    // lets them be drawn and clicked.
    function cellDate(index) {
        return new Date(panel.viewYear, panel.viewMonth,
                        index - panel.mondayOffset(panel.viewYear, panel.viewMonth) + 1)
    }

    function isToday(d) {
        const now = clock.date
        return d.getFullYear() === now.getFullYear()
            && d.getMonth() === now.getMonth()
            && d.getDate() === now.getDate()
    }

    function isSelected(d) {
        return d.getFullYear() === panel.selYear
            && d.getMonth() === panel.selMonth
            && d.getDate() === panel.selDay
    }

    readonly property bool onCurrentMonth:
        panel.viewMonth === clock.date.getMonth()
        && panel.viewYear === clock.date.getFullYear()

    readonly property date selectedDate: new Date(panel.selYear, panel.selMonth, panel.selDay)

    // Moving the view moves the selection with it, keeping the day of the
    // month where that day exists.
    //
    // It used to move the view alone, and the card then said two things at
    // once: paging back from 21 September left the grid on August with no
    // cell lit and the line underneath still reading "Måndag 21 september
    // · Idag" — a date that was neither on screen nor, once you were
    // looking at August, the one you were thinking about (found
    // 2026-09-21). The next arrow key made it worse by snapping the view
    // forward again to wherever the selection had been left.
    //
    // Clamped to the month's length, because the obvious way to write this
    // is `new Date(y, m + delta, selDay)` and that is a trap: JavaScript
    // rolls a 31st into the next month, so paging from 31 January lands on
    // 3 March.
    function viewTo(year, month) {
        const first = new Date(year, month, 1)
        const last = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()
        panel.select(new Date(first.getFullYear(), first.getMonth(),
                              Math.min(panel.selDay, last)))
    }

    function shiftMonth(delta) {
        panel.viewTo(panel.viewYear, panel.viewMonth + delta)
    }

    function shiftYear(delta) {
        panel.viewTo(panel.viewYear + delta, panel.viewMonth)
    }

    // Selecting a day is also how the view follows it: pick the 31st and
    // press Right and the card is on the next month, which is the whole
    // point of the days either side being real.
    function select(d) {
        panel.selYear = d.getFullYear()
        panel.selMonth = d.getMonth()
        panel.selDay = d.getDate()
        panel.viewYear = panel.selYear
        panel.viewMonth = panel.selMonth
    }

    function shiftSelection(days) {
        panel.select(new Date(panel.selYear, panel.selMonth, panel.selDay + days))
    }

    function goToToday() {
        panel.select(clock.date)
        panel.yearView = false
    }

    // A full-width strip under the bar, not the screen: the card hangs
    // from the top of it, and the height is the card's own plus the room
    // its shadow needs. exclusiveZone 0 reserves nothing and respects
    // what the bar reserves, which is what puts this strip's top edge
    // under the bar rather than behind it.
    anchors { top: true; left: true; right: true }
    implicitHeight: panel.inset + panel.cardHeight + panel.shadowPad

    exclusiveZone: 0
    mask: cardMask
    Region { id: cardMask; item: cardSlot }

    // The input region is taken from THIS, an empty item pinned where the
    // card comes to rest, and never from `card` itself, which carries the
    // slide-in Translate — network/NetworkPanel.qml has the full account
    // of what goes wrong when a mask item is being transformed.
    //
    // Centred on the clock rather than on the screen. Panels.clockAnchor
    // is where that module's middle sits across the bar, as a fraction,
    // published by bar/Clock.qml — the two surfaces are separate
    // layer-shell windows and neither can see the other's geometry, the
    // same reason Panels.rightRailWidth exists. Clamped to the inset so a
    // clock parked at either end still opens a card that is fully on
    // screen.
    Item {
        id: cardSlot
        anchors.top: parent.top
        anchors.topMargin: panel.inset
        width: panel.cardWidth
        height: panel.cardHeight
        // Rounded, and not only clamped: the anchor is a fraction of a bar
        // whose centre row can land on a half pixel, and an unrounded x
        // put every pixel of this card through a resample — see the grid
        // metrics above.
        x: Math.round(Math.max(panel.inset,
             Math.min(panel.width - panel.cardWidth - panel.inset,
                      Panels.clockAnchor * panel.width - panel.cardWidth / 2)))

        // The card changes height when the year view opens, when a month
        // needs a sixth week, and when the detail line wraps. Animated
        // for the same reason the slide is.
        Behavior on height {
            NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard }
        }
    }

    onSurfaceOpened: {
        // Every open is a fresh look at this month and this day: the card
        // is a glance surface, and where you paged to last time is not
        // where you want to land.
        panel.goToToday()
    }

    // Keeps the clock's hover pill lit while its card is up, which is
    // what the dropdown's own `visible` used to do for it.
    Binding {
        target: Panels
        property: "calendarShown"
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
            switch (event.key) {
            case Qt.Key_Escape:
                // One layer at a time, like the network rail's share
                // sheet: Escape out of the year view leaves the card up.
                if (panel.yearView) panel.yearView = false
                else panel.close()
                break
            case Qt.Key_Left:
                if (panel.yearView) panel.shiftYear(-1)
                else panel.shiftSelection(-1)
                break
            case Qt.Key_Right:
                if (panel.yearView) panel.shiftYear(1)
                else panel.shiftSelection(1)
                break
            case Qt.Key_Up:
                if (panel.yearView) panel.shiftYear(-1)
                else panel.shiftSelection(-7)
                break
            case Qt.Key_Down:
                if (panel.yearView) panel.shiftYear(1)
                else panel.shiftSelection(7)
                break
            case Qt.Key_PageUp:
                panel.shiftMonth(-1)
                break
            case Qt.Key_PageDown:
                panel.shiftMonth(1)
                break
            case Qt.Key_Home:
                panel.goToToday()
                break
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                // In the year view Enter takes the month being shown; in
                // the day view the title is what Enter opens, so the two
                // are each other's inverse.
                panel.yearView = !panel.yearView
                break
            default:
                return
            }
            event.accepted = true
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
            spacing: Theme.space2

            // ── Header ───────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                // The month, and a button into the year view. The chevron
                // beside it says it is one — a title that silently does
                // something on click is a title nobody clicks.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: 28
                    radius: Theme.radius
                    color: titleHover.hovered ? Appearance.hover : Appearance.clear(Appearance.hover)

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                    }

                    RowLayout {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.space1
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space2

                        SectionTitle {
                            text: panel.yearView ? panel.viewYear
                                : panel.monthTitle(panel.viewMonth) + " " + panel.viewYear
                        }

                        // U+F078 / U+F077 are nf-fa-chevron_down / _up:
                        // down to open the year view, up to fold it away.
                        Text {
                            text: panel.yearView ? "" : ""
                            color: Appearance.fgFaint
                            font.pixelSize: Theme.fontTiny
                            font.family: Theme.font
                        }
                    }

                    HoverHandler { id: titleHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.yearView = !panel.yearView
                    }
                }

                // Back, forward, and home — the same trio the dashboard's
                // calendar card carries, and the same glyphs. What they
                // step is the view: a month in the day view, a year in
                // the year view, which is what the chevrons are pointing
                // at in each case.
                Repeater {
                    model: [
                        { icon: "", delta: -1, home: false },
                        { icon: "", delta: 1, home: false },
                        // U+F00ED is nf-md-calendar_today, written as the
                        // literal glyph — a \u escape carries four hex
                        // digits and this is past the BMP.
                        { icon: "󰃭", delta: 0, home: true }
                    ]

                    delegate: Rectangle {
                        id: navButton
                        required property var modelData

                        // The way back appears only once there is
                        // somewhere to come back from.
                        visible: !navButton.modelData.home
                            || !panel.onCurrentMonth
                            || panel.yearView
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: Theme.radius
                        color: navHover.hovered ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong)
                        border.width: 1
                        border.color: Appearance.border

                        Behavior on color {
                            ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: navButton.modelData.icon
                            color: navHover.hovered ? Appearance.fgStrong : Appearance.fgSoft
                            font.pixelSize: Theme.fontTiny
                            font.family: Theme.font
                        }

                        HoverHandler { id: navHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (navButton.modelData.home) panel.goToToday()
                                else if (panel.yearView) panel.shiftYear(navButton.modelData.delta)
                                else panel.shiftMonth(navButton.modelData.delta)
                            }
                        }
                    }
                }
            }

            // ── Weekday heads ────────────────────────────
            RowLayout {
                visible: !panel.yearView
                Layout.fillWidth: true
                spacing: panel.daySpacing

                // The week-number gutter's own column, empty of a head —
                // "v" for vecka would be a fourth thing to read across a
                // row that is already seven.
                Item {
                    Layout.preferredWidth: panel.weekGutter
                    implicitHeight: 1
                }

                Repeater {
                    model: panel.dayHeads

                    delegate: Text {
                        required property string modelData
                        required property int index

                        text: modelData
                        // The weekend pair, dimmer than the working five
                        // — the one distinction a month grid is actually
                        // read for at a glance.
                        color: index >= 5 ? Appearance.fgDim : Appearance.fgMuted
                        font.pixelSize: Theme.fontMicro
                        font.family: Theme.font
                        horizontalAlignment: Text.AlignHCenter
                        Layout.preferredWidth: panel.dayCell
                    }
                }
            }

            // ── The month ────────────────────────────────
            ColumnLayout {
                visible: !panel.yearView
                Layout.fillWidth: true
                spacing: panel.daySpacing

                Repeater {
                    model: 6

                    delegate: RowLayout {
                        id: week
                        required property int index

                        readonly property date monday: panel.cellDate(week.index * 7)

                        // Six rows is the most any month can span once its
                        // first day is offset into the week, and most
                        // months don't. A row with no day of this month in
                        // it at all is dropped rather than drawn as a
                        // ghost week — a Layout skips an invisible child
                        // entirely, so the card comes up a row shorter
                        // instead of holding a blank band.
                        readonly property bool hasMonthDay: {
                            for (let i = 0; i < 7; i++)
                                if (panel.cellDate(week.index * 7 + i).getMonth() === panel.viewMonth)
                                    return true
                            return false
                        }

                        visible: week.hasMonthDay
                        Layout.fillWidth: true
                        spacing: panel.daySpacing

                        // The ISO week, in its own gutter. Taken from the
                        // Monday of the row, which is the day the whole
                        // row's week number belongs to.
                        Text {
                            text: panel.isoWeek(week.monday)
                            color: Appearance.fgFaint
                            font.pixelSize: Theme.fontMicro
                            font.family: Theme.font
                            horizontalAlignment: Text.AlignHCenter
                            Layout.preferredWidth: panel.weekGutter
                        }

                        Repeater {
                            model: 7

                            delegate: Rectangle {
                                id: day
                                required property int index

                                readonly property date date: panel.cellDate(week.index * 7 + day.index)
                                readonly property bool inMonth: day.date.getMonth() === panel.viewMonth
                                readonly property bool today: panel.isToday(day.date)
                                readonly property bool selected: panel.isSelected(day.date)
                                readonly property bool weekend: day.index >= 5

                                Layout.preferredWidth: panel.dayCell
                                Layout.preferredHeight: 28
                                radius: Theme.radius
                                // Today is a filled accent cell; a
                                // selection that isn't today is the
                                // half-accent ground every selected
                                // button in the shell uses.
                                color: day.today ? Appearance.accent
                                     : day.selected ? SlabStyle.tintSelected
                                     : dayHover.hovered ? Appearance.hover
                                     : Appearance.clear(Appearance.hover)

                                Behavior on color {
                                    ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                                }

                                // The three states are three grounds:
                                // today is the accent cell, a selection
                                // elsewhere is the half-accent ground,
                                // hover is the usual tint. The one cell
                                // that is both today and the selection has
                                // no fourth ground left, so it takes a
                                // ring instead.
                                border.width: day.today && day.selected ? 1 : 0
                                border.color: Appearance.fgStrong

                                Text {
                                    anchors.centerIn: parent
                                    text: day.date.getDate()
                                    // Against the filled accent cell the
                                    // panel's own ground is the only
                                    // reliably readable ink — fg would be
                                    // light on light on a pale palette.
                                    // Days outside the month stay legible
                                    // but recede.
                                    color: day.today ? Appearance.bar
                                         : !day.inMonth ? Appearance.fgDim
                                         : day.weekend ? Appearance.fgSoft
                                         : Appearance.fg
                                    font.pixelSize: Theme.fontSmall
                                    font.family: Theme.font
                                    font.bold: day.today
                                }

                                HoverHandler { id: dayHover }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    // Clicking a day outside this month
                                    // follows it into its own, which is
                                    // the other half of drawing them at
                                    // all.
                                    onClicked: panel.select(day.date)
                                }
                            }
                        }
                    }
                }
            }

            // ── The year ─────────────────────────────────
            GridLayout {
                visible: panel.yearView
                Layout.fillWidth: true
                columns: 3
                rowSpacing: Theme.space1
                // 3 cells and 2 gaps across the same gridWidth the month
                // uses, chosen so the division is exact: 3*90 + 2*3 = 276.
                columnSpacing: 3

                Repeater {
                    model: panel.monthHeads

                    delegate: Rectangle {
                        id: monthCell
                        required property string modelData
                        required property int index

                        readonly property bool current:
                            monthCell.index === clock.date.getMonth()
                            && panel.viewYear === clock.date.getFullYear()
                        readonly property bool showing: monthCell.index === panel.viewMonth

                        Layout.preferredWidth: (panel.gridWidth - 6) / 3
                        Layout.preferredHeight: 34
                        radius: Theme.radius
                        color: monthCell.current ? Appearance.accent
                             : monthCell.showing ? SlabStyle.tintSelected
                             : monthHover.hovered ? Appearance.hover
                             : Appearance.clear(Appearance.hover)

                        Behavior on color {
                            ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: monthCell.modelData
                            color: monthCell.current ? Appearance.bar : Appearance.fg
                            font.pixelSize: Theme.fontSmall
                            font.family: Theme.font
                            font.bold: monthCell.current
                        }

                        HoverHandler { id: monthHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                panel.viewTo(panel.viewYear, monthCell.index)
                                panel.yearView = false
                            }
                        }
                    }
                }
            }

            // ── The day that is picked ───────────────────
            // What the grid can't say in a cell: the whole date, the week
            // it falls in, and — only when it is true — that it is today.
            // Hidden in the year view, where nothing is picked yet.
            Rectangle {
                visible: !panel.yearView
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: 32
                radius: Theme.radius
                color: Appearance.surfaceAlt

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space2
                    anchors.rightMargin: Theme.space2
                    spacing: Theme.space2

                    Text {
                        text: panel.dayNames[panel.selectedDate.getDay()] + " "
                            + panel.selDay + " " + panel.monthNames[panel.selMonth]
                            + " " + panel.selYear
                        color: Appearance.fg
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "v " + panel.isoWeek(panel.selectedDate)
                        color: Appearance.fgFaint
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.font
                    }

                    Text {
                        visible: panel.isToday(panel.selectedDate)
                        text: "Idag"
                        color: Appearance.accent
                        font.pixelSize: Theme.fontTiny
                        font.family: Theme.font
                        font.bold: true
                    }
                }
            }
        }
    }
}
