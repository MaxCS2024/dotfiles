import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../theme"
import "../services"
import "../keybinds"

// Conf — one keystroke (SUPER+SPACE) to everything this config can do,
// in the shape of omarchy's menu: a small centred slab, one level of the
// tree at a time, type to narrow, Enter to go in, Backspace to come back
// out.
//
// The slab carries a filter field and the current level, and nothing
// else: the breadcrumb header and the key legend that used to bracket
// them were both removed at the user's request 2026-09-11. Since nothing
// on screen says so any more, the keys are: Up/Down (or Ctrl+n/Ctrl+p)
// to move, Home/End for the ends, Enter or Right to open a row,
// Backspace or Left to back out a level, Escape to back out and then to
// close. Typing filters; Backspace and Left only navigate while the
// field is empty, so they still edit text the rest of the time.
//
// The structure is the user's, spelled out in `buildTree()` below and
// nowhere else — that function is the whole menu. A row is a leaf if it
// has `run` (do something) or `info` (show something); it's a branch if
// it has `children`. Nothing else in this file knows what any particular
// entry means.
//
// Where the leaves go, and why they're not all the same kind of thing:
//
//   * A leaf that has a panel already — Wallpaper, Themes, and
//     Apps › Manage apps — calls Panels and lets the window
//     this shell already built do the work. The menu is a way *in* to
//     those, not a second copy of them.
//   * A leaf whose job is a long, interactive, privileged command —
//     every Update row, System › Check setup — opens a terminal
//     (menu/MenuActions.qml).
//     Those need a password prompt, a y/n per PKGBUILD and a wall of
//     output that deserves a scrollback, none of which belongs behind a
//     spinner in a popup.
//   * A leaf that just answers a question — System › About, Apps ›
//     Defaults — renders inline (menu/MenuInfoView.qml) rather than
//     opening anything at all.
//   * A Features row flips its feature. That runs headless and answers
//     with a notification, unless turning it on has packages to
//     install, which is the terminal case above. See featureRows().
//
// Learn › Keybindings was a fourth kind for a while: a level of rows
// that were each only a fact, answering the question the old Settings
// window's Keybinds pane used to (deleted 2026-09-13). It is an
// ordinary `run` leaf again as of 2026-09-19 — the keys needed more
// width than this slab has, so they have a window of their own
// (keybinds/KeybindsPanel.qml) and this is the way in. Typing still
// finds them from here; see `matches()`.
//
// Lazily constructed (shell.qml) like every other window that isn't the
// bar; the SUPER+SPACE GlobalShortcut lives on services/Panels.qml so it
// exists from the first press of a shell run, before this file has ever
// been built.
ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:menu"
    surfaceName: "menu"
    focusTarget: filterInput

    anchors { top: true; bottom: true; left: true; right: true }

    // 220, not ShellSurface's 200: this fades on the shell-wide panel
    // duration, and a refactor is not the place to quietly shorten it.
    exitDuration: Theme.animPanel

    // Back to the top level, and re-probe: binaries come and go with
    // `pacman -S`, and this menu is exactly where someone lands right
    // after installing one.
    onSurfaceOpened: {
        panel.enter([])
        actions.refresh()
    }

    // What you picked runs once the menu is off the screen rather than
    // behind its own closing animation.
    onSurfaceHidden: if (panel._pending) actTimer.restart()


    // Where in the tree we are, as the labels walked to get here — not
    // the item arrays themselves. Storing the path means `levelItems`
    // re-resolves against a freshly built tree on every change, so a row
    // that depends on live state (Record screen's label, System › About's
    // kernel hint, anything gated on a binary the probe hasn't answered
    // for yet) updates while the menu is open rather than freezing at
    // whatever it said when the level was entered.
    property var path: []
    property int selectedIndex: 0
    // The field itself is the filter state — mirroring it into a property
    // here would just be two things to keep in step.
    readonly property string filter: filterInput.text

    // Non-empty while an info leaf is showing in place of the list.
    property string infoKind: ""

    // The row height and the type scale are theme/ConfStyle.qml's, not
    // this file's: keybinds/KeybindsPanel.qml is a page this menu opens
    // and has to be the same size as it, and two copies of four numbers
    // is how those two drift apart. MenuInfoView takes them as
    // properties for the same reason. Nothing on the slab should read
    // Theme's sizes directly.
    //
    // How many of those rows fit stays here — it is this slab's shape,
    // and the keybinds window has a height ceiling instead.
    readonly property int maxVisibleRows: 10

    // Every binary the tree gates a row on, derived from the tree rather
    // than listed again beside it: a name that fell out of sync would dim
    // its row forever with nothing to say why. buildTree() reads neither
    // `tools` nor this, so there is no loop.
    //
    // The package probes (see MenuActions) are wired the opposite way
    // round on purpose: they read the app lists, which are plain data,
    // instead of walking the tree. Deriving them from the tree would put
    // `actions.packages` inside the expression that computes them — the
    // tree is built from what those probes answer — and that is the loop
    // this pair of comments exists to keep out.
    MenuActions {
        id: actions
        probeNames: panel.treeRequires()
        packageNames: panel.installApps.filter(app => app.pkg).map(app => app.pkg)
        flatpakNames: panel.installApps.filter(app => app.flatpak).map(app => app.flatpak)
    }

    function treeRequires() {
        const found = []
        function walk(items) {
            for (let i = 0; i < items.length; i++) {
                const item = items[i]
                if (item.requires && found.indexOf(item.requires) === -1)
                    found.push(item.requires)
                if (item.children) walk(item.children)
            }
        }
        walk(panel.buildTree())
        return found
    }

    // ── The menu ─────────────────────────────────────────
    // Two decorations over one freshly built tree, both outside
    // buildTree() so that function stays a description of the structure
    // and nothing else: what's missing (dims a row) and what's already
    // installed (annotates one).
    readonly property var tree: panel._markInstalled(
        panel._markAvailability(panel.buildTree(), actions.tools), actions.packages)

    // Six sections, one per job (regrouped at the user's request,
    // 2026-09-24): Capture, Style, Apps, Features, System, Learn. Before
    // that, apps were spread over four top-level entries — a catalogue
    // under Setup beside Install, Remove and Update — Remove and About
    // were branches holding one row each, and nothing reached the
    // optional features at all.
    function buildTree() {
        return [
            // Screenshots go through the shell's own capture path (see
            // Panels.capture) so they land in the same folder, on the
            // same clipboard and in the same notification history as the
            // Print key — the menu is a third way in, not a second
            // implementation.
            { label: "Capture", icon: "", children: [
                { label: "Screenshot (region)", icon: "",
                  requires: "slurp", run: () => Panels.capture("region") },
                { label: "Screenshot (window)", icon: "",
                  requires: "grim", run: () => Panels.capture("window") },
                { label: "Screenshot (screen)", icon: "",
                  requires: "grim", run: () => Panels.capture("screen") },
                { label: actions.recording ? "Stop recording" : "Record screen",
                  icon: "", requires: "wf-recorder",
                  hint: actions.recording ? "recording…" : "",
                  run: () => actions.record() },
                { label: "Colour picker", icon: "",
                  requires: "hyprpicker", run: () => actions.pickColor() }
            ]},

            { label: "Style", icon: "", children: [
                { label: "Wallpaper", icon: "\u{F0248}",
                  run: () => Panels.open("wallpaper", undefined) },
                // The card (theme/ThemesPanel.qml), which switches a
                // palette and, behind its Edit pill, edits one.
                { label: "Themes", icon: "", hint: "palettes",
                  run: () => Panels.open("themes", undefined) }
            ]},

            // Putting apps on the machine, taking them off, keeping them
            // current, and saying which of them opens what.
            { label: "Apps", icon: "\u{F003B}", children: [
                // One window for what is installed and for finding what
                // isn't (apps/AppManager.qml), where Install and Remove
                // were two until 2026-09-24. `search` keeps both words
                // finding it from the top of this menu.
                { label: "Manage apps", icon: "", hint: "install · remove",
                  search: "install remove uninstall packages",
                  run: () => Panels.open("apps", "") },
                // The same install rows, picked from a short list by
                // category rather than searched for.
                { label: "Browse", icon: "\u{F009}", hint: "by category", children: [
                    { label: "Browsers", icon: "", hint: "web",
                      children: panel.browserApps.map(app => panel.installRow(app)) },
                    { label: "Communications", icon: "", hint: "chat",
                      children: panel.communicationApps.map(app => panel.installRow(app)) },
                    { label: "Gaming", icon: "", hint: "launchers",
                      children: panel.gamingApps.map(app => panel.installRow(app)) },
                    { label: "General", icon: "", hint: "everyday",
                      children: panel.generalApps.map(app => panel.installRow(app)) }
                ]},
                // "Update all" is rack's own three-stage update (repo,
                // then AUR, then flatpak, each gated on the one before
                // it); the three rows under it are the single stages, for
                // when only one of them is what you meant.
                { label: "Update", icon: "", children: [
                    { label: "Update all", icon: "", hint: "rack update",
                      run: () => Terminal.rack("update") },
                    { label: "Pacman", icon: "", hint: "pacman -Syu",
                      requires: "sudo",
                      run: () => Terminal.run("sudo pacman -Syu") },
                    { label: "Yay", icon: "", hint: "yay -Sua", requires: "yay",
                      run: () => Terminal.run("yay -Sua") },
                    { label: "Flatpak", icon: "", hint: "flatpak update",
                      requires: "flatpak",
                      run: () => Terminal.run("flatpak update") }
                ]},
                { label: "Defaults", icon: "", hint: "what opens what",
                  children: panel.defaultRoles.map(role => ({
                      label: role.label, icon: role.icon,
                      hint: panel.defaultHint(role),
                      children: panel.defaultRows(role)
                  })) }
            ]},

            // The parts of the desktop `rack features` can turn on and
            // off — see featureRows() below.
            { label: "Features", icon: "\u{F0431}", hint: "optional parts",
              children: panel.featureRows() },

            { label: "System", icon: "", children: [
                { label: "About", icon: "", hint: SystemInfo.kernel,
                  info: "system" },
                // `rack setup` is the one command that answers "is this
                // machine set up": every dependency the shell and the
                // tooling need, and which of them are missing.
                { label: "Check setup", icon: "", hint: "rack setup",
                  run: () => Terminal.rack("setup") }
            ]},

            // The two wikis beside the keys: nearly everything this
            // desktop does, it does because Hyprland or Arch documents
            // it that way, and looking one of those up is the same kind
            // of errand as looking up a key. They open as their own
            // window rather than a tab — see Defaults.openWebApp.
            //
            // Keybindings is a leaf, not a branch: the keys live in
            // their own window now (keybinds/KeybindsPanel.qml).
            // `search` is what keeps them findable from here anyway —
            // see matches() — and the filter travels with them, so
            // "volume" typed on this slab opens that window already
            // narrowed to the volume keys.
            { label: "Learn", icon: "", children: [
                { label: "Keybindings", icon: "",
                  hint: Keybinds.count + " keys",
                  search: Keybinds.searchText,
                  run: () => Panels.open("keybinds", panel.filter) },
                { label: "Hyprland", icon: "\u{F359}", hint: "wiki.hypr.land",
                  run: () => Defaults.openWebApp("https://wiki.hypr.land/") },
                { label: "Arch", icon: "\u{F303}", hint: "wiki.archlinux.org",
                  run: () => Defaults.openWebApp("https://wiki.archlinux.org/") },
                { label: "LazyVim", icon: "\u{F04B2}", hint: "lazyvim.org",
                  run: () => Defaults.openWebApp("https://lazyvim.org/") }
            ]}
        ]
    }

    // ── Features ─────────────────────────────────────────
    // One row per feature in rack/features.json, in that file's order,
    // read through `rack features list` (MenuActions) so that a feature
    // added there shows up here with nothing else to change. Whether one
    // is on is services/Features.qml's, which watches the choices file:
    // the row follows a toggle the moment rack writes it.
    //
    // Picking a row flips it. Off, and on for a feature that is already
    // installed, run headless and say how it went as a notification;
    // on for one that isn't installed opens a terminal, because that
    // installs packages — a password prompt, and yay's PKGBUILD review
    // for the AUR ones. Uninstalling stays `rack features remove`, which
    // lists what it would delete and asks first.
    //
    // A feature that isn't installed never reads "on", whatever its line
    // in the choices file says: nothing of it can be running.
    //
    // One with nothing to switch (lazyvim, ohmyzsh: `"switch": false` in
    // features.json) reads installed or not installed instead, and
    // picking it once it is installed is the removal — in a terminal,
    // where `rack features remove` lists what it would delete and asks
    // before it does.
    readonly property var featureIcons: ({
        dictation: "\u{F036C}",
        earbuds: "\u{F184F}",
        weather: "\u{F0595}",
        lazyvim: "\u{F04B2}",
        ohmyzsh: "\u{F07B7}"
    })

    function featureRows() {
        if (actions.features === null) return [{ label: "Reading…", icon: "" }]
        if (actions.features.length === 0)
            return [{ label: "No features found", icon: "", hint: "rack features list" }]
        return actions.features.map(f => {
            if (!f.switchable) return {
                label: f.label, icon: panel.featureIcons[f.name] || "\u{F0431}",
                hint: f.installed ? "installed" : "not installed",
                installed: f.installed,
                run: () => Terminal.rack("features " + (f.installed ? "remove " : "on ") + f.name,
                    { title: f.label })
            }
            const on = f.installed && Features.on(f.name)
            return {
                label: f.label, icon: panel.featureIcons[f.name] || "\u{F0431}",
                hint: !f.installed ? "not installed" : on ? "on" : "off",
                current: on,
                run: () => !f.installed
                    ? Terminal.rack("features on " + f.name, { title: f.label })
                    : actions.setFeature(f.name, f.label, on ? "off" : "on")
            }
        })
    }

    // ── Learn › Keybindings ──────────────────────────────
    // The list itself moved to keybinds/Keybinds.qml when it outgrew
    // this slab; `bindGroups`, `bindCount` and `bindRow()` went with it,
    // and so did the bind-shaped row the delegate used to draw — a key
    // column, an arrow, and the name on the right.
    //
    // Why it is one row now: forty of them in a 410px popup meant the
    // slab widened for that level alone, the longest names elided beside
    // their keys, and you still walked a group at a time to reach one.
    // The window shows every key at once; this menu keeps the thing it
    // was always better at, which is being the place you type a word.

    // ── Apps › Defaults ──────────────────────────────────
    // What opens what, and a way to change it: one row per role, each
    // offering the candidates this machine actually has. The roles, their
    // candidates, which of those are installed and what picking one does
    // (the keybind, the XDG handler, the Hyprland reload) are all
    // `relay default`'s, read through services/Defaults.qml. What stays
    // here is only what this slab draws: which roles get a row, and their
    // labels and glyphs.
    //
    // Three roles have a row. The fourth, the file manager, came out at
    // the user's request on 2026-09-17 and is still set with `relay
    // default set file-manager <name>`. A key relay doesn't know shows
    // nothing, not an error.
    readonly property var defaultRoles: [
        { key: "terminal", label: "Terminal", icon: "\u{F018D}" },
        { key: "editor", label: "Editor", icon: "\u{F0DC8}" },
        { key: "browser", label: "Browser", icon: "\u{F059F}" }
    ]

    // The role row's own hint is what it resolves to right now. A custom
    // command has no name, so the command itself says more there than
    // "custom" would, minus the uwsm-app the column would otherwise start
    // with.
    function defaultHint(role) {
        const found = Defaults.roles ? Defaults.roles[role.key] : null
        if (!found) return ""
        if (found.source === "custom") return found.command.replace(/^uwsm-app -- /, "")
        // The pick was uninstalled and another stands in: say both.
        if (found.source === "missing") return found.label + ", " + found.wantedLabel + " gone"
        return found.installed ? found.label : found.label + ", not installed"
    }

    // Inert placeholder rows, like the ones under Keybindings: relay is a
    // process, and a level that came up empty for the tenth of a second
    // before it answered would read as "you have no terminals".
    function defaultRows(role) {
        if (Defaults.error !== "")
            return [{ label: "Can't read the defaults", icon: "", hint: Defaults.error }]
        if (Defaults.roles === null) return [{ label: "Reading…", icon: "" }]
        const found = Defaults.roles[role.key]
        const installed = found ? found.candidates.filter(c => c.installed) : []
        if (installed.length === 0) return [{ label: "Nothing installed", icon: "" }]
        return installed.map(c => ({
            label: c.label, icon: "",
            hint: c.default ? "current" : "",
            current: c.default,
            run: () => Defaults.set(role.key, c.name)
        }))
    }

    // Apps › Browse › Gaming. Five launchers because that is how many places a
    // game actually comes from here: Steam's own library, anything Wine
    // or an emulator can be talked into running (Lutris), the Epic and
    // GOG stores (Heroic), a Wine prefix you keep by hand (Bottles), and
    // Minecraft, whose own launcher Prism replaces.
    //
    // The rows are generated from this one list rather than written out
    // beside it, so another launcher is a line here and nothing else —
    // the same shape every other section has. `aur: true` marks the ones
    // that aren't in the official repos (checked with `pacman -Si`): only
    // those go through yay, so the rest install on a machine without it.
    readonly property var gamingApps: [
        { label: "Steam",   icon: "",    pkg: "steam" },
        { label: "Lutris",  icon: "",    pkg: "lutris" },
        { label: "Heroic",  icon: "",    pkg: "heroic-games-launcher-bin", aur: true },
        { label: "Bottles", icon: "\u{F0854}", pkg: "bottles", aur: true },
        { label: "Prism Launcher", icon: "\u{F0373}", pkg: "prismlauncher" }
    ]

    // Apps › Browse › Browsers. All of them as flatpaks, per the user's choice —
    // and flathub is in fact the only source that carries all of them:
    // chromium and firefox are in extra, google-chrome, zen-browser-bin
    // and brave-bin only in the AUR. One row shape and one updater
    // whichever browser you pick.
    //
    // Brave takes a shield rather than its own mark, which this font
    // hasn't got: its whole pitch is the blocker it calls Shields, so the
    // stand-in is at least the right idea.
    readonly property var browserApps: [
        { label: "Brave",         icon: "",          flatpak: "com.brave.Browser" },
        { label: "Chromium",      icon: "\u{F059F}", flatpak: "org.chromium.Chromium" },
        { label: "Firefox",       icon: "",          flatpak: "org.mozilla.firefox" },
        { label: "Google Chrome", icon: "",          flatpak: "com.google.Chrome" },
        { label: "Zen",           icon: "\u{F0B21}", flatpak: "app.zen_browser.zen" }
    ]

    // Apps › Browse › Communications. Discord from flathub, per the user's
    // choice, not extra/discord: the two package the same client
    // (1.0.157 either way today), so what the choice actually picks is
    // which updater it rides — flatpak, where the build is the vendor's
    // own, rather than pacman.
    readonly property var communicationApps: [
        { label: "Discord", icon: "\u{F066F}", flatpak: "com.discordapp.Discord" }
    ]

    // Apps › Browse › General. What doesn't group with anything else: LocalSend
    // for pushing a file at a phone on the same network, Bitwarden for
    // passwords, Obsidian for notes, Spotify for music. Flatpaks per the
    // user's choice, and for two of the four that is the only packaged
    // client anyway -- localsend is in no repo here, and extra carries
    // spotify-launcher, which fetches the vendor's build at runtime,
    // rather than the client itself. Flathub has both as the vendors'
    // own builds.
    //
    // Bitwarden and Obsidian are the two worth knowing about:
    // extra/bitwarden and extra/obsidian both exist and are both already
    // on this machine. Their rows install a second copy beside the
    // pacman one rather than adopting it, and until one is pressed it
    // reads "flatpak" rather than green "installed", because what the
    // probe asks about is the ref that line names. Deliberate -- the
    // section is flatpaks throughout, so a pacman entry would be the odd
    // one out and would ride a different updater.
    readonly property var generalApps: [
        { label: "Bitwarden", icon: "\u{F0BC4}", flatpak: "com.bitwarden.desktop" },
        { label: "LocalSend", icon: "\u{F022A}", flatpak: "org.localsend.localsend_app" },
        { label: "Obsidian",  icon: "\u{E6BB}",  flatpak: "md.obsidian.Obsidian" },
        { label: "Spotify",   icon: "\u{F04C7}", flatpak: "com.spotify.Client" }
    ]

    // Every app the sections name, which is what the probes ask about.
    // Another section joins this concat: that one line is what makes its
    // rows able to say "installed", and the only place outside its own
    // list that has to know it exists.
    readonly property var installApps: panel.gamingApps
        .concat(panel.browserApps, panel.communicationApps, panel.generalApps)

    // What a row runs is services/Packages.qml's, so that a section is a
    // list of apps and nothing else. A row runs after this slab has
    // closed, so there is no window left to ask a password in: Packages
    // takes that as a terminal, with sudo in it for the repo packages and
    // the flatpaks (flathub is a system remote here, and there is no
    // polkit agent), and yay for the AUR ones, which want a PKGBUILD read
    // and a y/n each. It watches for the package to land, and the row's
    // "installed" follows once it has.
    function packageEntry(app) {
        return {
            source: app.flatpak ? "Flatpak" : app.aur ? "AUR" : "Pacman",
            id: app.pkg || app.flatpak,
            name: app.label
        }
    }

    // --needed and -y, so picking a row for something already installed
    // is a no-op that says so rather than a reinstall — which is also why
    // an installed row stays put and stays runnable instead of being
    // hidden or dimmed. It says so itself instead: `installs` is what
    // _markInstalled answers for, so a row tells you what pressing it
    // would actually do before you press it.
    function installRow(app) {
        return {
            label: app.label, icon: app.icon,
            // A pacman name is worth showing — it is what you would type
            // yourself. A reverse-DNS ref is not: com.discordapp.Disc…
            // is all this column would fit, and which manager it comes
            // from is the more useful thing to say in the space. While
            // Packages is installing it, from here or anywhere, that is
            // what it says instead.
            hint: Packages.busy(panel.packageEntry(app).source, app.pkg || app.flatpak) !== ""
                ? "installing…" : app.pkg || "flatpak",
            requires: app.aur ? "yay" : app.pkg ? "sudo" : "flatpak",
            installs: [app.pkg || app.flatpak],
            run: () => Packages.install(panel.packageEntry(app))
        }
    }

    // A row naming a binary in `requires` is dimmed and inert when that
    // binary isn't on PATH — see MenuActions' probe. Walks the tree the
    // build just produced, so the flags are as fresh as `tools` is. A
    // null `tools` means the probe hasn't answered yet, and nothing is
    // held against a row until it has.
    function _markAvailability(items, tools) {
        for (let i = 0; i < items.length; i++) {
            const item = items[i]
            if (item.requires) item.unavailable = tools !== null && tools[item.requires] !== true
            if (item.children) panel._markAvailability(item.children, tools)
        }
        return items
    }

    // The other half of the pair above: `requires` says what a row needs
    // before it can run, `installs` says what it would put on the
    // machine, and this answers the second from the package probes. A
    // null `packages` is those not having answered yet — nothing is
    // claimed either way until they have, so a row never flickers from
    // "installed" to silent on the way into the menu.
    //
    // One path for a row naming one thing and a row naming several.
    // Every row names exactly one today — the "Install all" row that
    // named five is gone — but the count is the answer either way, and
    // "1 of 1 installed" is just a long way of writing "installed".
    //
    // The hint is replaced rather than added to: that column is 130px and
    // already elides a name as long as heroic-games-launcher-bin, and
    // between what a row would install and whether you have it, the
    // second is what you opened this level to find out.
    function _markInstalled(items, packages) {
        if (packages === null) return items
        for (let i = 0; i < items.length; i++) {
            const item = items[i]
            if (item.installs) {
                const have = item.installs.filter(name => packages[name] === true).length
                if (have === item.installs.length) {
                    item.installed = true
                    item.hint = item.installs.length === 1 ? "installed" : "all installed"
                } else if (have > 0) {
                    item.hint = have + " of " + item.installs.length + " installed"
                }
            }
            if (item.children) panel._markInstalled(item.children, packages)
        }
        return items
    }

    // ── Where we are in it ───────────────────────────────
    readonly property var levelItems: {
        let items = panel.tree
        for (let i = 0; i < panel.path.length; i++) {
            let hit = null
            for (let j = 0; j < items.length; j++)
                if (items[j].label === panel.path[i]) { hit = items[j]; break }
            if (!hit || !hit.children) return items
            items = hit.children
        }
        return items
    }

    readonly property var rows: panel.filterRows(panel.levelItems, panel.filter)
    readonly property var current: panel.selectedIndex >= 0 && panel.selectedIndex < panel.rows.length
        ? panel.rows[panel.selectedIndex] : null

    // `search` is a third haystack beside the label and the hint, for a
    // row that stands in for more than it says: Keybindings carries
    // every action and every key in it, so typing "volume" or "super
    // shift" here still finds the row that opens them — which is what
    // those words used to match directly, back when each key was a row
    // of its own. Already lowercased at the source. Nothing else in the
    // tree sets it.
    function matches(item, needle) {
        return item.label.toLowerCase().indexOf(needle) !== -1
            || (item.hint || "").toLowerCase().indexOf(needle) !== -1
            || (item.search || "").indexOf(needle) !== -1
    }

    // Typing narrows the level you're on. If nothing there matches, the
    // search widens to the whole tree rather than showing an empty list:
    // the leaf you want is often two levels down from where you happen to
    // be standing, and "Flatpak" typed at the root should find all three
    // of them. A widened match carries the trail it was found under, both
    // to show as its hint and so activating it lands in the right place.
    function filterRows(items, query) {
        const needle = query.trim().toLowerCase()
        if (needle === "") return items

        const local = items.filter(item => panel.matches(item, needle))
        if (local.length > 0) return local

        return panel.searchTree(panel.tree, [], needle)
    }

    function searchTree(items, trail, needle) {
        let found = []
        for (let i = 0; i < items.length; i++) {
            const item = items[i]
            if (panel.matches(item, needle))
                found.push(Object.assign({}, item, {
                    trail: trail,
                    // The branch it sits directly under, not the whole
                    // trail: "Pacman — Search For Packages" against
                    // "Pacman — Update" already says which is which, and
                    // the full path from the root only gets elided in the
                    // width this column has.
                    hint: trail.length > 0 ? trail[trail.length - 1] : (item.hint || ""),
                    // The installed colour belongs to the hint, so it
                    // goes wherever the hint does: a row found from two
                    // levels up says where it lives instead, and
                    // "Gaming" in installed-green would be claiming that
                    // about the wrong thing.
                    installed: trail.length > 0 ? false : item.installed
                }))
            if (item.children)
                found = found.concat(panel.searchTree(item.children, trail.concat([item.label]), needle))
        }
        return found
    }

    onRowsChanged: {
        if (panel.selectedIndex >= panel.rows.length)
            panel.selectedIndex = Math.max(0, panel.rows.length - 1)
    }

    // ── Navigation ───────────────────────────────────────
    function enter(labels) {
        panel.path = labels
        panel.clearFilter()
        panel.selectedIndex = 0
        panel.infoKind = ""
        levelSlide.restart()
    }

    function clearFilter() { filterInput.text = "" }

    // One step back out: a typed filter first, then an info leaf, then a
    // level. Returns false only when there's nothing left to back out of,
    // which is what makes Escape at the root close the menu.
    function back() {
        if (panel.filter !== "") { panel.clearFilter(); return true }
        if (panel.infoKind !== "") { panel.infoKind = ""; return true }
        if (panel.path.length > 0) { panel.enter(panel.path.slice(0, -1)); return true }
        return false
    }

    function activate(row) {
        if (!row) return

        if (row.unavailable) {
            actions.refuse(row.label, row.requires)
            return
        }

        if (row.children) {
            panel.enter((row.trail || panel.path).concat([row.label]))
            return
        }

        if (row.info) {
            panel.infoKind = row.info
            info.load(row.info)
            levelSlide.restart()
            return
        }

        if (row.run) panel.runRow(row)
    }

    // Every action waits for this window to be gone rather than racing
    // it. Two problems, one mechanism:
    //
    //   * a capture tool (grim, slurp, hyprpicker) reads the screen as
    //     the compositor currently has it, and this window — the scrim
    //     especially — is part of that;
    //   * a row that opens another shell window would hand that window a
    //     focus grab while this one is still tearing its own down, and
    //     the compositor resolves the overlap by clearing the new grab.
    //     Its HyprlandFocusGrab reads that as "focus left me" and closes
    //     it again the instant it appeared — wallpaper, themes and
    //     every packages row, all opening and vanishing.
    //
    // So the action is held until the window has actually gone — see the
    // surface, plus one more beat for the compositor to process the unmap
    // and hand focus back. This used to be a per-row `bare` flag that
    // only the capture rows set, which was both a special case in the
    // tree and the wrong fix for the other half of the problem.
    property var _pending: null

    function runRow(row) {
        panel._pending = row.run
        panel.close()
    }

    Timer {
        id: actTimer
        interval: 80
        onTriggered: {
            const run = panel._pending
            panel._pending = null
            if (run) run()
        }
    }

    // Only the slab takes clicks — a near-miss on the backdrop does
    // nothing rather than dismissing the menu, same as the power menu.
    // Focus leaving the window by any other route still closes it.
    mask: Region { item: box }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: panel.shown ? 0.5 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard } }
    }

    Item {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.18)
        implicitWidth: slab.implicitWidth
        implicitHeight: slab.implicitHeight

        opacity: panel.shown ? 1 : 0
        scale: panel.shown ? 1 : 0.98

        Behavior on opacity { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard } }
        Behavior on scale { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingQuint } }

        Rectangle {
            id: slab

            readonly property int pad: 18

            // Narrow enough that a row of nine short words doesn't sit in
            // a field of empty slab (user request 2026-09-11), but the
            // info leaf genuinely needs the room — a CPU model is a
            // long line, and eliding the answer is the one thing that
            // view must not do. So the slab widens for it, on the same
            // easing its height already animates with. (Two other views
            // used to need it and neither does now: Apps › Defaults is
            // a branch of ordinary rows, and Learn › Keybindings is a
            // single row that opens keybinds/KeybindsPanel.qml.)
            implicitWidth: panel.infoKind !== "" ? 430 : 340
            Behavior on implicitWidth {
                NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingDecel }
            }
            implicitHeight: content.implicitHeight + slab.pad * 2
            // The slab grows and shrinks as levels come and go. Animating
            // it keeps a nine-row branch from snapping open under the
            // cursor after a one-row one.
            Behavior on implicitHeight {
                NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingDecel }
            }

            color: Appearance.bar
            // Square, like every window on this desktop:
            // hypr/modules/decorations.lua sets decoration.rounding = 0.
            radius: 0
            border.width: Theme.hyprBorderWidth
            // What shows if the gradient frame below is ever hidden; the
            // Shape covers this band entirely otherwise.
            border.color: Appearance.border

            layer.enabled: true
            layer.effect: PopupShadow {}
            // The window border from the compositor, drawn around a
            // layer surface — see common/HyprFrame.qml. Declared first so
            // everything below paints over it.
            HyprFrame {}

            ColumnLayout {
                id: content
                anchors.fill: parent
                anchors.margins: slab.pad
                spacing: Theme.space4

                // ── Filter ───────────────────────────────
                // The first thing on the slab, per user request
                // 2026-09-11: the breadcrumb row that used to head it
                // (level icon, "Conf › Install › …", match count) is gone,
                // and so is the rule that used to divide this from the
                // list below. There are no rules left anywhere on the slab
                // — the frame is the only line on it — so the layout's own
                // spacing is what separates the field from the level, and
                // it gets a little more of it than the default to do that
                // job alone. What's left of "where am I" is this field's
                // own placeholder, which names the branch being filtered.
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    visible: panel.infoKind === ""

                    TextInput {
                        id: filterInput
                        anchors.fill: parent
                        color: Appearance.fgStrong
                        font.family: Theme.font
                        font.pixelSize: ConfStyle.fontRow
                        clip: true
                        cursorVisible: true

                        onTextChanged: panel.selectedIndex = 0

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                if (!panel.back()) panel.close()
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Down
                                    || (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier))) {
                                panel.step(1)
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Up
                                    || (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))) {
                                panel.step(-1)
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Home) {
                                panel.select(0)
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_End) {
                                panel.select(panel.rows.length - 1)
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                    || event.key === Qt.Key_Right) {
                                // Right only opens when the caret has
                                // nowhere left to go, so it still moves
                                // through text that's been typed.
                                if (event.key === Qt.Key_Right
                                        && filterInput.cursorPosition < filterInput.text.length) return
                                panel.activate(panel.current)
                                event.accepted = true
                                return
                            }
                            // Backspace and Left back out of a level only
                            // when there's no text for them to edit —
                            // otherwise they're ordinary editing keys.
                            if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left)
                                    && filterInput.text.length === 0) {
                                panel.back()
                                event.accepted = true
                                return
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: filterInput.text.length === 0
                        text: panel.path.length === 0 ? "Type to search…" : "Filter " + panel.path[panel.path.length - 1] + "…"
                        color: Appearance.placeholder
                        font.family: Theme.font
                        font.pixelSize: ConfStyle.fontRow
                    }
                }

                // ── The level ────────────────────────────
                // Slides a few pixels on every level change, so going in
                // and coming back out reads as movement rather than as the
                // same list swapping its words.
                Item {
                    id: levelHolder
                    Layout.fillWidth: true
                    implicitHeight: panel.infoKind === "" ? listHeight : info.implicitHeight

                    readonly property int listHeight: panel.rows.length > 0
                        ? Math.min(panel.rows.length, panel.maxVisibleRows) * ConfStyle.rowHeight
                        : 52

                    property real slide: 0
                    transform: Translate { x: levelHolder.slide }
                    opacity: 1 - Math.abs(levelHolder.slide) / 40

                    NumberAnimation {
                        id: levelSlide
                        target: levelHolder
                        property: "slide"
                        from: 12
                        to: 0
                        duration: 160
                        easing.type: Theme.easingQuint
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: panel.infoKind === "" && panel.rows.length === 0
                        text: "Nothing matches"
                        color: Appearance.fgMuted
                        font.family: Theme.font
                        font.pixelSize: ConfStyle.fontRow
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: Theme.space2
                        visible: panel.infoKind === "" && panel.rows.length > 0

                        ListView {
                            id: rowList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: panel.rows
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: menuRow
                                required property var modelData
                                required property int index

                                readonly property bool selected: menuRow.index === panel.selectedIndex
                                readonly property bool branch: !!menuRow.modelData.children
                                readonly property bool dimmed: menuRow.modelData.unavailable === true

                                width: rowList.width
                                height: ConfStyle.rowHeight
                                radius: 0
                                // The wash is the whole of the selection
                                // marker now: the 2px accent rule that used
                                // to run down the left edge of the current
                                // row was removed at the user's request
                                // 2026-09-11. Hover and the keyboard share
                                // this one state — pointing at a row *is*
                                // selecting it here — so there is nothing
                                // the rule was distinguishing that the wash
                                // doesn't.
                                color: menuRow.selected ? SlabStyle.tintSelected : Appearance.clear(SlabStyle.tintSelected)

                                Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space3
                                    anchors.rightMargin: Theme.space3
                                    spacing: Theme.space2

                                    Text {
                                        Layout.preferredWidth: 20
                                        text: menuRow.modelData.icon || ""
                                        color: menuRow.dimmed ? Appearance.disabled
                                             : menuRow.selected ? Appearance.fgStrong : Appearance.fgSoft
                                        font.family: Theme.font
                                        font.pixelSize: ConfStyle.fontIcon
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: menuRow.modelData.label
                                        color: menuRow.dimmed ? Appearance.disabled
                                             : menuRow.selected ? Appearance.fgStrong : Appearance.fg
                                        font.family: Theme.font
                                        font.pixelSize: ConfStyle.fontRow
                                        elide: Text.ElideRight
                                    }

                                    // Three things one column says, in
                                    // the order they override each other:
                                    // what the row can't do (orange),
                                    // what you already have or already
                                    // chose (green), and otherwise
                                    // whatever the row said about itself.
                                    Text {
                                        text: menuRow.dimmed
                                            ? "needs " + menuRow.modelData.requires
                                            : (menuRow.modelData.hint || "")
                                        visible: text !== ""
                                        color: menuRow.dimmed ? Appearance.orange
                                             : (menuRow.modelData.installed
                                                || menuRow.modelData.current) ? Appearance.green
                                             : Appearance.fgDim
                                        font.family: Theme.font
                                        font.pixelSize: ConfStyle.fontHint
                                        elide: Text.ElideRight
                                        // Held to roughly the character
                                        // count it showed before, so the
                                        // slimmer slab spends its width
                                        // on the label rather than here.
                                        Layout.maximumWidth: 124
                                    }

                                    Text {
                                        visible: menuRow.branch
                                        text: ""
                                        color: menuRow.selected ? Appearance.accent : Appearance.fgDim
                                        font.family: Theme.font
                                        font.pixelSize: ConfStyle.fontRow
                                    }
                                }

                                HoverHandler {
                                    cursorShape: Qt.PointingHandCursor
                                    onHoveredChanged: if (hovered) panel.selectedIndex = menuRow.index
                                }

                                TapHandler {
                                    onTapped: {
                                        panel.selectedIndex = menuRow.index
                                        panel.activate(menuRow.modelData)
                                    }
                                }
                            }
                        }

                        // Thinner and square where the launcher's is 4px
                        // and rounded; the thumb arithmetic is the shared
                        // part — see common/ListScrollBar.qml.
                        ListScrollBar {
                            Layout.fillHeight: true
                            view: rowList
                            barWidth: 3
                            barRadius: 0
                            trackColor: Appearance.scrollTrack
                            thumbColor: Appearance.scrollThumb
                        }
                    }

                    MenuInfoView {
                        id: info
                        width: parent.width
                        visible: panel.infoKind !== ""
                        fontBody: ConfStyle.fontRow
                        fontSub: ConfStyle.fontHint
                    }
                }

                // The key legend that used to close the slab ("↑↓ move ·
                // ⏎ open · ⌫ back · esc close") is gone too, per the same
                // request — and its rule with it. Nothing on screen
                // documents the keyboard now; what still works is unchanged
                // and listed in this file's header. Same call the user made
                // for the power menu's keycap chips (see
                // powermenu/PowerMenuPopout.qml).
            }
        }
    }

    function select(index) {
        if (panel.rows.length === 0) return
        panel.selectedIndex = Math.max(0, Math.min(index, panel.rows.length - 1))
        panel.ensureVisible()
    }

    function step(delta) {
        if (panel.rows.length === 0) return
        panel.select((panel.selectedIndex + delta + panel.rows.length) % panel.rows.length)
    }

    function ensureVisible() { rowList.positionViewAtIndex(panel.selectedIndex, ListView.Contain) }
}
