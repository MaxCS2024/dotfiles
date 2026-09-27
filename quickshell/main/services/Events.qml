pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../common/localBin.js" as LocalBin

// GNOME Calendar's events, for calendar/CalendarPanel.qml.
//
// They live in evolution-data-server, which GNOME Calendar is only a face
// on, and `relay calendar` (relay/lib/calendar.py) reads and writes them
// there — so what is added in the card shows in the app and the other way
// round, and an online calendar added in the app shows here too (user
// request 2026-09-28).
//
// Nothing is kept running: the card asks for the six weeks its grid shows
// each time it opens or pages, and the answer replaces what was here. The
// first ask after login starts EDS's calendar factory, so it can take a
// second or two; the grid draws at once and the marks arrive after.
//
// An optional feature (services/Features.qml, `rack features`): off, or
// on with EDS missing (relay exits 127), there are no events and the card
// draws no event list at all.
Singleton {
    id: root

    readonly property bool wanted: Features.on("calendar")
    // EDS answered at least once. False until then, and after a 127.
    property bool present: false
    readonly property bool available: root.wanted && root.present

    // [{ source, calendar, uid, rid, title, allDay, start, end, recurring }]
    // as relay prints them; see relay/lib/calendar.py.
    property var events: []
    // "YYYY-MM-DD" -> the events on that day, sorted as `events` is.
    property var _byDay: ({})

    property string error: ""
    property bool busy: listProc.running || editProc.running

    // The range last asked for, so an add or a delete can ask again.
    property string _from: ""
    property string _to: ""
    property bool _again: false

    function key(d) {
        const pad = n => (n < 10 ? "0" : "") + n
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
    }

    function on(d) { return root._byDay[root.key(d)] || [] }
    function has(d) { return root._byDay[root.key(d)] !== undefined }

    // Events over [from, to), both Dates. A second ask while one is out is
    // held and made when the first answers, so paging fast ends on the
    // month in view rather than the first one asked for.
    function load(from, to) {
        if (!root.wanted) return
        root._from = root.key(from)
        root._to = root.key(to)
        if (listProc.running) {
            root._again = true
            return
        }
        listProc.command = LocalBin.argv("relay", ["calendar", "list", root._from, root._to])
        listProc.running = true
    }

    function reload() {
        if (root._from !== "") root.load(root._date(root._from), root._date(root._to))
    }

    // TEXT as the card's add line takes it ("14:00 Tandläkare", or a
    // title alone for all day); relay/lib/calendar.py reads it.
    function add(day, text) {
        root._edit(["calendar", "add", root.key(day), text])
    }

    function remove(event) {
        const args = ["calendar", "delete", event.source, event.uid]
        if (event.rid) args.push(event.rid)
        root._edit(args)
    }

    // GNOME Calendar itself, for everything the card doesn't do.
    function openApp() {
        Quickshell.execDetached(["gnome-calendar"])
    }

    function _edit(args) {
        if (editProc.running) return
        root.error = ""
        editProc.command = LocalBin.argv("relay", args)
        editProc.running = true
    }

    function _date(k) {
        const [y, m, d] = k.split("-").map(Number)
        return new Date(y, m - 1, d)
    }

    // Each event under every day it touches. A timed event that ends on
    // the stroke of midnight doesn't touch the day after; an all-day end
    // is already exclusive, so it doesn't either.
    function _index(events) {
        const byDay = {}
        for (const ev of events) {
            const first = root._date(ev.start.slice(0, 10))
            let last = root._date(ev.end.slice(0, 10))
            if (ev.allDay || ev.end.slice(11) === "00:00") last.setDate(last.getDate() - 1)
            if (last < first) last = first
            // A month and a half is more than the grid can show.
            for (let d = new Date(first), n = 0; d <= last && n < 42; d.setDate(d.getDate() + 1), n++) {
                const k = root.key(d)
                if (!byDay[k]) byDay[k] = []
                byDay[k].push(ev)
            }
        }
        return byDay
    }

    onWantedChanged: {
        if (root.wanted) {
            root.reload()
        } else {
            root.events = []
            root._byDay = ({})
        }
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            id: listOut
        }
        stderr: StdioCollector {
            id: listErr
        }
        onExited: (exitCode) => {
            if (exitCode === 0) {
                try {
                    const events = JSON.parse(listOut.text)
                    root.events = events
                    root._byDay = root._index(events)
                    root.present = true
                } catch (e) {
                    console.warn("Events: unreadable answer from relay calendar list:", e)
                }
            } else {
                root.present = exitCode !== 127 && root.present
                if (exitCode !== 127) console.warn("Events: relay calendar list:", listErr.text.trim())
            }
            if (root._again) {
                root._again = false
                root.reload()
            }
        }
    }

    Process {
        id: editProc
        stderr: StdioCollector {
            id: editErr
        }
        onExited: (exitCode) => {
            // relay's own words, less its "calendar: " prefix.
            if (exitCode !== 0) root.error = editErr.text.trim().replace(/^calendar:\s*/, "") || "Kunde inte spara"
            root.reload()
        }
    }
}
