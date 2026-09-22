import Quickshell
import Quickshell.Io
import QtQuick

// A JSON file that backs shell state: loaded once at startup, written
// back debounced, and safe against the two ways that goes wrong.
//
// ── The two hazards ──────────────────────────────────────
// **Clobbering.** The obvious shape — bind a FileView to a path and
// write whenever state changes — destroys the file on every cold start,
// because the shell's defaults are in place for the moment before the
// file is read and that moment contains a write. So nothing is written
// until the file has been read.
//
// But "has been read" cannot be waited for when the file does not exist
// yet: FileView.onLoaded never fires, and the store would stay silent
// forever on a fresh install. Hence the probe below — a plain `test -f`
// rather than gating on an unconfirmed "failed to load" signal. If the
// file is absent, writing is safe immediately; if it is present, wait.
//
// Either way the FileView's `path` is set, because the *first-ever*
// setText() has nowhere to write without it and fails with "no path
// specified" — a file that does not exist yet still needs a path to be
// created at. That is the footgun this file exists to state once: three
// separate copies of this pattern each had to rediscover it.
//
// **Corruption.** A half-written or hand-edited file must not take the
// shell down with it. A parse failure comes up with defaults and says
// nothing; `printErrors: false` keeps the read itself quiet too.
//
// ── Using it ─────────────────────────────────────────────
//     JsonStore {
//         id: store
//         path: Quickshell.dataPath("thing.json")
//         snapshot: () => root._snapshot()
//         onRestored: (data) => root._apply(data)
//     }
//
//     function _save() { store.save() }   // debounced, guarded
//
// `restored` fires only when a file was there and parsed. `saved` fires
// after each write, for a store whose owner has a second file to keep in
// step — theme/Appearance.qml writes the terminal's palette that way.
//
// Written 2026-09-21, when this pattern existed four times: two in
// services/Notifications.qml (history and popups) and one each in
// services/Settings.qml and theme/Appearance.qml. The `test -f` probe
// and its StdioCollector were character-for-character identical in all
// four, and the comment explaining why was written out three times.
Item {
    id: store

    // Where the file lives. Set once; this does not follow a changing
    // path, because the probe that makes the first write safe runs once.
    required property string path

    // Returns the value to persist. A function rather than a bound
    // property so the snapshot is taken when the write happens, not on
    // every change that schedules one — a burst of twenty changes
    // computes it once.
    property var snapshot: null

    // Long enough that flipping a switch does not hit disk per keypress.
    // Shorter where the write has to land before whatever it is meant to
    // survive: the notification popup file uses a smaller number,
    // because a popup restored after a restart is the whole point of it.
    property int debounce: 400

    // False until it is safe to write — see the header. Nothing this
    // store owns is written while it is false.
    readonly property bool loaded: store._loaded

    // A file was there and parsed. Not emitted for a missing file, and
    // not emitted for a corrupt one.
    signal restored(var data)

    // A write has just gone out.
    signal saved()

    // Schedules a debounced write, or does nothing if it is not yet safe
    // to write. Callers can fire this as freely as they like.
    function save() {
        if (store._loaded) saveTimer.restart()
    }

    // For a write that must not wait — a shutdown path, say. Still a
    // no-op before the file has been read.
    function saveNow() {
        if (!store._loaded) return
        saveTimer.stop()
        store._write()
    }

    property bool _loaded: false

    function _write() {
        if (!store.snapshot) return
        file.setText(JSON.stringify(store.snapshot()))
        store.saved()
    }

    Process {
        running: true
        command: ["sh", "-c", "test -f '" + store.path + "' && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: {
                file.path = store.path
                if (text.trim() !== "yes") store._loaded = true
            }
        }
    }

    FileView {
        id: file
        printErrors: false
        onLoaded: {
            // Flipped before the restore rather than after, so a handler
            // that saves in response to what it restored is not swallowed
            // by the guard in save(). services/Notifications.qml's popup
            // file depends on exactly that: restoring a popup rewrites the
            // file to describe what is actually on screen.
            store._loaded = true
            try {
                const parsed = JSON.parse(text())
                if (parsed !== null && parsed !== undefined) store.restored(parsed)
            } catch (e) {
                // Corrupt file — come up in defaults. Deliberately not
                // rewritten here: leaving it alone keeps whatever could
                // not be read available to look at afterwards.
            }
        }
    }

    Timer {
        id: saveTimer
        interval: store.debounce
        onTriggered: store._write()
    }
}
