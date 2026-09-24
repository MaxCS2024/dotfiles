import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

// The app manager: what is installed, and one search over pacman, the AUR
// and Flathub for what isn't. One window for putting apps on the machine
// and taking them off (user request, 2026-09-24).
//
// It was two until then, this one as the installer and
// packages/PackagesWindow.qml as the list you removed things from. They
// were answering the same question from opposite ends — the installer's
// results already knew which were installed, and the list was every
// installed package with nothing to find one by — so they are one list
// that changes with the search field:
//
//   * Empty field: what is installed. Apps by default — the packages that
//     put a launcher entry in /usr/share/applications, and every flatpak
//     (Packages.isApp) — with a toggle for all of it. The whole `pacman
//     -Qe` list is two hundred lines of base, bc and bluez-utils, and a
//     red button beside `base` is one careless click from a broken system.
//   * Two letters or more: the search. One ranked list, three badges —
//
//       - ranked by how well the *name* matches, not grouped by where it
//         came from, so `firefox` puts the repo package on top however
//         long yay took to answer;
//       - each source reports separately while it works: pacman answers
//         in a few hundred ms, `yay -Ss` takes seconds against the AUR
//         RPC, and one shared spinner makes the fast answer feel as slow
//         as the slow one. The chips fill in as each lands;
//       - `flatpak search` does not say what is installed, so rows are
//         marked from Packages' inventory.
//
// Either way a row offers what can be done to it: Install, or Remove once
// it is here. Enter installs; removing is a click or Delete, never Enter,
// because a flatpak installed for the user alone comes off with no
// password to stop a stray keypress.
//
// A row that is the default terminal, editor, browser or file manager
// says so, and removing it takes a second press, with the status line
// naming what opens instead (user request 2026-09-24). Removing it is
// still allowed: hypr/modules/defaults.lua hands the role to the next
// installed candidate, and the keybinds ask it on each press.
//
// The filter chips narrow a list that is already there instead of choosing
// what to fetch, so switching is instant and reversible, in both views.
//
// Installing and removing are services/Packages.qml's: pacman and system
// flatpaks run behind this window with the password its PasswordPrompt
// collects (`sudo -S`, no polkit agent in this session), and an AUR
// install goes to a real terminal because `yay` wants to show a PKGBUILD
// diff and ask about it. services/packages.js has the rules, and
// tests/packages checks them.
ShellSurface {
    id: manager

    surfaceNamespace: "quickshell:apps"
    surfaceName: "apps"

    // A query opens straight on its search (the Conf menu's search, `qs
    // ipc call apps find <text>`). A bare open keeps whatever was showing.
    onSurfaceOpened: (query) => {
        if (!query) return
        searchInput.text = query
        manager.query = query
        manager.runSearch()
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
    // The installed view's toggle: every package rather than apps only.
    property bool allPackages: false

    property bool searchingPacman: false
    property bool searchingAur: false
    property bool searchingFlatpak: false
    readonly property bool searching: manager.searchingPacman
        || manager.searchingAur || manager.searchingFlatpak

    // Short queries match thousands of packages and none of them
    // usefully — `-Ss a` is a wall of noise that takes seconds to
    // render. Below this the field is empty as far as the list is
    // concerned, and it shows what is installed.
    readonly property int minQueryLength: 2
    readonly property bool browsing: manager.query.trim().length < manager.minQueryLength

    // What is installed, as the installed view lists it: apps unless the
    // toggle says otherwise, by name.
    readonly property var installedList: Packages.installed
        .filter(e => manager.allPackages || Packages.isApp(e))
        .slice()
        .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()))

    // Whichever of the two lists the field is showing, before the chips.
    readonly property var listed: manager.browsing ? manager.installedList : manager.results

    readonly property var visibleResults: manager.sourceFilter === "All"
        ? manager.listed
        : manager.listed.filter(r => r.source === manager.sourceFilter)

    function countFor(source) {
        return source === "All" ? manager.listed.length
            : manager.listed.filter(r => r.source === source).length
    }

    function busyFor(source) {
        if (manager.browsing) return !Packages.loadedOnce
        if (source === "Pacman") return manager.searchingPacman
        if (source === "AUR") return manager.searchingAur
        if (source === "Flatpak") return manager.searchingFlatpak
        return manager.searching
    }

    function badgeFor(source) {
        if (source === "Pacman") return Appearance.badgePacman
        if (source === "AUR") return Appearance.badgeAur
        return Appearance.badgeFlatpak
    }

    // ── Open/close ────────────────────────────────────────
    // The inventory is asked for once, when this window is first built;
    // after that Packages refreshes itself whenever something changes.
    Component.onCompleted: {
        if (!Packages.loadedOnce) Packages.refresh()
        Defaults.refresh()
    }

    function find(text) { manager.open(text) }

    // ── Searching ─────────────────────────────────────────
    // Typing doesn't search. Three processes per keystroke would queue
    // `yay -Ss` runs faster than they finish, and the window would spend
    // its time rendering the results of a prefix you have already typed
    // past. The timer restarts on every edit, so the searches go out
    // once the typing stops.
    Timer {
        id: debounce
        interval: 350
        onTriggered: manager.runSearch()
    }

    function runSearch() {
        const q = manager.query.trim()
        manager.selectedIndex = 0
        // A filter is about the list in front of you, not a standing
        // preference: carrying "Flatpak" over into the next query is how
        // you search for ripgrep and get told there is one result.
        manager.sourceFilter = "All"
        if (q.length < manager.minQueryLength) {
            manager.results = []
            return
        }

        manager.results = []

        manager.searchingPacman = true
        pacmanSearch.command = ["pacman", "-Ss", q]
        pacmanSearch.running = false
        pacmanSearch.running = true

        manager.searchingAur = true
        aurSearch.command = ["yay", "-Ss", "--aur", q]
        aurSearch.running = false
        aurSearch.running = true

        manager.searchingFlatpak = true
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
                rank: manager.rank(name, manager.query.trim())
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
                // Flathub names are titles ("Visual Studio Code"), not
                // package names, so rank the id too and keep whichever
                // answers better.
                rank: Math.max(manager.rank(parts[0], manager.query.trim()),
                               manager.rank(appId, manager.query.trim()))
            })
        }
        return out
    }

    // Merging keeps the list sorted as a whole rather than appending
    // each source's block, which is what makes the three backends read
    // as one answer instead of three.
    function mergeIn(entries) {
        const merged = manager.results.concat(entries)
        merged.sort((a, b) => b.rank - a.rank || a.name.localeCompare(b.name))
        manager.results = merged

        // A result landing under the cursor must not move what pressing
        // Enter would install, so the selection is clamped, never reset.
        if (manager.selectedIndex >= manager.visibleResults.length)
            manager.selectedIndex = Math.max(0, manager.visibleResults.length - 1)
    }

    Process {
        id: pacmanSearch
        stdout: StdioCollector {
            onStreamFinished: {
                manager.mergeIn(manager.parsePacmanish(text, "Pacman"))
                manager.searchingPacman = false
            }
        }
        onExited: (exitCode, exitStatus) => {
            // pacman exits 1 on "no results", which is an answer, not a
            // failure — the collector has already delivered whatever
            // there was.
            manager.searchingPacman = false
        }
    }

    Process {
        id: aurSearch
        stdout: StdioCollector {
            onStreamFinished: {
                manager.mergeIn(manager.parsePacmanish(text, "AUR"))
                manager.searchingAur = false
            }
        }
        onExited: (exitCode, exitStatus) => manager.searchingAur = false
        // Without yay the Process never starts, and a Process that never
        // started emits neither of the two above — the AUR column would
        // say "searching" forever. Stopping running covers that case too.
        onRunningChanged: if (!running) manager.searchingAur = false
    }

    Process {
        id: flatpakSearch
        stdout: StdioCollector {
            onStreamFinished: {
                manager.mergeIn(manager.parseFlatpak(text))
                manager.searchingFlatpak = false
            }
        }
        onExited: (exitCode, exitStatus) => manager.searchingFlatpak = false
    }

    // Re-mark search results after anything changes what is installed —
    // an install or removal from here, the Conf menu or a terminal all
    // end in a Packages refresh. Both ways: a removed package's row goes
    // back to Install.
    Connections {
        target: Packages
        function onRefreshed() {
            // What is installed decides what each default resolves to.
            Defaults.refresh()
            manager.results = manager.results.map(r => {
                r.installed = r.source === "Flatpak" ? Packages.hasFlatpak(r.id) : Packages.has(r.id)
                return r
            })
        }
    }

    // ── Install and remove ────────────────────────────────
    // services/Packages.qml's: which command, whether it needs the
    // password below or a terminal, and when it has landed. This window
    // hands it the row and its prompt, and reads whether a row is busy
    // from it as well.
    property string status: ""
    property bool statusIsError: false

    function say(message, isError) {
        manager.status = message
        manager.statusIsError = isError === true
    }

    function install(entry) {
        if (!entry || entry.installed || Packages.busy(entry.source, entry.id) !== "") return
        if (entry.source === "AUR") manager.say("Review " + entry.id + " in the terminal")
        Packages.install({ source: entry.source, id: entry.id, name: entry.name }, pwPrompt)
    }

    // The row a Remove is waiting to be pressed again on, as source:id,
    // or "". Anything else you do — another row, another search — lets it
    // go, so a second press only ever confirms the warning just read.
    property string confirmKey: ""
    onSelectedIndexChanged: manager.confirmKey = ""
    onQueryChanged: manager.confirmKey = ""

    function roleName(role) { return role.replace("-", " ") }

    // "default terminal", "default editor and browser", or "".
    function defaultTag(entry) {
        const roles = Defaults.rolesFor(entry.id).map(r => manager.roleName(r))
        return roles.length === 0 ? "" : "default " + roles.join(" and ")
    }

    // A search result carries no scope, and a flatpak has to be removed
    // from the installation it is in (--user or --system), so the
    // inventory's own entry is what goes to Packages when there is one.
    function remove(entry) {
        if (!entry || !entry.installed || Packages.busy(entry.source, entry.id) !== "") return

        const key = entry.source + ":" + entry.id
        const roles = Defaults.rolesFor(entry.id)
        if (roles.length > 0 && manager.confirmKey !== key) {
            manager.confirmKey = key
            const after = roles.map(r => {
                const next = Defaults.standIn(r)
                const what = roles.length > 1 ? " as " + manager.roleName(r) : ""
                return next ? next + " takes over" + what
                            : "no " + manager.roleName(r) + " is left"
            })
            manager.say(entry.name + " is your " + manager.defaultTag(entry)
                + ". Remove again to go ahead: " + after.join(", ") + ".", true)
            return
        }

        manager.confirmKey = ""
        const own = Packages.installed.find(e => e.source === entry.source && e.id === entry.id)
        Packages.remove(own || { source: entry.source, id: entry.id, name: entry.name }, pwPrompt)
    }

    // A failure that needed the password is already on the prompt, which
    // stays up to be tried again; anything else is said here.
    Connections {
        target: Packages
        function onFinished(action, entry, ok, message) {
            if (ok) manager.say(message)
            else if (!pwPrompt.shown) manager.say(message, true)
        }
    }

    // ── Keyboard ──────────────────────────────────────────
    function move(delta) {
        const n = manager.visibleResults.length
        if (n === 0) return
        manager.selectedIndex = Math.max(0, Math.min(n - 1, manager.selectedIndex + delta))
        resultList.positionViewAtIndex(manager.selectedIndex, ListView.Contain)
    }

    function cycleFilter(delta) {
        const order = ["All", "Pacman", "AUR", "Flatpak"]
        const at = order.indexOf(manager.sourceFilter)
        manager.sourceFilter = order[(at + delta + order.length) % order.length]
        manager.selectedIndex = 0
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

        opacity: manager.shown ? 1 : 0
        scale: manager.shown ? 1 : 0.97
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
            anchors.margins: Theme.space4
            spacing: Theme.space3

            // ── Title ─────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                Text {
                    text: "Apps"
                    color: Appearance.fgStrong
                    font.bold: true
                    font.pixelSize: Theme.fontLarge
                    font.family: Theme.font
                }

                Text {
                    text: manager.browsing ? "installed" : "search results"
                    color: Appearance.fgMuted
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                }

                // The rest of the row: a warning about removing a default
                // is the one message here that has to be read whole.
                Text {
                    text: manager.status
                    color: manager.statusIsError ? Appearance.red : Appearance.green
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                }
            }

            // ── Search field ──────────────────────────────
            // Focus shows as the caret, not an accent ring (STYLE.md §1).
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Theme.radius
                color: Appearance.surfaceAlt
                border.width: 1
                border.color: Appearance.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space3
                    anchors.rightMargin: Theme.space3
                    spacing: Theme.space2

                    Text {
                        text: ""
                        color: Appearance.fgMuted
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
                            manager.query = text
                            debounce.restart()
                        }

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                // Out of a search first, then out of the
                                // window, the way the Conf menu backs out.
                                if (searchInput.text !== "") searchInput.text = ""
                                else manager.close()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down) {
                                manager.move(1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up) {
                                manager.move(-1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                // Enter with the debounce still pending
                                // means "search now" — waiting out a
                                // timer you have already answered for is
                                // the one thing debouncing must not do.
                                if (debounce.running) {
                                    debounce.stop()
                                    manager.runSearch()
                                } else {
                                    manager.install(manager.visibleResults[manager.selectedIndex])
                                }
                                event.accepted = true
                            } else if (event.key === Qt.Key_Delete) {
                                // Delete edits the text while there is
                                // text after the caret; at the end of the
                                // field there is nothing for it to do
                                // there, so it removes the row instead.
                                if (searchInput.cursorPosition === searchInput.text.length) {
                                    manager.remove(manager.visibleResults[manager.selectedIndex])
                                    event.accepted = true
                                }
                            } else if (event.key === Qt.Key_Tab) {
                                manager.cycleFilter(1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Backtab) {
                                manager.cycleFilter(-1)
                                event.accepted = true
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search pacman, the AUR and Flathub to install…"
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
            // has answered, "…" while it is still out.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                Repeater {
                    // A plain list of names, not a list of objects
                    // carrying the busy flags: the model would then be a
                    // binding on those flags, and every delegate would be
                    // destroyed and rebuilt each time a backend answered.
                    model: ["All", "Pacman", "AUR", "Flatpak"]

                    delegate: Rectangle {
                        id: chip
                        required property string modelData

                        readonly property bool active: manager.sourceFilter === chip.modelData
                        readonly property bool busy: manager.busyFor(chip.modelData)

                        implicitWidth: chipRow.implicitWidth + Theme.space5
                        implicitHeight: 28
                        radius: Theme.radius
                        color: chip.active ? SlabStyle.tintSelected
                             : chipHover.hovered ? Appearance.hover : Appearance.clear(Appearance.hover)
                        border.width: chip.active ? 0 : 1
                        border.color: Appearance.border

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Theme.space2

                            Rectangle {
                                implicitWidth: 8
                                implicitHeight: 8
                                radius: 4
                                color: manager.badgeFor(chip.modelData)
                                visible: chip.modelData !== "All"
                            }

                            Text {
                                text: chip.modelData
                                color: chip.active ? Appearance.fgStrong : Appearance.fgSoft
                                font.pixelSize: Theme.fontSmall
                                font.family: Theme.font
                            }

                            Text {
                                text: chip.busy ? "…" : manager.countFor(chip.modelData)
                                color: Appearance.fgMuted
                                font.pixelSize: Theme.fontSmall
                                font.family: Theme.font
                            }
                        }

                        HoverHandler { id: chipHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                manager.sourceFilter = chip.modelData
                                manager.selectedIndex = 0
                                resultList.positionViewAtBeginning()
                                searchInput.forceActiveFocus()
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Apps only, or everything pacman and flatpak know about.
                // The installed view's alone: a search already lists
                // whatever matched.
                Rectangle {
                    id: allToggle
                    visible: manager.browsing
                    implicitWidth: allRow.implicitWidth + Theme.space5
                    implicitHeight: 28
                    radius: Theme.radius
                    color: manager.allPackages ? SlabStyle.tintSelected
                         : allHover.hovered ? Appearance.hover : Appearance.clear(Appearance.hover)
                    border.width: manager.allPackages ? 0 : 1
                    border.color: Appearance.border

                    RowLayout {
                        id: allRow
                        anchors.centerIn: parent
                        spacing: Theme.space2

                        Text {
                            text: manager.allPackages ? "\u{F0132}" : "\u{F0131}"   // nf-md-checkbox_marked / _blank_outline
                            color: manager.allPackages ? Appearance.fgStrong : Appearance.fgSoft
                            font.pixelSize: Theme.fontSmall
                            font.family: Theme.font
                        }

                        Text {
                            text: "All packages"
                            color: manager.allPackages ? Appearance.fgStrong : Appearance.fgSoft
                            font.pixelSize: Theme.fontSmall
                            font.family: Theme.font
                        }
                    }

                    HoverHandler { id: allHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            manager.allPackages = !manager.allPackages
                            manager.selectedIndex = 0
                            resultList.positionViewAtBeginning()
                            searchInput.forceActiveFocus()
                        }
                    }
                }
            }

            Divider {}

            // ── The list ──────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.space2

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: resultList
                        anchors.fill: parent
                        clip: true
                        model: manager.visibleResults
                        boundsBehavior: Flickable.StopAtBounds
                        spacing: 2

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index

                            width: ListView.view.width
                            // Two lines where there is a description to
                            // show — search results — and one otherwise:
                            // pacman's inventory has no descriptions
                            // (one `pacman -Qi` each would be hundreds of
                            // processes), and a blank second line down
                            // the whole installed list is just gaps.
                            height: row.modelData.description ? 52 : 40
                            radius: Theme.radius
                            color: row.index === manager.selectedIndex ? SlabStyle.tintSelected
                                 : rowHover.hovered ? Appearance.hover : Appearance.clear(Appearance.hover)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.space3
                                anchors.rightMargin: Theme.space3
                                spacing: Theme.space2

                                // Fixed width so the names line up down the
                                // list: three sources means three badge
                                // widths, and ragged left edges on a list
                                // you read by scanning is a tax for nothing.
                                Rectangle {
                                    implicitWidth: 56
                                    implicitHeight: 20
                                    radius: Theme.radius
                                    color: manager.badgeFor(row.modelData.source)

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
                                        spacing: Theme.space2

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
                                            color: Appearance.fgMuted
                                            font.pixelSize: Theme.fontTiny
                                            font.family: Theme.font
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Text {
                                        visible: text !== ""
                                        text: row.modelData.description || ""
                                        color: Appearance.fgMuted
                                        font.pixelSize: Theme.fontTiny
                                        font.family: Theme.font
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        elide: Text.ElideRight
                                    }
                                }

                                // Which default this is, if any — the
                                // reason its Remove asks twice.
                                Text {
                                    readonly property string tag: manager.defaultTag(row.modelData)
                                    visible: tag !== ""
                                    text: tag
                                    color: Appearance.fgSoft
                                    font.pixelSize: Theme.fontTiny
                                    font.family: Theme.font
                                }

                                // A flatpak installed for every user needs
                                // the password to come off; one installed
                                // for you alone does not.
                                Text {
                                    visible: row.modelData.scope === "system"
                                    text: "system"
                                    color: Appearance.fgMuted
                                    font.pixelSize: Theme.fontTiny
                                    font.family: Theme.font
                                }

                                // Install, or Remove once it is here. The
                                // two differ by their text colour alone —
                                // one neutral edge on both, no coloured
                                // ring (STYLE.md §1). Filled rather than
                                // see-through: on the selected row's tint
                                // a bare red label all but disappears.
                                Rectangle {
                                    id: actionButton
                                    readonly property bool installed: row.modelData.installed === true
                                    // Packages' answer, so a row being
                                    // changed from anywhere reads as busy.
                                    readonly property bool busy:
                                        Packages.busy(row.modelData.source, row.modelData.id) !== ""
                                    readonly property color hoverFill: actionButton.installed
                                        ? Appearance.dangerBg : Appearance.hoverStrong
                                    implicitWidth: actionLabel.implicitWidth + Theme.space5
                                    implicitHeight: 28
                                    radius: Theme.radius
                                    color: actionHover.hovered && !actionButton.busy
                                        ? actionButton.hoverFill : Appearance.surfaceAlt
                                    border.width: 1
                                    border.color: Appearance.border
                                    opacity: actionButton.busy ? 0.6 : 1

                                    Text {
                                        id: actionLabel
                                        anchors.centerIn: parent
                                        text: actionButton.busy ? "Working…"
                                            : !actionButton.installed ? "Install"
                                            : manager.confirmKey === row.modelData.source + ":" + row.modelData.id
                                                ? "Remove anyway" : "Remove"
                                        color: actionButton.installed && !actionButton.busy
                                            ? Appearance.red : Appearance.fgSoft
                                        font.pixelSize: Theme.fontTiny
                                        font.family: Theme.font
                                    }

                                    HoverHandler { id: actionHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: !actionButton.busy
                                        onClicked: actionButton.installed
                                            ? manager.remove(row.modelData) : manager.install(row.modelData)
                                    }
                                }
                            }

                            HoverHandler {
                                id: rowHover
                                onHoveredChanged: if (hovered) manager.selectedIndex = row.index
                            }
                        }
                    }

                    // What the empty space means, in the space the rows
                    // would have filled.
                    Text {
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: manager.visibleResults.length === 0
                        text: manager.browsing
                            ? (!Packages.loadedOnce ? "Reading what is installed…"
                               : manager.sourceFilter === "All"
                                   ? "Nothing installed" + (manager.allPackages ? "" : " with a launcher entry")
                                   : "No " + manager.sourceFilter
                                       + (manager.allPackages ? " packages" : " apps") + " installed")
                            : manager.searching ? "Searching…"
                            : manager.results.length > 0
                                ? "No " + manager.sourceFilter + " packages match"
                            : "Nothing matched “" + manager.query.trim() + "”"
                        color: Appearance.fgMuted
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
                    text: "↑↓ select · Enter install · Del remove · Tab source · Esc "
                        + (manager.browsing ? "close" : "back to installed")
                    color: Appearance.fgMuted
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.font
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }

                Text {
                    text: manager.browsing
                        ? manager.installedList.length + (manager.allPackages ? " packages" : " apps")
                        : manager.searching ? "searching…"
                        : manager.results.length + " results"
                    color: Appearance.fgMuted
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
