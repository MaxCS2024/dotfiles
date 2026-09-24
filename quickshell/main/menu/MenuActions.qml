import Quickshell
import Quickshell.Io
import QtQuick
import "../services"

// Everything the Conf menu can actually *do*, kept out of ConfMenu.qml so
// that file stays the view — a filter, a list and a key handler. Nothing
// here draws; nothing in ConfMenu.qml spawns a process.
//
// Two kinds of action live here:
//
//   * the ones that run a command — package updates, `rack`, screen
//     capture, the colour picker. Anything long-running or interactive
//     (a sudo prompt, a PKGBUILD diff, a wall of pacman output) opens a
//     terminal rather than a Process this shell would have to render the
//     output of; anything instant runs headless and reports through
//     Notifications, like every other shell-generated event.
//   * the ones that open a panel this shell already has — those aren't
//     here at all, they're one-line `Panels.*` calls in ConfMenu.qml's
//     tree, because routing a signal emit through a second file would be
//     indirection for its own sake. Screen capture is a `Panels.capture`
//     call there for the same reason.
QtObject {
    id: actions

    // ── What's actually on PATH ──────────────────────────
    // A menu row that names a binary in `requires` draws dimmed and
    // refuses to run when that binary isn't on PATH. The menu offers
    // things this machine may simply not have (wf-recorder is the
    // obvious one — it isn't installed here today), and a row that
    // silently does nothing is worse than one that says why.
    //
    // The list comes from ConfMenu.qml, which derives it from the
    // `requires:` values in the tree itself rather than keeping a second
    // copy beside it: a name that fell out of sync here would dim its row
    // forever, with nothing connecting the two lists to say why.
    //
    // Probed once per open rather than once per shell run: these come
    // and go with `pacman -S`, and the menu is exactly where someone
    // goes right after installing one.
    property var probeNames: []

    // Null until the probe has answered once. Nothing is treated as
    // missing before that: the probe is a process, so on the first open
    // of a shell run it is still running when the menu draws its first
    // frame, and a menu whose rows all read "needs grim" for the first
    // tenth of a second — and refuse to run if you're quick on the Enter
    // key — is worse than one that finds out a moment later.
    property var tools: null

    function has(name) { return actions.tools !== null && actions.tools[name] === true }

    readonly property Process probeProc: Process {
        command: ["sh", "-c",
            "for t in " + actions.probeNames.join(" ")
            + "; do command -v \"$t\" >/dev/null 2>&1 && printf '%s\\n' \"$t\"; done"]
        stdout: StdioCollector {
            id: probeOut
            // Only publish a genuinely different answer. ConfMenu.qml
            // binds its whole tree to this, and that binding feeds the
            // list's model — assigning a fresh object on every open
            // would fire toolsChanged each time and tear down and
            // rebuild every visible row a few ms into the open
            // animation, for an answer that is almost always the same
            // one as last time.
            onStreamFinished: {
                const found = actions._toSet(probeOut.text)
                if (!actions._sameSet(actions.tools, found)) actions.tools = found
            }
        }
    }

    // ── Probe plumbing ──────────────────────────────────
    // Shared with the PATH probe above. It kept these when the two
    // package probes left for services/Packages.qml, because "which of
    // these binaries is on PATH" is still this file's own question.
    function _toSet(text) {
        const found = ({})
        const lines = text.trim().split("\n")
        for (let i = 0; i < lines.length; i++)
            if (lines[i] !== "") found[lines[i]] = true
        return found
    }

    function _sameSet(current, found) {
        if (current === null) return false
        const names = Object.keys(found)
        if (names.length !== Object.keys(current).length) return false
        for (let i = 0; i < names.length; i++)
            if (current[names[i]] !== true) return false
        return true
    }

    // ── What's actually installed ────────────────────────
    // A second probe, and a different question from the one above: that
    // one asks whether a binary is on PATH, which is what gates a row on
    // the tool it needs; this one asks pacman whether a package is on the
    // machine, which is what an install row says about itself.
    //
    // They can't be folded together. A package is not its binary
    // (heroic-games-launcher-bin puts `heroic` on PATH, bottles puts
    // `bottles`), and the two answers are wanted in opposite directions:
    // missing dims a `requires` row, present annotates an install one.
    //
    // The names come from the caller rather than from the tree, unlike
    // `probeNames` — the tree is where the answer is *used*, so deriving
    // the question from it too would make ConfMenu's `tree` binding
    // depend on its own probe.
    //
    // Two lists because there are two package managers to ask and they
    // answer about different things: `packageNames` are pacman's, repo
    // and AUR alike, and `flatpakNames` are flathub refs. The answers
    // merge into one map below, which is what makes a row's "is this
    // here" a lookup rather than a question about where it came from.
    property var packageNames: []
    property var flatpakNames: []

    // Null until answered, for the same reason `tools` is: a row that
    // said "installed" — or stayed silent — before the probe had run
    // would be guessing. With two probes that means until *both* have
    // answered, so a level holding one of each doesn't light up half a
    // frame before the rest.
    //
    // Names don't collide across the two: a flatpak ref is reverse-DNS
    // (com.discordapp.Discord), which is not a shape pacman package names
    // take — dotted ones like dotnet-runtime-6.0 exist, but nothing is
    // named as a domain — so one flat map is safe and neither side has to
    // know which probe put a name in it.
    readonly property var packages: {
        if (!Packages.loadedOnce) return null
        const out = ({})
        for (const n of actions.packageNames) if (Packages.has(n)) out[n] = true
        for (const n of actions.flatpakNames) if (Packages.has(n)) out[n] = true
        return out
    }

    Component.onCompleted: if (!Packages.loadedOnce) Packages.refresh()

    // All three probes run per menu open, not per shell run: packages and
    // binaries alike come and go with `pacman -S`, a default can be
    // changed by anything on the machine, and this menu is where someone
    // lands right after either. The package probes are skipped when
    // nothing asked about their side — an empty list would make `pacman
    // -Qq` print every package on the machine, and there is no point
    // spawning flatpak for a tree that names none.
    //
    // Apps › Defaults is the third: services/Defaults.qml, which asks
    // `relay default` what each role is set to and which candidates are
    // installed. It had a probe of its own here, a generated script that
    // resolved the options a second time beside hypr/modules/vars.lua,
    // until both moved behind relay (docs/adr/0001).
    //
    // Features › is the fourth: `rack features list`, below.
    function refresh() {
        if (actions.probeNames.length > 0) {
            actions.probeProc.running = false
            actions.probeProc.running = true
        }
        if (actions.packageNames.length > 0 || actions.flatpakNames.length > 0)
            Packages.refresh()
        Defaults.refresh()
        actions.featuresProc.running = false
        actions.featuresProc.running = true
    }

    // ── Optional features ────────────────────────────────
    // Every feature rack/features.json defines, in its order, as `rack
    // features list` prints them: its name, its label, whether its
    // packages are on the machine, and whether it can be switched at all
    // ("-" in the state column: installed or not, like lazyvim). Whether
    // a switchable one is on is not taken from here —
    // services/Features.qml answers that live from the choices file,
    // where this is only as fresh as the last open.
    //
    // Null until answered, for the same reason `tools` is. An empty list
    // is rack missing or failing: the row that says so names the
    // command to run by hand.
    property var features: null

    readonly property Process featuresProc: Process {
        command: ["sh", "-c", 'PATH="$HOME/.local/bin:$PATH" exec rack features list']
        stdout: StdioCollector {
            id: featuresOut
            onStreamFinished: actions._parseFeatures(featuresOut.text)
        }
    }

    function _parseFeatures(text) {
        const found = []
        for (const line of text.split("\n")) {
            const m = line.match(/^\s*(\S+)\s+(on|off|-)\s+(installed|not installed)\s+(.+?)\s*$/)
            if (m) found.push({ name: m[1], switchable: m[2] !== "-",
                                installed: m[3] === "installed", label: m[4] })
        }
        // Only a different answer is published, as with `tools`: the
        // whole tree is bound to this.
        if (JSON.stringify(found) !== JSON.stringify(actions.features)) actions.features = found
    }

    // `rack features on|off` for a feature that is already installed:
    // nothing to prompt for, so no terminal. It enables or disables the
    // feature's units, writes the choices file and reloads Hyprland and
    // this shell; the notification is the only sign of it for a feature
    // with nothing in the bar, like dictation.
    readonly property Process featureProc: Process {
        property string label: ""
        property string verb: ""
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                Notifications.post(featureProc.label + " is " + featureProc.verb, "",
                    "normal", "Conf", "")
            else
                Notifications.post("Couldn't turn " + featureProc.label + " " + featureProc.verb,
                    "rack features " + featureProc.verb + " exited " + exitCode,
                    "critical", "Conf", "")
        }
    }

    function setFeature(name, label, verb) {
        actions.featureProc.running = false
        actions.featureProc.label = label
        actions.featureProc.verb = verb
        actions.featureProc.command = ["sh", "-c",
            'PATH="$HOME/.local/bin:$PATH" exec rack features "$1" "$2"', "sh", verb, name]
        actions.featureProc.running = true
    }

    // ── Terminal commands ────────────────────────────────
    // Moved to services/Terminal.qml, which any part of the shell can
    // call and which floats the window in the middle of the screen (one
    // window rule, see that file). The rows that want one call it
    // directly from the tree, the same way the rows that open a panel
    // call Panels — see this file's header.

    // ── Colour picker ────────────────────────────────────
    // hyprpicker -a puts the hex on the clipboard itself and prints it;
    // the notification is what tells the user it worked, since nothing
    // else on screen changes. A cancelled pick (Escape) exits non-zero
    // with nothing on stdout and is deliberately silent.
    readonly property Process pickProc: Process {
        property int lastExit: -1
        command: ["hyprpicker", "-a", "-f", "hex"]
        onExited: (exitCode, exitStatus) => pickProc.lastExit = exitCode
        stdout: StdioCollector {
            id: pickOut
            onStreamFinished: {
                const hex = pickOut.text.trim()
                if (pickProc.lastExit !== 0 || hex === "") return
                Notifications.post("Colour picked", hex + " is on the clipboard",
                    "normal", "Conf", "")
            }
        }
    }

    function pickColor() {
        actions.pickProc.running = false
        actions.pickProc.running = true
    }

    // ── Screen recording ─────────────────────────────────
    // A toggle, not a one-shot: wf-recorder runs until something signals
    // it, and the menu row is the only stop control there is. `recording`
    // is what the row reads to relabel itself.
    property bool recording: false

    readonly property Process recProc: Process {
        property int lastExit: -1
        onExited: (exitCode, exitStatus) => {
            recProc.lastExit = exitCode
            actions.recording = false
        }
        stdout: StdioCollector {
            id: recOut
            onStreamFinished: {
                const path = recOut.text.trim()
                if (recProc.lastExit === 3) return   // region select cancelled
                if (recProc.lastExit === 0 && path !== "")
                    Notifications.post("Recording saved", path, "normal", "Conf", "")
                else
                    Notifications.post("Recording failed",
                        "wf-recorder exited " + recProc.lastExit, "critical", "Conf", "")
            }
        }
    }

    readonly property Process recStopProc: Process {
        // -INT, not -TERM: wf-recorder only finalises the container (and
        // so leaves a playable file) when it's interrupted.
        command: ["pkill", "-INT", "-x", "wf-recorder"]
    }

    function record() {
        if (actions.recording) {
            actions.recStopProc.running = false
            actions.recStopProc.running = true
            return
        }
        const script = [
            'dir="$HOME/Videos/Recordings"',
            'mkdir -p "$dir"',
            'sel="$(slurp)" || exit 3',
            '[ -n "$sel" ] || exit 3',
            'f="$dir/$(date +%Y-%m-%d_%H-%M-%S).mp4"',
            'wf-recorder -g "$sel" -f "$f" >/dev/null 2>&1 || exit 1',
            'printf "%s" "$f"'
        ].join("; ")
        actions.recProc.command = ["sh", "-c", script]
        actions.recProc.running = false
        actions.recProc.running = true
        actions.recording = true
    }

    // Whatever a row couldn't do, said out loud — see `probeNames` above.
    function refuse(label, tool) {
        Notifications.post(label + " needs " + tool,
            tool + " isn't installed", "critical", "Conf", "")
    }
}
