import Quickshell.Io
import QtQuick

// One source's search for apps/AppManager.qml: run(command) starts it,
// replacing a search still out, and it reports each answer once.
//
// Replacing is the reason this exists. Setting a Process's `running` to
// false and back to true only asks the old run to stop: it still ends
// first — its output handed to the collector, then exited() and
// runningChanged() — and the new run starts after (Quickshell's
// Process::onFinished). Handled like any other ending, that merged the
// old query's partial output into the new list and cleared the source's
// "searching" while its new search was still out, so the Flathub chip
// said 0 for the five seconds `flatpak search` takes (found 2026-09-27).
// `_stale` marks that one ending to ignore; a second replacement before
// it arrives is still the one ending.
Process {
    id: root

    // The output of a search that was not replaced.
    signal answered(string text)
    // The search is over, answered or not. A search that never started
    // (yay not installed) ends too, with no answer: a Process that fails to
    // start emits only runningChanged().
    signal ended()

    property bool _stale: false

    function run(argv) {
        if (root.running) root._stale = true
        root.command = argv
        root.running = false
        root.running = true
    }

    stdout: StdioCollector {
        id: out
        onStreamFinished: if (!root._stale) root.answered(out.text)
    }

    // The last signal of any ending, so it is where one is settled. pacman
    // exits 1 on "no results", which is an answer, not a failure: the
    // collector has already delivered whatever there was.
    onRunningChanged: {
        if (root.running) return
        if (root._stale) {
            root._stale = false
            return
        }
        root.ended()
    }
}
