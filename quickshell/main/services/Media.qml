pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// Which player the shell is talking about, and where it is in the track.
//
// Both halves of the media UI read this: the pill in the bar
// (bar/MediaPlayer.qml) and the card it opens (media/MediaPanel.qml).
// All of it lived on the bar module until 2026-09-22, and could, because
// the hover dropdown it fed was a child of the pill and simply read its
// parent. The card that replaced that dropdown is its own layer-shell
// surface and cannot see the pill at all — the same wall that puts
// Panels.clockAnchor on a singleton — so a player pinned in the card
// would have been a second opinion, and the pill would have gone on
// showing whatever it had picked for itself.
//
// Owning the selection here is also what services/ is for: state with
// more than one consumer that outlives any one surface. The card is
// behind a LazyLoader and most sessions never build it; the pinned
// player survives it being closed either way.
Singleton {
    id: root

    // Every player on the bus except the ones with nothing to show:
    // Stopped with no title. Chromium browsers leave one of those behind
    // when a tab's media ends, and it used to hold the pill up as
    // "Unknown" with transport controls for nothing. A stopped player
    // that still has a title stays, since it can be played again.
    // tests/media/shell.qml checks each state against a real player.
    readonly property var players: Mpris.players.values.filter(p =>
        p.playbackState !== MprisPlaybackState.Stopped || p.trackTitle !== "")

    // -1 = auto-pick (prefer whichever player is playing, else the first
    // one); >= 0 = pinned by the card's player-switch arrows, see
    // switchPlayer() below. A pinned index that stops being valid (that
    // player closed) falls back to auto rather than silently pointing at
    // whichever player inherited the slot.
    property int _pinnedIndex: -1

    readonly property var activePlayer: {
        const players = root.players
        if (root._pinnedIndex >= 0 && root._pinnedIndex < players.length)
            return players[root._pinnedIndex]
        for (const p of players) {
            if (p.isPlaying) return p
        }
        return players.length > 0 ? players[0] : null
    }

    function switchPlayer(delta) {
        const players = root.players
        if (players.length === 0) return
        const cur = root._pinnedIndex >= 0
            ? root._pinnedIndex : players.indexOf(root.activePlayer)
        root._pinnedIndex = (cur + delta + players.length) % players.length
    }

    // position has no periodic change notification of its own — Mpris
    // only pushes it on a seek, confirmed against a real MPRIS session
    // built for this, where position read correctly and advanced every
    // time it was actively re-read, but never fired positionChanged on
    // its own between seeks. `_tick` exists purely to give the two
    // properties below something to depend on that *does* change every
    // second, forcing the re-read; its value is otherwise unused.
    property int _tick: 0

    Timer {
        interval: 1000
        // Gated on something being able to show the result. Hiding the
        // bar (SUPER+ALT+SPACE) leaves its subtree mapped at opacity 0
        // rather than tearing it down — see bar/Bar.qml for why it can't
        // use `visible` — so without this the tick would go on firing
        // every second while music plays, re-driving a progress line
        // nobody can see and its Behavior animation with it. The card is
        // the other reason to keep ticking, and it is its own window.
        running: root.activePlayer !== null
            && (Panels.barVisible || Panels.mediaShown)
        repeat: true
        onTriggered: root._tick++
    }

    readonly property real progressFraction: {
        root._tick
        if (!root.activePlayer || root.activePlayer.length <= 0) return 0
        return Math.max(0, Math.min(1, root.activePlayer.position / root.activePlayer.length))
    }

    // The same re-read, as seconds rather than a fraction, for a surface
    // that prints the elapsed time as text. It needs its own property
    // because `activePlayer.position` on its own is exactly the binding
    // that never re-evaluates: the dropdown this card replaced read it
    // directly and its elapsed time stood still between seeks while the
    // progress bar two rows above it advanced normally.
    readonly property real position: {
        root._tick
        return root.activePlayer ? root.activePlayer.position : 0
    }

    function fmtTime(seconds) {
        if (!seconds || seconds < 0) seconds = 0
        const m = Math.floor(seconds / 60)
        const s = Math.floor(seconds % 60)
        return m + ":" + (s < 10 ? "0" : "") + s
    }
}
