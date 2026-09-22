pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// What is installed on this machine, from the two package managers this
// config uses: pacman (native and foreign) and flatpak (user and system).
//
// ── Why this exists ──────────────────────────────────────
// Every other command-line tool in this shell is wrapped exactly once —
// nmcli only in services/Network.qml, rfkill only in AirplaneMode.qml,
// busctl only in MprisWatchdog.qml, hyprsunset only in NightLight.qml,
// and the wallpaper tools moved into wallpaper/Wallpapers.qml for this
// same reason. Packages was the one domain that never got its service,
// so three surfaces each grew their own adapter to the same two CLIs and
// gave three different answers to "is this installed?":
//
//   menu/MenuActions.qml     `pacman -Qq <names…>`, exit code ignored
//   installer/AppInstaller.qml  `pacman -Q <pkg>`, exit code is the answer
//   packages/PackagesList.qml   `pacman -Qe` and `-Qm`, the full lists
//
// and `flatpak list` four times over, with four flag sets and four
// parsers. MenuActions' invocation carries a careful note about machines
// without flatpak installed; AppInstaller's, written separately, has no
// such guard.
//
// ── What is deliberately NOT here ────────────────────────
// installer/AppInstaller.qml's `pacman -Q <pkg>` stays where it is. It
// reads like a membership test but it is a poll: after an AUR build is
// handed off, it asks every two seconds whether the package has appeared
// yet. A cached set is stale exactly when that question is being asked,
// so it wants its own live process and keeps one.
//
// ── Shape ────────────────────────────────────────────────
// Entries are the shape packages/PackagesList.qml already drew:
//
//   { source, id, name, version, description, installed, installing }
//
// plus `scope` ("user" | "system") on flatpaks, which is what lets an
// uninstall pass the matching flag instead of guessing --user.
//
// `-Qe` rather than `-Q`: explicitly-installed packages, not every
// transitive library underneath them, which is what a person means by
// "installed". `-Qm` is the foreign ones, in practice almost always AUR;
// whichever of the two finishes second removes the AUR entries from the
// native list, since a foreign package answers to both.
//
// Descriptions are left empty. Filling them means one `pacman -Qi` per
// package, which is hundreds of processes to draw one list.
Singleton {
    id: root

    readonly property var pacman: root._pacman
    readonly property var aur: root._aur
    readonly property var flatpak: root._flatpak

    // Everything, in the order the list wants to show it.
    readonly property var installed: root._pacman.concat(root._aur, root._flatpak)

    readonly property bool loading: root._loading
    // Both the inventory and the membership set have answered, so a
    // caller that must not flicker — a menu greying out rows it has not
    // heard about yet — has something to wait for.
    readonly property bool loadedOnce: root._loadedOnce && root._allLoaded

    // Fired when a refresh has finished and `installed` is worth reading.
    // A caller that keeps its own mutable copy — packages/PackagesList.qml
    // marks entries as uninstalling — re-takes it here.
    signal refreshed()

    function refresh() {
        root._loading = true
        root._pacman = []
        root._aur = []
        root._flatpakUser = []
        root._flatpakSystem = []
        for (const p of [pacmanProc, aurProc, allPacmanProc, flatpakUserProc, flatpakSystemProc]) {
            p.running = false
            p.running = true
        }
    }

    // Is this exact flatpak application id installed? Asked by name
    // rather than by scanning `installed`, because the installer marks
    // search results with it on every keystroke.
    function hasFlatpak(id): bool {
        return root._flatpak.some(e => e.id === id)
    }

    // Is a package with this name here at all?
    //
    // Deliberately not asked of the inventory above. That is `-Qe` and
    // `-Qm`, which is what a person installed on purpose; this is `-Qq`,
    // which is everything, dependencies included. menu/MenuActions.qml
    // wants this one: an app that arrived underneath something else is
    // still here, and a menu row offering to install it would be wrong.
    //
    // Flatpak has no such split — an app is installed or it is not — so
    // that half answers from the inventory. A ref matches by id
    // (com.spotify.Client) and a human name by name.
    function has(name): bool {
        if (root._allPacman[name] === true) return true
        return root._flatpak.some(e => e.id === name || e.name === name)
    }

    // Set, not list: this is only ever asked "is this in you".
    property var _allPacman: ({})

    property var _pacman: []
    property var _aur: []
    property var _flatpakUser: []
    property var _flatpakSystem: []
    readonly property var _flatpak: root._flatpakUser.concat(root._flatpakSystem)
    property bool _loading: false
    property bool _loadedOnce: false
    property bool _allLoaded: false

    function _parsePacman(text, sourceLabel) {
        // "name version" per line.
        return text.split("\n")
            .filter(l => l.trim() !== "")
            .map(l => {
                const parts = l.trim().split(/\s+/)
                return {
                    source: sourceLabel,
                    id: parts[0],
                    name: parts[0],
                    version: parts[1] || "",
                    description: "",
                    installed: true,
                    installing: false
                }
            })
    }

    function _parseFlatpak(text, scope) {
        // "name<TAB>application-id" per line.
        return text.split("\n")
            .filter(l => l.trim() !== "")
            .map(l => {
                const parts = l.split("\t")
                return {
                    source: "Flatpak",
                    id: parts[1] || parts[0],
                    name: parts[0],
                    version: "",
                    description: "",
                    installed: true,
                    installing: false,
                    scope: scope
                }
            })
    }

    Process {
        id: pacmanProc
        command: ["pacman", "-Qe"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._pacman = root._parsePacman(text, "Pacman")
                    .filter(e => !root._aur.some(a => a.id === e.id))
                root._loading = false
                root._loadedOnce = true
                root.refreshed()
            }
        }
    }

    Process {
        id: allPacmanProc
        command: ["pacman", "-Qq"]
        stdout: StdioCollector {
            onStreamFinished: {
                const set = ({})
                for (const line of text.split("\n")) {
                    const n = line.trim()
                    if (n !== "") set[n] = true
                }
                root._allPacman = set
                root._allLoaded = true
                root.refreshed()
            }
        }
    }

    Process {
        id: aurProc
        command: ["pacman", "-Qm"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._aur = root._parsePacman(text, "AUR")
                // This may finish before or after pacmanProc; whichever
                // runs second is the one that excludes the foreign
                // entries from the native list.
                root._pacman = root._pacman.filter(e => !root._aur.some(a => a.id === e.id))
                root.refreshed()
            }
        }
    }

    // `|| true` and stderr discarded: a machine without flatpak is not an
    // error, it is a machine without flatpak. menu/MenuActions.qml's
    // invocation has carried that guard for a while and the installer's,
    // written separately, never did.
    Process {
        id: flatpakUserProc
        command: ["sh", "-c", "flatpak list --app --user --columns=name,application 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._flatpakUser = root._parseFlatpak(text, "user")
                root.refreshed()
            }
        }
    }

    Process {
        id: flatpakSystemProc
        command: ["sh", "-c", "flatpak list --app --system --columns=name,application 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._flatpakSystem = root._parseFlatpak(text, "system")
                root.refreshed()
            }
        }
    }
}
