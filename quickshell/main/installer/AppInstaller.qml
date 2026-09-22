import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

// One search box over pacman, the AUR and Flathub at once.
//
// The shell's installer, and the reason systemsettings/
// SettingsPackagesTab.qml is now an Installed/Remove list and nothing
// else. That tab searched all three too, and then showed one source at
// a time, because it was arrived at with a source already chosen — the
// Conf menu deep-linked "search Flatpak". Right for a settings tab you
// open knowing what you want; wrong for "how do I install Obsidian",
// which is the question this window is for: you do not know yet whether
// the answer is a repo package, an AUR build or a flatpak, and picking
// the backend first is being asked to answer the question in order to
// ask it.
//
// So: one ranked list, three badges, and what follows from that —
//
//   * Results are ranked by how well the *name* matches, not grouped by
//     where they came from, so `firefox` puts the repo package on top
//     however long yay took to answer.
//   * Each source reports separately while it works. pacman answers in
//     a few hundred ms, `yay -Ss` takes seconds against the AUR RPC,
//     and one shared spinner makes the fast answer feel as slow as the
//     slow one. The chips fill in as each lands.
//   * The filter chips narrow a list that is already there instead of
//     choosing what to fetch, so switching is instant and reversible.
//   * `flatpak search` does not say what is already installed, so this
//     asks `flatpak list` once at startup and marks rows itself —
//     otherwise every flatpak looks installable, including the ones on
//     this machine right now.
//
// The install paths came from the packages tab and are unchanged:
// pacman and flatpak go through PasswordPrompt + PrivilegedExec
// (`sudo -S`, no polkit agent in this session), and the AUR goes to a
// real terminal because `yay` wants to show a PKGBUILD diff and ask
// about it. See services/PrivilegedExec.qml's header for why the first
// two aren't a terminal too. Flatpak installs are system scope because
// flathub is registered system-wide here — a --user install fails
// before it reaches the network.
//
// Removal stays in the settings tab. This window is the answer to "get
// me this", which is a thing you do by name; removal is a thing you do
// by looking at a list of what you already have.
ShellSurface {
    id: installer

    surfaceNamespace: "quickshell:installer"
    surfaceName: "installer"

    onSurfaceOpened: (query) => {
        if (!query) return
        searchInput.text = query
        installer.query = query
        installer.runSearch()
    }
    focusTarget: searchInput

    // 220, not ShellSurface's 200: this fades on the shell-wide panel
    // duration, and a refactor is not the place to quietly shorten it.
    exitDuration: Theme.animPanel

    anchors { top: true; bottom: true; left: true; right: true }


    // ── State ─────────────────────────────────────────────
    property string query: ""
    property var results: []
    // "All" | "Pacman" | "AUR" | "Flatpak"
    property string sourceFilter: "All"
    property int selectedIndex: 0

    property bool searchingPacman: false
    property bool searchingAur: false
    property bool searchingFlatpak: false
    readonly property bool searching: installer.searchingPacman
        || installer.searchingAur || installer.searchingFlatpak

    // True once a search has actually been run, so the empty list can
    // tell "nothing matched" apart from "you haven't typed anything".
    property bool searched: false

    // Application ids of the flatpaks already on this machine, as an
    // object used as a set — `flatpak search` won't say.

    readonly property var visibleResults: installer.sourceFilter === "All"
        ? installer.results
        : installer.results.filter(r => r.source === installer.sourceFilter)

    function countFor(source) {
        return installer.results.filter(r => r.source === source).length
    }

    function busyFor(source) {
        if (source === "Pacman") return installer.searchingPacman
        if (source === "AUR") return installer.searchingAur
        if (source === "Flatpak") return installer.searchingFlatpak
        return installer.searching
    }

    function badgeFor(source) {
        if (source === "Pacman") return Appearance.badgePacman
        if (source === "AUR") return Appearance.badgeAur
        return Appearance.badgeFlatpak
    }

    // ── Open/close ────────────────────────────────────────
    // The flatpak inventory is asked for once, when this window is first
    // built — the installer is the only surface that wants it before the
    // packages window has ever been opened.
    Component.onCompleted: if (!Packages.loadedOnce) Packages.refresh()

    // Open on a query, which is what the Conf menu's Install row and
    // `qs ipc call installer find <text>` both come in on. The IpcHandler
    // itself lives on services/Panels.qml with every other window's, so
    // the call works before this window has ever been built.
    // The query rides in on open() and arrives at onSurfaceOpened, so
    // one path serves the keybind, the IPC and the Conf menu row alike.
    function find(text) { installer.open(text) }

    // This window does not exist until something asks for it, and the
    // request that caused shell.qml to build it never reaches the
    // Connections below — they weren't subscribed yet. So the first open
    // is Component.onCompleted's, and every later one arrives here. Same
    // arrangement as launcher/Launcher.qml, which spells it out in full.
    // ── Searching ─────────────────────────────────────────
    // Typing doesn't search. Three processes per keystroke would queue
    // `yay -Ss` runs faster than they finish, and the window would spend
    // its time rendering the results of a prefix you have already typed
    // past. The timer restarts on every edit, so the searches go out
    // once the typing stops.
    Timer {
        id: debounce
        interval: 350
        onTriggered: installer.runSearch()
    }

    // Short queries match thousands of packages and none of them
    // usefully — `-Ss a` is a wall of noise that takes seconds to
    // render.
    readonly property int minQueryLength: 2

    function runSearch() {
        const q = installer.query.trim()
        if (q.length < installer.minQueryLength) {
            installer.results = []
            installer.searched = false
            return
        }

        installer.results = []
        installer.selectedIndex = 0
        installer.searched = true
        // A filter is about the list in front of you, not a standing
        // preference: carrying "Flatpak" over into the next query is how
        // you search for ripgrep and get told there is one result.
        installer.sourceFilter = "All"

        installer.searchingPacman = true
        pacmanSearch.command = ["pacman", "-Ss", q]
        pacmanSearch.running = false
        pacmanSearch.running = true

        installer.searchingAur = true
        aurSearch.command = ["yay", "-Ss", "--aur", q]
        aurSearch.running = false
        aurSearch.running = true

        installer.searchingFlatpak = true
        flatpakSearch.command = ["flatpak", "search",
                                 "--columns=name,description,application", q]
        flatpakSearch.running = false
        flatpakSearch.running = true
    }

    // How well a package name answers the query. Name only, on purpose:
    // descriptions match far too eagerly ("firefox" appears in the
    // description of every extension and theme for it), and a list
    // sorted by anything that generous puts the actual package below a
    // dozen of its accessories.
    function rank(name, q) {
        const h = name.toLowerCase()
        const n = q.toLowerCase()
        if (h === n) return 1000
        // firefox-developer-edition ranks above firefoxpwa: a separator
        // means the query is a whole word here, not a prefix of a
        // longer one.
        if (h.startsWith(n + "-") || h.startsWith(n + "_")) return 900 - h.length
        if (h.startsWith(n)) return 800 - h.length
        const idx = h.indexOf(n)
        if (idx !== -1) return 600 - idx * 4 - h.length
        // Matched the description rather than the name — the backend
        // thought it was relevant and we have no better opinion.
        return 200 - h.length
    }

    // pacman and yay share a two-line format:
    //   repo/name version [installed]
    //       Description text
    function parsePacmanish(text, source) {
        const lines = text.split("\n")
        const out = []
        let i = 0
        while (i < lines.length) {
            const header = lines[i]
            if (header.trim() === "" || header.startsWith(" ") || header.startsWith("\t")) {
                i++
                continue
            }
            const m = header.match(/^(\S+)\/(\S+)\s+(\S+)/)
            if (!m) { i++; continue }

            const name = m[2]
            let description = ""
            const next = i + 1 < lines.length ? lines[i + 1] : ""
            if (next.startsWith(" ") || next.startsWith("\t")) {
                description = lines[i + 1].trim()
                i += 2
            } else {
                i += 1
            }

            out.push({
                source: source,
                id: name,
                name: name,
                repo: m[1],
                version: m[3],
                description: description,
                installed: header.includes("[installed"),
                installing: false,
                rank: installer.rank(name, installer.query.trim())
            })
        }
        return out
    }

    function parseFlatpak(text) {
        const out = []
        for (const line of text.split("\n")) {
            if (line.trim() === "") continue
            const parts = line.split("\t")
            if (parts.length < 3) continue
            if (parts[0] === "Name") continue   // header row
            const appId = parts[2]
            out.push({
                source: "Flatpak",
                id: appId,
                name: parts[0],
                repo: "flathub",
                version: "",
                description: parts[1],
                installed: Packages.hasFlatpak(appId),
                installing: false,
                // Flathub names are titles ("Visual Studio Code"), not
                // package names, so rank the id too and keep whichever
                // answers better.
                rank: Math.max(installer.rank(parts[0], installer.query.trim()),
                               installer.rank(appId, installer.query.trim()))
            })
        }
        return out
    }

    // Merging keeps the list sorted as a whole rather than appending
    // each source's block, which is what makes the three backends read
    // as one answer instead of three.
    function mergeIn(entries) {
        const inflight = {}
        installer.results.forEach(r => {
            if (r.installing) inflight[r.source + ":" + r.id] = true
        })
        entries.forEach(e => {
            if (inflight[e.source + ":" + e.id]) e.installing = true
        })

        const merged = installer.results.concat(entries)
        merged.sort((a, b) => b.rank - a.rank || a.name.localeCompare(b.name))
        installer.results = merged

        // A result landing under the cursor must not move what pressing
        // Enter would install, so the selection is clamped, never reset.
        if (installer.selectedIndex >= installer.visibleResults.length)
            installer.selectedIndex = Math.max(0, installer.visibleResults.length - 1)
    }

    Process {
        id: pacmanSearch
        stdout: StdioCollector {
            onStreamFinished: {
                installer.mergeIn(installer.parsePacmanish(text, "Pacman"))
                installer.searchingPacman = false
            }
        }
        onExited: (exitCode, exitStatus) => {
            // pacman exits 1 on "no results", which is an answer, not a
            // failure — the collector has already delivered whatever
            // there was.
            installer.searchingPacman = false
        }
    }

    Process {
        id: aurSearch
        stdout: StdioCollector {
            onStreamFinished: {
                installer.mergeIn(installer.parsePacmanish(text, "AUR"))
                installer.searchingAur = false
            }
        }
        onExited: (exitCode, exitStatus) => installer.searchingAur = false
    }

    Process {
        id: flatpakSearch
        stdout: StdioCollector {
            onStreamFinished: {
                installer.mergeIn(installer.parseFlatpak(text))
                installer.searchingFlatpak = false
            }
        }
        onExited: (exitCode, exitStatus) => installer.searchingFlatpak = false
    }

    // ── What flatpaks are already here ────────────────────
    // services/Packages.qml's, since 2026-09-21. It is asked once at
    // startup and again after an install rather than per search: the
    // answer changes only when something installs something, and
    // `flatpak list` is slow enough to be visible on every keystroke.
    //
    // This file used to run that list itself, with its own flags, its own
    // "Application ID" header skip and no guard for a machine that has no
    // flatpak at all — which packages/PackagesList.qml and
    // menu/MenuActions.qml each also had, differently.
    Connections {
        target: Packages
        function onRefreshed() {
            // Re-mark anything already on screen.
            installer.results = installer.results.map(r => {
                if (r.source === "Flatpak" && Packages.hasFlatpak(r.id)) r.installed = true
                return r
            })
        }
    }

    // ── Install ───────────────────────────────────────────
    function setInstalling(source, id, value) {
        installer.results = installer.results.map(r => {
            if (r.source === source && r.id === id) r.installing = value
            return r
        })
    }

    function setInstalled(source, id) {
        installer.results = installer.results.map(r => {
            if (r.source === source && r.id === id) {
                r.installing = false
                r.installed = true
            }
            return r
        })
    }

    property string status: ""

    function say(message) { installer.status = message }

    function install(entry) {
        if (!entry || entry.installed || entry.installing) return
        if (entry.source === "Pacman") installer.installPacman(entry.id)
        else if (entry.source === "AUR") installer.installAur(entry.id)
        else installer.installFlatpak(entry.id)
    }

    function installPacman(pkg) {
        pwPrompt.ask(
            "Install " + pkg,
            "pacman -S " + pkg,
            (password) => {
                installer.setInstalling("Pacman", pkg, true)
                PrivilegedExec.run(
                    ["pacman", "-S", "--noconfirm", pkg],
                    password,
                    () => {
                        pwPrompt.close()
                        installer.setInstalled("Pacman", pkg)
                        installer.say(pkg + " installed")
                    },
                    (message) => {
                        installer.setInstalling("Pacman", pkg, false)
                        pwPrompt.showError(message)
                    }
                )
            }
        )
    }

    // The AUR build is interactive by nature — yay shows the PKGBUILD
    // and asks — so it gets a terminal rather than the password path.
    // That terminal is detached, and the Process here exits as soon as
    // it has been launched rather than when the build finishes, so the
    // only honest way to notice the install landing is to watch for the
    // package appearing.
    Process { id: aurInstall }

    function installAur(pkg) {
        installer.setInstalling("AUR", pkg, true)
        installer.say("Review " + pkg + " in the terminal")
        aurInstall.command = [Theme.appLauncherPrefix, "--", Theme.terminal,
                              "-e", "yay", "-S", pkg]
        aurInstall.running = false
        aurInstall.running = true
        aurPoll.pkg = pkg
        aurPoll.ticks = 0
        aurPoll.running = true
    }

    Timer {
        id: aurPoll
        property string pkg: ""
        property int ticks: 0
        // ~90s, the same budget main's packages tab gives a yay build
        // before it stops watching. Giving up only drops the spinner —
        // the build in the terminal is unaffected either way.
        readonly property int maxTicks: 45
        interval: 2000
        repeat: true
        onTriggered: {
            aurPoll.ticks++
            if (aurPoll.ticks > aurPoll.maxTicks) {
                aurPoll.running = false
                installer.setInstalling("AUR", aurPoll.pkg, false)
                return
            }
            aurCheck.command = ["pacman", "-Q", aurPoll.pkg]
            aurCheck.running = false
            aurCheck.running = true
        }
    }

    Process {
        id: aurCheck
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) return
            aurPoll.running = false
            installer.setInstalled("AUR", aurPoll.pkg)
            installer.say(aurPoll.pkg + " installed")
        }
    }

    // System scope, not --user: flathub is registered system-wide here,
    // and a --user install can only pull from remotes the user
    // installation knows about — it fails before it reaches the
    // network. Root is what system scope needs, hence the same password
    // path pacman takes.
    function installFlatpak(appId) {
        pwPrompt.ask(
            "Install " + appId,
            "flatpak install --system flathub " + appId,
            (password) => {
                installer.setInstalling("Flatpak", appId, true)
                PrivilegedExec.run(
                    ["flatpak", "install", "-y", "--system", "flathub", appId],
                    password,
                    () => {
                        pwPrompt.close()
                        installer.setInstalled("Flatpak", appId)
                        installer.say(appId + " installed")
                        Packages.refresh()
                    },
                    (message) => {
                        installer.setInstalling("Flatpak", appId, false)
                        pwPrompt.showError(message)
                    }
                )
            }
        )
    }

    // ── Keyboard ──────────────────────────────────────────
    function move(delta) {
        const n = installer.visibleResults.length
        if (n === 0) return
        installer.selectedIndex = Math.max(0, Math.min(n - 1, installer.selectedIndex + delta))
        resultList.positionViewAtIndex(installer.selectedIndex, ListView.Contain)
    }

    function cycleFilter(delta) {
        const order = ["All", "Pacman", "AUR", "Flatpak"]
        const at = order.indexOf(installer.sourceFilter)
        installer.sourceFilter = order[(at + delta + order.length) % order.length]
        installer.selectedIndex = 0
        resultList.positionViewAtBeginning()
    }

    mask: Region { item: box }

    // ── The window ────────────────────────────────────────
    Rectangle {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter
        // Sized off the surface with a ceiling, not fixed at 720x560.
        // Rows on screen at once is the whole benefit of a bigger
        // window here — a `-Ss` against three backends routinely
        // answers with dozens, and scrolling past them is the tax the
        // small box charged. The ceiling is because none of that is
        // true of the search field, which on a 4K monitor would
        // otherwise be a metre of empty box with six words in it.
        width: Math.min(1040, Math.round(parent.width * 0.6))
        height: Math.min(820, Math.round(parent.height * 0.76))
        // Slightly above centre: the window grows downward from where
        // the eye already is after a keybind, and a list that starts
        // higher has further to run before it needs scrolling.
        y: Math.round((parent.height - box.height) / 2.6)
        radius: Theme.radius
        color: Appearance.surface
        border.width: 1
        border.color: Appearance.border

        opacity: installer.shown ? 1 : 0
        scale: installer.shown ? 1 : 0.97
        Behavior on opacity {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard }
        }
        Behavior on scale {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingDecel }
        }

        layer.enabled: true
        layer.effect: PopupShadow {}
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // ── Title ─────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Install apps"
                    color: Appearance.fgStrong
                    font.bold: true
                    font.pixelSize: Theme.fontLarge
                    font.family: Theme.font
                }

                Text {
                    text: "one search, three sources"
                    color: Appearance.fgFaint
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }

                Text {
                    text: installer.status
                    color: Appearance.green
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    elide: Text.ElideRight
                    Layout.maximumWidth: 240
                }
            }

            // ── Search field ──────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: Theme.radius
                color: Appearance.surfaceAlt
                border.width: 1
                border.color: searchInput.activeFocus ? Appearance.accent : Appearance.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: ""
                        color: Appearance.fgFaint
                        font.pixelSize: Theme.fontNormal
                        font.family: Theme.font
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        color: Appearance.fg
                        font.pixelSize: Theme.fontBig
                        font.family: Theme.font
                        clip: true
                        selectByMouse: true
                        selectionColor: Appearance.selected
                        verticalAlignment: TextInput.AlignVCenter

                        onTextChanged: {
                            installer.query = text
                            debounce.restart()
                        }

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                installer.close()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down) {
                                installer.move(1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up) {
                                installer.move(-1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                // Enter with the debounce still pending
                                // means "search now" — waiting out a
                                // timer you have already answered for is
                                // the one thing debouncing must not do.
                                if (debounce.running) {
                                    debounce.stop()
                                    installer.runSearch()
                                } else {
                                    installer.install(
                                        installer.visibleResults[installer.selectedIndex])
                                }
                                event.accepted = true
                            } else if (event.key === Qt.Key_Tab) {
                                installer.cycleFilter(1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Backtab) {
                                installer.cycleFilter(-1)
                                event.accepted = true
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search pacman, the AUR and Flathub…"
                            color: Appearance.placeholder
                            font.pixelSize: Theme.fontBig
                            font.family: Theme.font
                            visible: searchInput.text.length === 0
                        }
                    }
                }
            }

            // ── Source chips ──────────────────────────────
            // Each one says what its backend is doing: a count once it
            // has answered, a dot while it is still out. main's tab has
            // a single spinner for all three, which reads as "nothing
            // has answered yet" for as long as the slowest one takes.
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    // A plain list of names, not a list of objects
                    // carrying the busy flags: the model would then be a
                    // binding on those flags, and every delegate would be
                    // destroyed and rebuilt each time a backend answered.
                    model: ["All", "Pacman", "AUR", "Flatpak"]

                    delegate: Rectangle {
                        id: chip
                        required property string modelData

                        readonly property bool active: installer.sourceFilter === chip.modelData
                        readonly property bool busy: installer.busyFor(chip.modelData)
                        readonly property int count: chip.modelData === "All"
                            ? installer.results.length : installer.countFor(chip.modelData)

                        implicitWidth: chipRow.implicitWidth + 20
                        implicitHeight: 26
                        radius: Theme.radius
                        color: chip.active ? Appearance.selected
                             : chipHover.hovered ? Appearance.hover : "transparent"
                        border.width: 1
                        border.color: chip.active ? Appearance.accent : Appearance.border

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                implicitWidth: 8
                                implicitHeight: 8
                                radius: 4
                                color: installer.badgeFor(chip.modelData)
                                visible: chip.modelData !== "All"
                            }

                            Text {
                                text: chip.modelData
                                color: chip.active ? Appearance.fgStrong : Appearance.fgSoft
                                font.pixelSize: Theme.fontSmall
                                font.family: Theme.font
                            }

                            Text {
                                text: chip.busy ? "…" : chip.count
                                color: Appearance.fgFaint
                                font.pixelSize: Theme.fontSmall
                                font.family: Theme.font
                                visible: installer.searched
                            }
                        }

                        HoverHandler { id: chipHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                installer.sourceFilter = chip.modelData
                                installer.selectedIndex = 0
                                resultList.positionViewAtBeginning()
                                searchInput.forceActiveFocus()
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            Divider {}

            // ── Results ───────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: resultList
                        anchors.fill: parent
                        clip: true
                        model: installer.visibleResults
                        boundsBehavior: Flickable.StopAtBounds
                        spacing: 2

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index

                            width: ListView.view.width
                            height: 52
                            radius: Theme.radius
                            color: row.index === installer.selectedIndex ? Appearance.selected
                                 : rowHover.hovered ? Appearance.hover : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                // Fixed width so the names line up down the
                                // list: three sources means three badge
                                // widths, and ragged left edges on a list
                                // you read by scanning is a tax for nothing.
                                Rectangle {
                                    implicitWidth: 58
                                    implicitHeight: 18
                                    radius: Theme.radius
                                    color: row.modelData.source === "Pacman" ? Appearance.badgePacman
                                         : row.modelData.source === "AUR" ? Appearance.badgeAur
                                         : Appearance.badgeFlatpak

                                    Text {
                                        anchors.centerIn: parent
                                        text: row.modelData.source
                                        color: Appearance.fg
                                        font.pixelSize: Theme.fontTiny
                                        font.family: Theme.font
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            text: row.modelData.name
                                            color: Appearance.fgStrong
                                            font.pixelSize: Theme.fontNormal
                                            font.family: Theme.font
                                            Layout.maximumWidth: 420
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: row.modelData.version !== ""
                                                ? row.modelData.version : row.modelData.id
                                            color: Appearance.fgDim
                                            font.pixelSize: Theme.fontTiny
                                            font.family: Theme.font
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Text {
                                        text: row.modelData.description
                                        color: Appearance.fgFaint
                                        font.pixelSize: Theme.fontTiny
                                        font.family: Theme.font
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    implicitWidth: actionLabel.implicitWidth + 18
                                    implicitHeight: 26
                                    radius: Theme.radius
                                    color: row.modelData.installed ? Appearance.installedBg
                                         : actionHover.hovered ? Appearance.hoverStrong : "transparent"
                                    border.width: 1
                                    border.color: row.modelData.installed
                                        ? Appearance.green : Appearance.border
                                    opacity: row.modelData.installing ? 0.6 : 1

                                    Text {
                                        id: actionLabel
                                        anchors.centerIn: parent
                                        text: row.modelData.installed ? "Installed"
                                            : row.modelData.installing ? "Working…" : "Install"
                                        color: row.modelData.installed ? Appearance.green : Appearance.fgSoft
                                        font.pixelSize: Theme.fontTiny
                                        font.family: Theme.font
                                    }

                                    HoverHandler { id: actionHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: !row.modelData.installed && !row.modelData.installing
                                        onClicked: installer.install(row.modelData)
                                    }
                                }
                            }

                            HoverHandler {
                                id: rowHover
                                onHoveredChanged: if (hovered) installer.selectedIndex = row.index
                            }
                        }
                    }

                    // One line, three different things it can mean: not
                    // asked yet, asked and still waiting, asked and
                    // answered nothing. It sits in the space the results
                    // would have filled rather than under it.
                    Text {
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: installer.visibleResults.length === 0
                        text: !installer.searched ? "Type at least two letters"
                            : installer.searching ? "Searching…"
                            : installer.results.length > 0
                                ? "No " + installer.sourceFilter + " packages match"
                            : "Nothing matched “" + installer.query.trim() + "”"
                        color: Appearance.fgFaint
                        font.pixelSize: Theme.fontNormal
                        font.family: Theme.font
                    }
                }

                ListScrollBar {
                    Layout.fillHeight: true
                    view: resultList
                    trackColor: Appearance.scrollTrack
                    thumbColor: Appearance.scrollThumb
                }
            }

            // ── Footer ────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "↑↓ select · Enter install · Tab source · Esc close"
                    color: Appearance.fgDim
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.font
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }

                Text {
                    text: installer.searching ? "searching…"
                        : installer.searched ? installer.results.length + " results"
                        : ""
                    color: Appearance.fgDim
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.font
                }
            }
        }
    }

    // Same modal main uses for every privileged action, and the same
    // singleton behind it — this window only supplies the command.
    PasswordPrompt { id: pwPrompt }
}
