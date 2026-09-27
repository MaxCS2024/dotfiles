# calendar — events from evolution-data-server, GNOME Calendar's store.
#
# The work is calendar.py next door, which talks to EDS through its own
# library; this is the name the shell and a terminal reach it by.
# services/Calendar.qml runs `list` whenever the calendar card opens or
# changes month, and `add` and `delete` from the card. Whatever GNOME
# Calendar shows, this lists, and the other way round: there is one store.

rig::load log check

RELAY_MODULE_SUMMARY[calendar]="GNOME Calendar's events: list, add, delete"
RELAY_MODULE_ACTIONS[calendar]="list add delete parse"
RELAY_MODULE_STATUS[calendar]="ready"
RELAY_MODULE_TIER[calendar]="general"

relay::calendar::__run() {
    rig::check::require python3 || return "$RIG_EX_NODEP"
    python3 "$RELAY_LIB_DIR/calendar.py" "$@"
}

relay::calendar::list() { relay::calendar::__run list "$@"; }
relay::calendar::add() { relay::calendar::__run add "$@"; }
relay::calendar::delete() { relay::calendar::__run delete "$@"; }
relay::calendar::parse() { relay::calendar::__run parse "$@"; }

relay::calendar::__usage() {
    cat <<'EOF'
  relay calendar list FROM TO          events overlapping [FROM, TO), as JSON
  relay calendar add DATE TEXT         add an event to the default calendar
  relay calendar delete SOURCE UID [RID]   remove one (RID: one occurrence)
  relay calendar parse DATE TEXT       what add would make of TEXT

Dates are YYYY-MM-DD. TEXT starting with a time or a range is a timed
event, anything else lasts all day:

  relay calendar add 2026-09-28 "14:00 Tandläkare"
  relay calendar add 2026-09-28 "9.30-10 Möte"
  relay calendar add 2026-10-02 "Mammas födelsedag"

Needs evolution-data-server and python-gobject (`rack features on calendar`
installs them, with GNOME Calendar).

exit status
  0    done
  1    EDS could not be reached, or refused
  2    bad arguments
  127  python3, python-gobject or evolution-data-server is missing
EOF
}
