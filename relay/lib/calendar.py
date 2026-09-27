#!/usr/bin/env python3
"""Events from evolution-data-server, the store GNOME Calendar keeps them in.

Run through `relay calendar` (calendar.sh next door); the shell's
services/Calendar.qml is what reads it.

    calendar.py list FROM TO        every event overlapping [FROM, TO)
    calendar.py add DATE TEXT       one event on DATE, in the default calendar
    calendar.py delete SOURCE UID [RID]
    calendar.py parse DATE TEXT     what `add` would make of TEXT, without EDS

Dates are YYYY-MM-DD, times local. `list` prints one JSON array, sorted by
start, all-day events first on their day:

    [{"source": "system-calendar", "calendar": "Personal",
      "uid": "…", "rid": "", "title": "Tandläkare", "allDay": false,
      "start": "2026-09-28T14:00", "end": "2026-09-28T15:00",
      "recurring": false}]

An all-day event's start and end are dates, the end exclusive the way
iCalendar has it: a one-day event on the 28th ends on the 29th. A repeating
event is listed once per occurrence, each with its own `rid`, and `delete`
with a rid removes that occurrence alone.

TEXT is how the card's add line is typed: a time or a time range first makes
a timed event, anything else an all-day one.

    14:00 Tandläkare         14:00–15:00 (an hour when no end is given)
    9.30-10 Möte             09:30–10:00
    22-01 Nattåg             22:00 to 01:00 the next day
    Mammas födelsedag        all day

A bare hour ("14 Tandläkare") is not a time: a title can start with a number.

Every enabled calendar is listed, local or online; `add` writes to the one
EDS calls the default, which is "Personal" (on this computer) until GNOME
Calendar is told otherwise.

Exit status: 0, 1 when EDS cannot be reached or refuses, 2 on a usage error,
127 when python-gobject or EDS's typelibs are missing.
"""

import json
import re
import sys
from datetime import date, datetime, timedelta, timezone

TIME = r"(\d{1,2})(?:[:.](\d{2}))?"
TIMED = re.compile(r"^" + TIME + r"(?:\s*[-–]\s*" + TIME + r")?\s+(\S.*)$")

# How long an event with a start and no end lasts.
DEFAULT_LENGTH = timedelta(hours=1)

# Seconds to wait for a calendar's backend to come up. The first ask after
# login starts evolution-calendar-factory, which takes a moment.
CONNECT_TIMEOUT = 15


def usage(message):
    print(f"calendar: {message}", file=sys.stderr)
    sys.exit(2)


def parse_date(text):
    try:
        return date.fromisoformat(text)
    except ValueError:
        usage(f"not a date (YYYY-MM-DD): {text}")


def parse_text(day, text):
    """TEXT on DAY -> {title, allDay, start, end}, the shape `list` prints."""
    text = text.strip()
    m = TIMED.match(text)
    if m:
        h1, m1, h2, m2, title = m.groups()
        # A time needs minutes or a range; "14 Tandläkare" stays a title.
        if m1 is not None or h2 is not None:
            h1, m1 = int(h1), int(m1 or 0)
            ok = h1 < 24 and m1 < 60
            if h2 is not None:
                h2, m2 = int(h2), int(m2 or 0)
                ok = ok and h2 < 24 and m2 < 60
            if ok:
                start = datetime.combine(day, datetime.min.time()).replace(hour=h1, minute=m1)
                if h2 is None:
                    end = start + DEFAULT_LENGTH
                else:
                    end = start.replace(hour=h2, minute=m2)
                    if end <= start:
                        end += timedelta(days=1)
                return {"title": title.strip(), "allDay": False,
                        "start": start.strftime("%Y-%m-%dT%H:%M"),
                        "end": end.strftime("%Y-%m-%dT%H:%M")}
    return {"title": text, "allDay": True,
            "start": day.isoformat(), "end": (day + timedelta(days=1)).isoformat()}


# ── EDS ──────────────────────────────────────────────────────────────

def eds():
    try:
        import gi
        gi.require_version("ECal", "2.0")
        gi.require_version("EDataServer", "1.2")
        gi.require_version("ICalGLib", "3.0")
        from gi.repository import ECal, EDataServer, ICalGLib
    except (ImportError, ValueError) as e:
        print(f"calendar: evolution-data-server is not installed ({e})", file=sys.stderr)
        sys.exit(127)
    return ECal, EDataServer, ICalGLib


def registry(EDataServer):
    return EDataServer.SourceRegistry.new_sync(None)


def connect(ECal, source):
    return ECal.Client.connect_sync(source, ECal.ClientSourceType.EVENTS, CONNECT_TIMEOUT, None)


def local(t):
    """An ICalTime -> a naive local datetime, or a date for an all-day time."""
    if t.is_date():
        return date(t.get_year(), t.get_month(), t.get_day())
    zone = t.get_timezone()
    if zone is None and not t.is_utc():
        # Floating: the same wall-clock time wherever you are.
        return datetime(t.get_year(), t.get_month(), t.get_day(),
                        t.get_hour(), t.get_minute(), t.get_second())
    epoch = t.as_timet_with_zone(zone)
    return datetime.fromtimestamp(epoch)


def stamp(value):
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%dT%H:%M")
    return value.isoformat()


def epoch(day):
    return int(datetime.combine(day, datetime.min.time()).timestamp())


def list_events(first, last):
    ECal, EDataServer, ICalGLib = eds()
    reg = registry(EDataServer)
    events = []
    for source in reg.list_enabled(EDataServer.SOURCE_EXTENSION_CALENDAR):
        try:
            client = connect(ECal, source)
        except Exception as e:
            # One calendar that can't be reached (an online one, offline)
            # shouldn't hide the others.
            print(f"calendar: skipping {source.get_display_name()}: {e}", file=sys.stderr)
            continue

        def found(icomp, start, end, *rest):
            s, e = local(start), local(end)
            all_day = not isinstance(s, datetime)
            if end is None or e is None or e <= s:
                e = s + (timedelta(days=1) if all_day else timedelta(0))
            rid = icomp.get_recurrenceid()
            has_rid = rid is not None and not rid.is_null_time()
            recurring = has_rid or icomp.get_first_property(ICalGLib.PropertyKind.RRULE_PROPERTY) is not None
            if not recurring:
                rid_text = ""
            elif has_rid:
                rid_text = rid.as_ical_string()
            else:
                # An occurrence is named by where it starts.
                rid_text = start.as_ical_string()
            events.append({
                "source": source.get_uid(),
                "calendar": source.get_display_name(),
                "uid": icomp.get_uid(),
                "rid": rid_text,
                "title": icomp.get_summary() or "",
                "allDay": all_day,
                "start": stamp(s),
                "end": stamp(e),
                "recurring": recurring,
            })
            return True

        client.generate_instances_sync(epoch(first), epoch(last), None, found)

    # All-day first on a day, then by time; an all-day's "2026-09-28"
    # sorts before any "2026-09-28T…".
    events.sort(key=lambda ev: (ev["start"], ev["title"].lower()))
    print(json.dumps(events, ensure_ascii=False))


def ical_utc(stamp_text):
    t = datetime.strptime(stamp_text, "%Y-%m-%dT%H:%M").astimezone(timezone.utc)
    return t.strftime("%Y%m%dT%H%M%SZ")


def add(day, text):
    event = parse_text(day, text)
    if not event["title"]:
        usage("an event needs a title")
    ECal, EDataServer, ICalGLib = eds()
    reg = registry(EDataServer)
    source = reg.ref_default_calendar()
    if source is None:
        print("calendar: EDS has no default calendar", file=sys.stderr)
        sys.exit(1)

    if event["allDay"]:
        dtstart = "DTSTART;VALUE=DATE:" + event["start"].replace("-", "")
        dtend = "DTEND;VALUE=DATE:" + event["end"].replace("-", "")
    else:
        # UTC, so the event needs no VTIMEZONE of its own; GNOME Calendar
        # shows it in local time like any other.
        dtstart = "DTSTART:" + ical_utc(event["start"])
        dtend = "DTEND:" + ical_utc(event["end"])
    summary = ICalGLib.Property.new_summary(event["title"]).as_ical_string().strip()
    now = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    vevent = "\r\n".join([
        "BEGIN:VEVENT",
        "DTSTAMP:" + now,
        "CREATED:" + now,
        dtstart,
        dtend,
        summary,
        "END:VEVENT",
    ])
    icomp = ICalGLib.Component.new_from_string(vevent)
    if icomp is None:
        print("calendar: could not build the event", file=sys.stderr)
        sys.exit(1)

    client = connect(ECal, source)
    _, uid = client.create_object_sync(icomp, ECal.OperationFlags.NONE, None)
    print(json.dumps({"source": source.get_uid(), "uid": uid, **event}, ensure_ascii=False))


def delete(source_uid, uid, rid):
    ECal, EDataServer, ICalGLib = eds()
    reg = registry(EDataServer)
    source = reg.ref_source(source_uid)
    if source is None:
        print(f"calendar: no calendar {source_uid}", file=sys.stderr)
        sys.exit(1)
    client = connect(ECal, source)
    mod = ECal.ObjModType.THIS if rid else ECal.ObjModType.ALL
    client.remove_object_sync(uid, rid or None, mod, ECal.OperationFlags.NONE, None)


def main(argv):
    if not argv:
        usage("list, add, delete or parse")
    cmd, args = argv[0], argv[1:]
    try:
        if cmd == "list" and len(args) == 2:
            list_events(parse_date(args[0]), parse_date(args[1]))
        elif cmd == "add" and len(args) == 2:
            add(parse_date(args[0]), args[1])
        elif cmd == "delete" and len(args) in (2, 3):
            delete(args[0], args[1], args[2] if len(args) == 3 else "")
        elif cmd == "parse" and len(args) == 2:
            print(json.dumps(parse_text(parse_date(args[0]), args[1]), ensure_ascii=False))
        else:
            usage(f"bad arguments to {cmd}")
    except SystemExit:
        raise
    except Exception as e:
        # GLib.Error from EDS: a backend that went away, a read-only
        # calendar, a uid that no longer exists.
        print(f"calendar: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
