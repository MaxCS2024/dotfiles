pragma Singleton

import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// The media feature (AGENTS.md, Media): keeps one persistent activity in
// the queue for the current MPRIS player while it plays, and for a while
// after it pauses. The activity carries the player, so the media face
// reads its position and sends its controls itself.
Singleton {
    id: root

    // The one that played last, so a pause doesn't hand the island to
    // another player that happens to be open.
    property var lastPlaying: null

    // Playing first, then the one that played last, then any with a title.
    readonly property var player: {
        const ps = Mpris.players.values.filter(p => p.trackTitle)
        return ps.find(p => p.isPlaying)
            ?? (ps.includes(lastPlaying) ? lastPlaying : null)
            ?? ps[0]
            ?? null
    }

    onPlayerChanged: {
        if (player?.isPlaying)
            lastPlaying = player
        sync(true)
    }

    Connections {
        target: root.player
        function onIsPlayingChanged() {
            if (root.player.isPlaying)
                root.lastPlaying = root.player
            root.sync(true)
        }
        function onTrackTitleChanged() { root.sync(false) }
        function onTrackArtistChanged() { root.sync(false) }
        function onTrackArtUrlChanged() { root.sync(false) }
    }

    // `fresh`: the player or its play state changed, which always puts the
    // activity up. A new title or art only updates one already up, so a
    // paused player whose time ran out stays gone.
    function sync(fresh) {
        const p = player
        if (!Config.media || !p || !p.trackTitle || p.playbackState === MprisPlaybackState.Stopped) {
            ActivityQueue.remove("media")
            return
        }
        if (!fresh && !p.isPlaying && !ActivityQueue.find("media"))
            return
        ActivityQueue.submit({
            key: "media",
            face: "media",
            profile: "media",
            // A user's dismissal holds until the player starts or stops
            // again (or another takes over), not through a new track.
            revive: fresh,
            player: p,
            icon: "\u{f075a}",
            label: p.trackArtist ? `${p.trackTitle} – ${p.trackArtist}` : p.trackTitle,
            progress: -1,
            // Paused: it lives this long, then leaves the island.
            timeout: p.isPlaying ? 0 : Config.mediaPausedTimeout,
        })
    }
}
