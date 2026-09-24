# earbuds — the battery of Nothing earbuds: left, right and case.
#
# The work is earbuds.py next door, which speaks Nothing's own protocol to the
# earbuds over Bluetooth; this is the name the shell and a terminal reach it
# by. `watch` is what services/Earbuds.qml runs for as long as the earbuds
# feature is on (`rack features`): one JSON line per change, the whole state
# each time, `{"connected":false}` while no Nothing earbuds are connected.
#
# BlueZ lets one process at a time hold the earbuds' data channel, so while
# the shell is watching, a second `relay earbuds watch` exits 3 and says so.

rig::load log check

RELAY_MODULE_SUMMARY[earbuds]="battery of Nothing earbuds (left, right, case)"
RELAY_MODULE_ACTIONS[earbuds]="watch"
RELAY_MODULE_STATUS[earbuds]="ready"
RELAY_MODULE_TIER[earbuds]="general"

relay::earbuds::watch() {
    rig::check::require python3 || return "$RIG_EX_NODEP"
    exec python3 "$RELAY_LIB_DIR/earbuds.py"
}

relay::earbuds::__usage() {
    cat <<'EOF'
  relay earbuds watch    one JSON line per change, until stopped

Needs python-dbus and python-gobject (`rack features on earbuds` installs
them). Works with Nothing earbuds that offer the Nothing X service; checked
against the Ear (3).

exit status
  0    stopped (SIGTERM or ^C)
  1    bluetoothd is not running, or went away
  3    another watcher already has the earbuds (the shell, usually)
  127  python3, python-dbus or python-gobject is missing
EOF
}
