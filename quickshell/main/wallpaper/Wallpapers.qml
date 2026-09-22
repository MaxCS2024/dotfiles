pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../services"

// Everything about wallpapers that is not a window: what is in the
// folder, which image each output is actually showing, applying one, and
// the hourly rotation.
//
// A singleton because three things need it and none of them owns it. The
// gallery (WallpaperSwitcher.qml) is lazily built and most sessions never
// open it; the rotation has to run whether it was opened or not; and
// WallpaperPopup reports the result of an apply that may have come from
// either. All of it used to live in the switcher window except the
// rotation, which lived in the since-deleted settingswindow's
// WallpaperPane.qml — dropped from this config on 2026-09-13, which is
// why
// Settings.rotateWallpaperHourly has been a persisted setting with
// nothing behind it ever since. It has something behind it again.
Singleton {
    id: root

    // Shown in the empty state, and the one place the folder is spelled
    // the way a person would write it. The find below spells it $HOME.
    readonly property string dirDisplay: "~/Pictures/Wallpapers"

    property var files: []
    property bool loading: false

    // What awww is displaying right now, one entry per output — so a
    // two-monitor setup showing two different images marks both.
    //
    // Asked of awww rather than remembered here, so it stays true across
    // a shell restart and is right even when something else set the
    // wallpaper — a script, the rotation below, or the old config's own
    // switcher. rack's theme module parses the same line out of the same
    // command, which is the precedent for this spelling.
    property var currentPaths: []

    // The path an apply is in flight for, "" when none is. Also the lock
    // that keeps a second apply from starting on top of the first.
    property string applying: ""

    function isCurrent(path) { return root.currentPaths.indexOf(path) !== -1 }

    // The filename without its extension, and without a trailing
    // resolution: wallhaven-vpyekp_1920x1080.png is "wallhaven-vpyekp".
    // Every file in this folder carries that suffix and none of it tells
    // you anything the thumbnail doesn't.
    function displayName(path) {
        const base = path.split("/").pop()
        return base.replace(/\.[^.]+$/, "").replace(/[_-]\d{3,5}x\d{3,5}$/, "")
    }

    function refresh() {
        root.loading = true
        listProc.running = false
        listProc.running = true
        root.readCurrent()
    }

    function readCurrent() {
        currentProc.running = false
        currentProc.running = true
    }

    function apply(path) {
        if (path === "" || root.applying !== "") return
        root.applying = path
        const escaped = path.replace(/'/g, "'\\''")
        applyProc.command = ["sh", "-c",
            "awww img '" + escaped + "' --transition-type wipe && matugen image '" + escaped + "' -m smart"]
        applyProc.running = false
        applyProc.running = true
    }

    // A random one that isn't already up. Falling back to the whole list
    // keeps a folder of one image working rather than silently doing
    // nothing, and with two images it is a swap either way.
    function shuffle() {
        const pool = root.files.filter(p => !root.isCurrent(p))
        const from = pool.length > 0 ? pool : root.files
        if (from.length === 0) return
        root.apply(from[Math.floor(Math.random() * from.length)])
    }

    Process {
        id: listProc
        command: ["sh", "-c",
            "find \"$HOME/Pictures/Wallpapers\" -maxdepth 1 -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) " +
            "2>/dev/null | sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.files = text.split("\n").filter(l => l.trim() !== "")
                root.loading = false
            }
        }
    }

    // One line per output, from `awww query` — "…: eDP-1: 1920x1080,
    // scale: 1, currently displaying: image: /path". No `head -n1` where
    // rack's theme module has one: it wants the wallpaper to theme from and this
    // wants every output's, so a two-monitor setup showing two different
    // images marks both of them.
    Process {
        id: currentProc
        command: ["sh", "-c",
            "awww query 2>/dev/null | sed -n 's/.*currently displaying: image: //p'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.currentPaths = text.split("\n").filter(l => l.trim() !== "")
            }
        }
    }

    Process {
        id: applyProc

        // exitCode off the signal, not off a property read here: a stored
        // code can still be the previous run's by the time this lands.
        onExited: (exitCode, exitStatus) => {
            const path = root.applying
            const name = path.split("/").pop()
            if (exitCode === 0) {
                Notifications.addManual("Wallpaper changed", name, "normal", "Wallpaper")
                Panels.notifyWallpaperApplied(path, true, name)
                // awww has written its cache by now, so this is what makes
                // the gallery's "Current" mark move without being told.
                root.readCurrent()
            } else {
                const failMessage = "Could not apply " + name
                    + " — check that awww and matugen are installed"
                Notifications.addManual("Wallpaper Failed", failMessage, "critical", "Wallpaper")
                Panels.notifyWallpaperApplied(path, false, failMessage)
            }
            root.applying = ""
        }
    }

    // The rotation, restored from the deleted settings window and kept
    // honest: a switch that claims to rotate hourly has to rotate hourly
    // (README §7/9 — no non-functional toggles). It shuffles rather than
    // walking the list in order, so a folder you have seen in sequence
    // doesn't repeat itself the same way every day.
    //
    // Hangs off `files` being non-empty, so a session that has not
    // listed the folder yet doesn't fire into an empty pool.
    Timer {
        interval: 3600000
        repeat: true
        running: Settings.rotateWallpaperHourly && root.files.length > 0
        onTriggered: root.shuffle()
    }

    // Listed once at startup rather than on first open: the rotation
    // above needs the list whether or not the gallery is ever built, and
    // it is one `find` over one directory.
    Component.onCompleted: root.refresh()
}
