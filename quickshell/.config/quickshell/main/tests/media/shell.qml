import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import "services"

// Tests for services/Media.qml, the player list the media pill and card
// both read. Run with `tests/run media`, which copies the real Media.qml in
// beside the stub here — this file can't run on its own.
//
// It drives a real player over D-Bus: fake-mpris-player, started below,
// joins the session bus and the steps move it between states through
// Quickshell's own MprisPlayer calls. Other players on the bus (a browser,
// say) are left alone; every check is about the fake one.
//
// Same step runner as tests/bar/shell.qml: a step that returns a number
// waits that many ms, which is how each D-Bus round trip gets time to land.
ShellRoot {
    id: root

    property int failures: 0
    property int step: 0

    // The fake player as Mpris sees it, whether or not Media lets it in.
    readonly property var fake: Mpris.players.values.find(p => p.identity === "BarTest") ?? null
    readonly property bool listed: root.fake !== null && Media.players.includes(root.fake)

    function check(name, ok, detail) {
        if (!ok) root.failures++
        console.log(`TEST ${ok ? "PASS" : "FAIL"} ${name}${ok || detail === undefined ? "" : ` (${detail})`}`)
    }
    function describe() {
        return root.fake ? `${root.fake.playbackState}, title "${root.fake.trackTitle}"` : "no fake player"
    }

    Process {
        id: fakePlayer
        command: ["python3", Qt.resolvedUrl("fake-mpris-player").toString().replace("file://", "")]
        running: true
    }

    readonly property var steps: [
        // Mpris picks the player up asynchronously; give it a moment.
        () => 1500,
        () => {
            root.check("fake player is on the bus", root.fake !== null)
        },

        // ── the case being filtered ────────────────────────
        () => {
            root.check("stopped player with no title is not listed", !root.listed, root.describe())
            root.check("stopped player with no title is never the active one", Media.activePlayer !== root.fake)
            root.fake.play()
            return 400
        },

        // ── everything else stays ──────────────────────────
        () => {
            root.check("playing player is listed", root.listed, root.describe())
            root.check("playing player is the active one", Media.activePlayer === root.fake)
            root.fake.pause()
            return 400
        },
        () => {
            root.check("paused player is listed", root.listed, root.describe())
            root.fake.stop()
            return 400
        },
        () => {
            root.check("stopped player that still has a title is listed", root.listed, root.describe())
            // The fake's stand-in for a media session ending.
            root.fake.next()
            return 400
        },
        () => {
            root.check("player drops out when its title goes", !root.listed, root.describe())
            root.fake.play()
            return 400
        },
        () => {
            root.check("player comes back when it plays again", root.listed, root.describe())
        }
    ]

    Timer {
        id: runner
        interval: 0
        onTriggered: {
            if (root.step >= root.steps.length) {
                console.log(`TEST DONE ${root.failures}`)
                return
            }
            let wait
            try {
                wait = root.steps[root.step]()
            } catch (e) {
                root.check(`step ${root.step} threw`, false, e)
            }
            root.step++
            runner.interval = typeof wait === "number" ? wait : 0
            runner.start()
        }
    }

    Component.onCompleted: runner.start()
}
