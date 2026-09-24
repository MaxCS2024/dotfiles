pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "packages.js" as Plan

// What is installed on this machine, from the two package managers this
// config uses — pacman (native and foreign) and flatpak (user and system)
// — and the one way to change it.
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
// Changing it went the same way, later: the Conf menu, the installer and
// the packages list each spelled their own install and remove commands,
// took root three ways for the same package, kept their own "installing"
// marks, and only the installer's flatpak path refreshed this afterwards.
// Those are here now too (see "Changing what is installed" below), with
// the per-source rules in packages.js, which tests/packages covers.
//
// ── Shape ────────────────────────────────────────────────
// Entries are the shape packages/PackagesList.qml already drew:
//
//   { source, id, name, version, description, installed }
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
    signal refreshed()

    // The lists keep their last answer until each process replaces it:
    // emptied first, every window bound to `installed` would flash an
    // empty list after each install or removal.
    function refresh() {
        root._loading = true
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

    // ── Changing what is installed ───────────────────────
    //
    //   Packages.install(entry, prompt)   entry: { source, id, name, scope }
    //   Packages.remove(entry, prompt)
    //
    // `prompt` is the calling window's common/PasswordPrompt, or nothing.
    // With one, what needs root runs behind the window: the prompt asks, a
    // wrong password is tried again with it still up, and it closes once
    // the command has worked. Without one — the Conf menu, which runs a
    // row after it has closed — root means a terminal with sudo in it.
    // packages.js decides which, per source; an AUR install always gets a
    // terminal, because yay wants its PKGBUILD read.
    //
    // A terminal reports nothing back, so what runs in one is watched: the
    // plan's check (`pacman -Q`, `flatpak info`) is asked every two seconds
    // until the package arrives or leaves, for up to ten minutes — an AUR
    // build or a first flatpak's runtime can take a while. Giving up only
    // clears the mark; the terminal carries on regardless.
    //
    // Commands behind the window go one at a time. services/PrivilegedExec
    // tracks a single command, and two windows asking it at once used to
    // lose the first one's answer.
    //
    // While something is being done to a package, busy(source, id) is the
    // action ("install" or "remove"), and "" otherwise — the one answer a
    // window's "Working…" reads. finished() fires when it ends, with a
    // message a window can show in its own way; an action started with no
    // window gets a desktop notification instead, since nothing else would
    // say it.

    signal finished(string action, var entry, bool ok, string message)

    function busy(source, id): string {
        return root._busy[source + ":" + id] || ""
    }

    function install(entry, prompt) { root._start("install", entry, prompt || null) }
    function remove(entry, prompt) { root._start("remove", entry, prompt || null) }

    readonly property int watchInterval: 2000
    readonly property int watchLimit: 10 * 60 * 1000

    // key -> action. Replaced rather than changed in place, so that every
    // binding reading busy() hears about it.
    property var _busy: ({})

    function _mark(entry, action) {
        const next = Object.assign({}, root._busy)
        if (action === "") delete next[Plan.key(entry)]
        else next[Plan.key(entry)] = action
        root._busy = next
    }

    function _name(entry) { return entry.name || entry.id }

    function _done(action, entry) {
        return root._name(entry) + (action === "install" ? " installed" : " removed")
    }

    function _start(action, entry, prompt) {
        if (!entry || root.busy(entry.source, entry.id) !== "") return

        const plan = Plan.plan(action, entry, prompt !== null)
        if (plan === null) {
            root._end(action, entry, prompt, false,
                "Can't " + action + " " + (entry.id || "that") + ": not a package this knows how to")
            return
        }

        if (plan.terminal) {
            root._mark(entry, action)
            Terminal.run(plan.commandLine, { title: plan.title })
            root._watch(action, entry, plan.check, prompt)
        } else if (plan.privileged) {
            // The prompt stays up while the command runs, so a second
            // Enter would queue the same action twice.
            prompt.ask(plan.title, plan.prompt, password => {
                if (root.busy(entry.source, entry.id) === "")
                    root._enqueue({ action, entry, plan, prompt, password })
            })
        } else {
            root._enqueue({ action, entry, plan, prompt, password: "" })
        }
    }

    function _end(action, entry, prompt, ok, message) {
        root._mark(entry, "")
        if (ok) root.refresh()
        root.finished(action, entry, ok, message)
        if (prompt === null)
            Notifications.post(message, "", ok ? "normal" : "critical", "Packages", "")
    }

    // ── Behind the window, one at a time ─────────────────
    property var _queue: []
    property var _current: null

    function _enqueue(job) {
        root._mark(job.entry, job.action)
        root._queue = root._queue.concat([job])
        root._next()
    }

    function _next() {
        if (root._current !== null || root._queue.length === 0) return
        const job = root._queue[0]
        root._queue = root._queue.slice(1)
        root._current = job

        if (job.plan.privileged) {
            PrivilegedExec.run(job.plan.argv, job.password,
                () => {
                    job.prompt.close()
                    root._finishJob(job, true, root._done(job.action, job.entry))
                },
                message => {
                    // The prompt stays up and still holds the action, so
                    // submitting again retries — see PasswordPrompt.ask.
                    job.prompt.showError(message)
                    root._finishJob(job, false, message)
                })
        } else {
            plainProc.command = job.plan.argv
            plainProc.running = true
        }
    }

    function _finishJob(job, ok, message) {
        root._current = null
        root._end(job.action, job.entry, job.prompt, ok, message)
        root._next()
    }

    // What needs no root: removing a flatpak installed for the user alone.
    Process {
        id: plainProc
        onExited: (exitCode, exitStatus) => {
            const job = root._current
            if (job === null) return
            root._finishJob(job, exitCode === 0, exitCode === 0
                ? root._done(job.action, job.entry)
                : "Couldn't " + job.action + " " + root._name(job.entry))
        }
        // A command that is not installed never starts, and a Process
        // that never started emits no exited() — the queue would wait on
        // it for good. Checked a turn later, once exited() has had its
        // chance to finish the job.
        // The job is taken now, not then: by then exited() may have
        // finished it and started the next one.
        onRunningChanged: {
            if (running) return
            const job = root._current
            Qt.callLater(() => {
                if (job !== null && root._current === job && !job.plan.privileged)
                    root._finishJob(job, false, "Couldn't run " + job.plan.argv[0])
            })
        }
    }

    // ── In a terminal, watched ───────────────────────────
    // key -> { action, entry, check, prompt, until }
    property var _watches: ({})

    function _watch(action, entry, check, prompt) {
        const next = Object.assign({}, root._watches)
        next[Plan.key(entry)] = { action, entry, check, prompt, until: Date.now() + root.watchLimit }
        root._watches = next
        watchTimer.start()
    }

    Timer {
        id: watchTimer
        interval: root.watchInterval
        repeat: true
        onTriggered: {
            const keys = Object.keys(root._watches)
            if (keys.length === 0) {
                watchTimer.stop()
                return
            }
            if (watchProc.running) return

            // One process asks every check: a line per watch, its index and
            // the check's exit status.
            watchProc.keys = keys
            watchProc.command = ["sh", "-c", keys.map((k, i) =>
                Plan.line(root._watches[k].check) + ' >/dev/null 2>&1; echo "' + i + ' $?"').join("\n")]
            watchProc.running = true
        }
    }

    Process {
        id: watchProc
        property var keys: []
        stdout: StdioCollector {
            id: watchOut
            onStreamFinished: root._settle(watchProc.keys, watchOut.text)
        }
    }

    function _settle(keys, text) {
        const now = Date.now()
        const next = Object.assign({}, root._watches)
        const ended = []
        for (const row of text.split("\n")) {
            const cells = row.trim().split(" ")
            if (cells.length !== 2) continue
            const key = keys[Number(cells[0])]
            const watch = next[key]
            if (!watch) continue
            const present = cells[1] === "0"
            if (present === (watch.action === "install")) {
                delete next[key]
                ended.push({ watch, ok: true })
            } else if (now > watch.until) {
                delete next[key]
                ended.push({ watch, ok: false })
            }
        }
        root._watches = next

        for (const e of ended) {
            const w = e.watch
            root._end(w.action, w.entry, w.prompt, e.ok, e.ok
                ? root._done(w.action, w.entry)
                : "Stopped waiting for " + root._name(w.entry) + " — its terminal has the answer")
        }
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
                    installed: true
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
