import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
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

    // All four probes run per menu open, not per shell run: packages and
    // binaries alike come and go with `pacman -S`, a default can be
    // changed by anything on the machine, and this menu is where someone
    // lands right after either. Each is skipped when nothing asked about
    // its side — an empty list would make `pacman -Qq` print every
    // package on the machine, and there is no point spawning flatpak for
    // a tree that names none.
    function refresh() {
        if (actions.probeNames.length > 0) {
            actions.probeProc.running = false
            actions.probeProc.running = true
        }
        if (actions.packageNames.length > 0 || actions.flatpakNames.length > 0)
            Packages.refresh()
        if (actions.defaultRoles.length > 0) {
            actions.defaultsProc.running = false
            actions.defaultsProc.running = true
        }
    }

    // ── What is set, and what could be ───────────────────
    // The fourth probe, for Setup › Defaults. It answers two questions at
    // once because they are the same walk of the machine: what each role
    // is set to now (`cur`), and which of the roles' listed options are
    // actually here to choose (`opt`).
    //
    // The roles and their options come from ConfMenu.qml — plain data,
    // like the app lists the package probes read, and deliberately not
    // derived from the tree: this feeds the tree, so a question asked of
    // the tree would close a loop (see ConfMenu's own note on that).
    //
    // Resolution order per option is native binary, then the flathub ref
    // this menu's Setup section would install, because that is the order
    // of preference for running one: a native brave beats `flatpak run
    // com.brave.Browser` on startup time, and the flatpak is what you
    // have when there is no native one. Anything neither is silently not
    // offered — Setup › Browsers is the level for adding one, and a
    // Defaults level full of dimmed rows would be a worse version of it.
    property var defaultRoles: []

    // Null until answered, for the reason `tools` and `packages` are —
    // an empty level for the first frames of an open reads as "you have
    // no terminals installed", which is a lie a probe can tell.
    property var defaultsByRole: null

    // What role <name> resolves to right now, as a `cur` shell function
    // for whoever sources it. hypr/modules/vars.lua run by lua, not read
    // by sed: that file is the one that resolves a state file against its
    // fallback, so running it asks exactly the question the binds ask —
    // no second copy of the fallbacks here, and no parser to break the
    // next time that file changes shape (the sed the old info view used
    // broke the moment it did). The role name goes through the
    // environment to keep the quoting flat. Silent on a machine without
    // lua: the answer is empty, which both callers below have a path for.
    // Read through ~/.config/hypr, the deployed link, rather than the
    // repo, so this works wherever the repo was cloned.
    readonly property string varsCur:
        "cur() { ROLE=\"$1\" lua -e 'local v = dofile(os.getenv(\"HOME\")..\"/.config/hypr/modules/vars.lua\") io.write(v[os.getenv(\"ROLE\")] or \"\")' 2>/dev/null; }"

    readonly property string defaultsScript: {
        const roles = actions.defaultRoles
        if (roles.length === 0) return ""

        const lines = [
            'dirs="$HOME/.local/share/applications'
                + ' $HOME/.local/share/flatpak/exports/share/applications'
                + ' /var/lib/flatpak/exports/share/applications'
                + ' /usr/local/share/applications /usr/share/applications"',
            actions.varsCur,
            'desk() { for id in "$@"; do for d in $dirs; do [ -f "$d/$id" ] && { printf "%s" "$id"; return; }; done; done; }',
            'have() { command -v "$1" >/dev/null 2>&1; }',
            'fp() { flatpak info "$1" >/dev/null 2>&1; }',
            'opt() { printf "opt\\t%s\\t%s\\t%s\\t%s\\n" "$1" "$2" "$3" "$4"; }'
        ]

        for (let i = 0; i < roles.length; i++) {
            const role = roles[i]
            // A role with a state file is asked about through vars.lua's
            // eyes — the command a bind would run. One without is asked
            // of XDG, which is the only place its answer lives.
            lines.push(role.state !== ""
                ? 'printf "cur\\t' + role.key + '\\t%s\\n" "$(cur ' + role.vars + ')"'
                : 'printf "cur\\t' + role.key + '\\t%s\\n" "$(xdg-mime query default '
                    + role.mimes[0] + ' 2>/dev/null)"')

            for (let j = 0; j < role.options.length; j++) {
                const option = role.options[j]
                const args = option.args || ""
                const wrap = option.wrap === false ? "" : "uwsm-app -- "
                // An option that resolves to no .desktop id is still
                // worth offering to a role that runs a command, and
                // useless to one that can only set a handler.
                const guard = role.state !== "" ? "" : '[ -n "$id" ] && '
                const emit = command => guard + "opt " + role.key + " "
                    + actions._quote(option.label) + " "
                    + actions._quote(command) + ' "$id"'

                let branch = "if have " + option.bin + "; then id=$(desk "
                    + option.desktop.join(" ") + "); " + emit(wrap + option.bin + args)
                if (option.flatpak)
                    branch += "; elif fp " + option.flatpak + "; then id="
                        + option.flatpak + ".desktop; "
                        + emit(wrap + "flatpak run " + option.flatpak + args)
                lines.push(branch + "; fi")
            }
        }
        return lines.join("\n")
    }

    // Single quotes, so a label with a space in it ("Eye of GNOME") and a
    // command with a flag on it survive the trip through sh. Nothing
    // here comes from outside the table in ConfMenu.qml, but a table is
    // exactly the thing someone adds a line to without thinking about
    // the shell.
    function _quote(value) {
        return "'" + String(value).split("'").join("'\\''") + "'"
    }

    readonly property Process defaultsProc: Process {
        command: ["sh", "-c", actions.defaultsScript]
        stdout: StdioCollector {
            id: defaultsOut
            onStreamFinished: actions._parseDefaults(defaultsOut.text)
        }
    }

    // "opt<TAB>role<TAB>label<TAB>command<TAB>desktop" and
    // "cur<TAB>role<TAB>value", in whatever order the script printed
    // them. Anything else on stdout is ignored rather than parsed
    // defensively: every line comes from the two printf helpers above.
    function _parseDefaults(text) {
        const byRole = ({})
        for (let i = 0; i < actions.defaultRoles.length; i++)
            byRole[actions.defaultRoles[i].key] = { current: "", options: [] }

        const lines = text.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const cells = lines[i].split("\t")
            const found = byRole[cells[1]]
            if (!found) continue
            if (cells[0] === "cur")
                found.current = (cells[2] || "").trim()
            else if (cells[0] === "opt")
                found.options.push({
                    label: cells[2],
                    command: (cells[3] || "").trim(),
                    desktop: (cells[4] || "").trim(),
                    current: false
                })
        }

        // Which option is the one in force. Exact match, not a fuzzy one
        // on the binary's name: the command a state file holds was
        // written from this same table, and the fallback in vars.lua is
        // spelled to match it. No match is a real answer — the browser
        // this machine's bind names is not installed — and the role row
        // says so by showing the raw value instead of a name.
        for (let i = 0; i < actions.defaultRoles.length; i++) {
            const role = actions.defaultRoles[i]
            const found = byRole[role.key]
            for (let j = 0; j < found.options.length; j++)
                found.options[j].current = role.state !== ""
                    ? found.options[j].command === found.current
                    : found.options[j].desktop === found.current
        }

        // Only publish a genuinely different answer, for the reason the
        // binary probe's own collector spells out: this feeds the tree,
        // and a fresh object every open would tear down and rebuild every
        // visible row a few ms into the open animation for an answer that
        // is almost always last open's.
        const next = JSON.stringify(byRole)
        if (next !== JSON.stringify(actions.defaultsByRole)) actions.defaultsByRole = byRole
    }

    // Setting one, which is up to four writes and never more than one
    // process. The state file is what hypr/modules/vars.lua reads, and a
    // bind captures its value at config load, so the reload at the end is
    // what makes the change reach SUPER+RETURN — the same reload
    // theme/WallpaperSource.qml already fires on every wallpaper change. It costs zen
    // mode its saved chrome (hypr/modules/binds/zen.lua drops the
    // snapshot on config.reloaded), which is the one visible side effect
    // of picking a terminal.
    readonly property Process setProc: Process {
        property string message: ""
        property string detail: ""
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                Notifications.post(setProc.message, setProc.detail, "normal", "Conf", "")
            else
                Notifications.post("Couldn't set that default",
                    "the commands exited " + exitCode, "critical", "Conf", "")
        }
    }

    function setDefault(role, option) {
        const steps = []
        if (role.state !== "") {
            steps.push('mkdir -p "$HOME/.local/state/rack/defaults"')
            steps.push('printf "%s\\n" ' + actions._quote(option.command)
                + ' > "$HOME/.local/state/rack/defaults/' + role.state + '"')
        }
        if (role.terminalsList === true && option.desktop !== "")
            steps.push('printf "%s\\n" ' + actions._quote(option.desktop)
                + ' > "$HOME/.config/xdg-terminals.list"')
        // env -u BROWSER on the set as well as the get: with $BROWSER in
        // the environment, xdg-settings acts on that instead of the XDG
        // database and reports success either way.
        if (role.xdgBrowser === true && option.desktop !== "")
            steps.push("env -u BROWSER xdg-settings set default-web-browser "
                + actions._quote(option.desktop))
        if (role.mimes.length > 0 && option.desktop !== "")
            steps.push("xdg-mime default " + actions._quote(option.desktop)
                + " " + role.mimes.join(" "))
        if (role.state !== "")
            steps.push("hyprctl reload >/dev/null")

        if (steps.length === 0) return

        actions.setProc.message = option.label + " is now the default " + role.noun
        actions.setProc.detail = role.state !== "" ? option.command : option.desktop
        actions.setProc.command = ["sh", "-c", steps.join(" && ")]
        actions.setProc.running = false
        actions.setProc.running = true
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

    // ── The wikis, as their own window ───────────────────
    // Learn › Hyprland and Learn › Arch. `--app=<url>` is the
    // chromium-family flag that drops the tab strip, the address bar and
    // the rest of the browser chrome: the same trick a browser's own
    // "install this site as an app" performs, without installing
    // anything, and the whole of what makes a wiki feel like an app
    // rather than one more tab to lose.
    //
    // The browser is whichever one Setup › Defaults chose, asked of
    // vars.lua exactly the way a keybind asks (`varsCur`), so these open
    // in whatever SUPER+B opens — and a Brave that arrived as a
    // flatpak gets the flag handed past its `flatpak run`, where it
    // belongs.
    //
    // Firefox is the one family with no --app left, so it falls back to
    // xdg-open, as does a machine that has no answer at all: an ordinary
    // tab is a worse window than an app window, and a wiki that doesn't
    // open is worse than both.
    //
    // Detached, as services/Terminal.qml's spawns are, and for the same
    // reason: uwsm-app doesn't hand the browser off and return, it stays
    // until the browser exits. A reused Process would kill the first
    // wiki's window when the second opened — and the whole browser with
    // it, if this was what started it.
    function openWebApp(url) {
        const script = [
            actions.varsCur,
            "url=" + actions._quote(url),
            'cmd="$(cur browser)"',
            'case "$cmd" in *firefox*|*librewolf*|*waterfox*|*zen*) cmd="" ;; esac',
            '[ -n "$cmd" ] || exec ' + Theme.appLauncherPrefix + ' -- xdg-open "$url"',
            // $cmd is a command line and not a binary — "uwsm-app --
            // flatpak run com.brave.Browser --password-store=basic" — so
            // it has to become words again before it can be run. `eval
            // set --` is that, and it leaves the url out of the eval
            // entirely: it goes on as one more argument afterwards,
            // where nothing re-splits it.
            'eval "set -- $cmd"',
            'exec "$@" "--app=$url"'
        ].join("\n")

        Quickshell.execDetached(["sh", "-c", script])
    }

    // Whatever a row couldn't do, said out loud — see `probeNames` above.
    function refuse(label, tool) {
        Notifications.post(label + " needs " + tool,
            tool + " isn't installed", "critical", "Conf", "")
    }
}
