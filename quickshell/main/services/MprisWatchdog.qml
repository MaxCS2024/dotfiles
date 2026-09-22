pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

// Quickshell's Mpris singleton can start stale: a player already on the
// session bus that Mpris.players never picks up, because the service's
// own D-Bus enumeration can race the player registering its name —
// confirmed both at a cold `qs` launch and mid-session, minutes after
// launch, with a player that started well after the shell did. There's
// no public API to re-enumerate just the Mpris service (see
// quickshell-service-mpris.qmltypes — Mpris only exposes the read-only
// `players` list), but any config reload does re-sync it, the same one
// a plain QML file edit already triggers during dev. This polls the bus
// directly for what should be there and asks for that reload
// (Quickshell.reload, soft — reuses windows) only when the two disagree,
// instead of waiting for someone to notice and touch a file.
//
// Three guards against turning that fix into a reload storm, all earned
// live testing this:
// 1. No `triggeredOnStart` on the poll Timer — a reload recreates this
//    whole singleton, so an instant re-check would race Mpris.players
//    still resyncing after that very reload, read the still-stale value
//    as another mismatch, and reload again immediately.
// 2. A cooldown between actual reload calls, regardless of what later
//    polls see — a genuinely persistent mismatch (Mpris that a reload
//    doesn't actually fix) would otherwise re-fire every single Timer
//    tick forever.
// 3. The cooldown timestamp lives in `state`, a PersistentProperties,
//    not a plain property on `root` — a reload recreates `root` same as
//    any other object, wiping plain properties back to their declared
//    default, which silently defeats guard 2 the moment it's needed:
//    confirmed live, a plain-property cooldown let a persistent mismatch
//    reload every ~20s (one full Timer interval) indefinitely instead of
//    being suppressed. PersistentProperties is Quickshell's own
//    mechanism for state that must survive exactly this kind of
//    recreation, matched across reloads by `reloadableId`.
Singleton {
    id: root

    readonly property int cooldownMs: 60000

    PersistentProperties {
        id: state
        reloadableId: "mprisWatchdogState"
        property double lastReloadAt: 0
    }

    Process {
        id: busList
        command: ["busctl", "--user", "list", "--no-legend"]
        stdout: StdioCollector {
            onStreamFinished: {
                const live = text.split("\n")
                    .map(line => line.trim().split(/\s+/)[0])
                    .filter(name => name && name.startsWith("org.mpris.MediaPlayer2."))
                const now = Date.now()
                if (live.length !== Mpris.players.values.length
                        && now - state.lastReloadAt > root.cooldownMs) {
                    state.lastReloadAt = now
                    Quickshell.reload(false)
                }
            }
        }
    }

    Timer {
        interval: 20000
        running: true
        repeat: true
        onTriggered: if (!busList.running) busList.running = true
    }
}
