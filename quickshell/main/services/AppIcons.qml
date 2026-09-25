pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// An app's icon by name, including apps installed after the shell started.
//
// Quickshell.iconPath asks Qt's icon theme, which reads the icon
// directories once and never notices an app installed later: Blanket and
// VLC, both from Flathub, showed a letter tile in the launcher and a
// "not found" square in the tray until the shell was restarted, while a
// fresh qs found both at once (2026-09-25). Nothing in Quickshell makes Qt
// look again, so when the theme misses, this looks for the file itself
// where every app installs its icon, hicolor and pixmaps, in each
// XDG data dir.
//
//   source: AppIcons.path(entry.icon)    // "" while nothing is found
//
// The search runs in the background, and path() returns "" until it
// finishes; a binding that calls path() re-runs when it does.
Singleton {
    id: root

    // name -> file:// URL, or "" when the search found nothing.
    property var found: ({})

    // Names waiting for a search, and names being searched. Mutated in
    // place, never reassigned: path() reads them inside callers' bindings,
    // and a reassignment would re-run every one of those bindings.
    readonly property var _pending: ({})
    readonly property var _searching: ({})

    function path(name) {
        if (!name) return ""
        const themed = Quickshell.iconPath(name, true)
        if (themed !== "") return themed
        const hit = root.found[name]
        if (hit === undefined && !root._searching[name]) {
            root._pending[name] = true
            Qt.callLater(root._search)
        }
        return hit || ""
    }

    function _search() {
        if (search.running) return
        const names = Object.keys(root._pending)
        if (names.length === 0) return
        for (const n of names) {
            delete root._pending[n]
            root._searching[n] = true
        }
        search.names = names
        search.running = true
    }

    // A miss is remembered so the same name isn't searched on every
    // redraw. An app installed later changes the desktop entries, and its
    // icon may be one of those misses, so they are forgotten then.
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            const kept = {}
            for (const n in root.found) {
                if (root.found[n] !== "") kept[n] = root.found[n]
            }
            root.found = kept
        }
    }

    Process {
        id: search
        property var names: []
        // Largest first, so the icon is scaled down rather than up.
        command: ["sh", "-c", `
            dirs="\${XDG_DATA_HOME:-$HOME/.local/share}:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
            for name; do
                hit=
                IFS=:
                for d in $dirs; do
                    for f in "$d/icons/hicolor/scalable/apps/$name.svg" \\
                             "$d/icons/hicolor/512x512/apps/$name.png" \\
                             "$d/icons/hicolor/256x256/apps/$name.png" \\
                             "$d/icons/hicolor/128x128/apps/$name.png" \\
                             "$d/icons/hicolor/64x64/apps/$name.png" \\
                             "$d/icons/hicolor/48x48/apps/$name.png" \\
                             "$d/pixmaps/$name.svg" "$d/pixmaps/$name.png"; do
                        if [ -f "$f" ]; then hit=$f; break 2; fi
                    done
                done
                unset IFS
                printf '%s\\t%s\\n' "$name" "$hit"
            done`, "sh"].concat(search.names)
        stdout: StdioCollector {
            onStreamFinished: {
                const next = Object.assign({}, root.found)
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t")
                    if (tab <= 0) continue
                    const file = line.slice(tab + 1)
                    next[line.slice(0, tab)] = file !== "" ? "file://" + file : ""
                }
                for (const n of search.names) delete root._searching[n]
                root.found = next
            }
        }
        onExited: Qt.callLater(root._search)
    }
}
