import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"
import "../services/packages.js" as Pkg
import "search.js" as Search

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
//     (Packages.isApp) — and a last row that shows all of it. The whole
//     `pacman -Qe` list is two hundred lines of base, bc and bluez-utils.
//   * Two letters or more: the search. One ranked list —
//
//       - ranked by how well the *name* matches, not grouped by where it
//         came from, so `firefox` puts the repo package on top however
//         long yay took to answer;
//       - each source merges in as it answers: pacman in a few hundred
//         ms, `yay -Ss` in seconds against the AUR RPC;
//       - `flatpak search` does not say what is installed, so rows are
//         marked from Packages' inventory.
//
// It looks and works like the Conf menu it is opened from (user request
// 2026-09-30): the same slab, field and rows, and nothing else on it. It
// had a title and status line, source chips with counts, an "All
// packages" checkbox, coloured source badges, an Install or Remove button
// on every row and a key legend until then. Where each of those went:
//
//   * The source is the row's glyph: pac-man for pacman, a group of
//     people for the AUR, a box for Flathub — the Conf menu's own glyphs
//     for Install › Pacman and AUR.
//   * Tab and Shift+Tab step through All, Pacman, AUR and Flathub; the
//     placeholder names the one you are on, and while there is text in
//     the field a dim word at its right end does (see `fieldNote`).
//   * "Show all packages" is the installed list's last row.
//   * A row is a toggle, like Conf's install rows: Enter or a click
//     installs it, or removes it once it is here. A row that is the
//     default terminal, editor, browser or file manager reads "default",
//     and pressing it only says why not — pick another in System ›
//     Defaults first. (Until 2026-09-30 Enter only installed, removing
//     was Delete or the button, and a default went after a second press.)
//   * What happened is a notification, as it is for everything Conf runs.
//
// Installing and removing are services/Packages.qml's: pacman and system
// flatpaks run behind this window with the password its PasswordPrompt
// collects (`sudo -S`, not the polkit agent), and an AUR
// install goes to a real terminal because `yay` wants to show a PKGBUILD
// diff and ask about it. services/packages.js has the rules, and
// tests/packages checks them. Reading what the searches print, and
// ranking it, is apps/search.js's, which tests/packages checks too.
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
    // "All", or one of Pkg.SOURCES.
    property string sourceFilter: "All"
    // The order Tab steps through them.
    readonly property var filters: ["All"].concat(Pkg.SOURCES)
    property int selectedIndex: 0
    // The installed view's last row: every package rather than apps only.
    property bool allPackages: false

    // How many rows the slab shows before it scrolls. The Conf menu's is
    // ten; a search here answers with dozens, so a few more are worth it.
    readonly property int maxVisibleRows: 12

    // source -> whether its search is still out. Replaced rather than
    // changed in place, so that every binding reading it hears about it.
    property var searchingIn: ({})
    readonly property bool searching: Pkg.SOURCES.some(s => manager.searchingIn[s] === true)

    function setSearching(source, on) {
        const next = Object.assign({}, manager.searchingIn)
        next[source] = on
        manager.searchingIn = next
    }

    // Short queries match thousands of packages and none of them
    // usefully — `-Ss a` is a wall of noise that takes seconds to
    // render. Below this the field is empty as far as the list is
    // concerned, and it shows what is installed.
    readonly property int minQueryLength: 2
    readonly property bool browsing: manager.query.trim().length < manager.minQueryLength

    // What is installed, as the installed view lists it: apps unless the
    // last row says otherwise, by name.
    readonly property var installedList: Packages.installed
        .filter(e => manager.allPackages || Packages.isApp(e))
        .slice()
        .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()))

    // Whichever of the two lists the field is showing, before the source.
    readonly property var listed: manager.browsing ? manager.installedList : manager.results

    function bySource(list) {
        return manager.sourceFilter === "All" ? list
            : list.filter(r => r.source === manager.sourceFilter)
    }

    // The toggle row, at the foot of the installed list once there is
    // one. Its hint is how many rows pressing it would list.
    readonly property var allRow: ({
        toggle: true,
        name: manager.allPackages ? "Show apps only" : "Show all packages",
        count: manager.bySource(Packages.installed
            .filter(e => !manager.allPackages || Packages.isApp(e))).length
    })

    readonly property var visibleResults: {
        const rows = manager.bySource(manager.listed)
        return manager.browsing && Packages.loadedOnce ? rows.concat([manager.allRow]) : rows
    }

    readonly property var sourceIcons: ({
        [Pkg.PACMAN]: "\u{F0BAF}",
        [Pkg.AUR]: "\u{F0849}",
        [Pkg.FLATHUB]: "\u{F03D7}"
    })

    function labelFor(filter) {
        return filter === "All" ? "All" : Pkg.LABELS[filter]
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
        // preference: carrying "Flathub" over into the next query is how
        // you search for ripgrep and get told there is one result.
        manager.sourceFilter = "All"
        if (q.length < manager.minQueryLength) {
            manager.results = []
            return
        }

        manager.results = []

        manager.searchingIn = {}

        manager.setSearching(Pkg.PACMAN, true)
        pacmanSearch.run(["pacman", "-Ss", q])
        manager.setSearching(Pkg.AUR, true)
        aurSearch.run(["yay", "-Ss", "--aur", q])
        manager.setSearching(Pkg.FLATHUB, true)
        flatpakSearch.run(["flatpak", "search", "--columns=name,description,application", q])
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

    SourceSearch {
        id: pacmanSearch
        onAnswered: text => manager.mergeIn(Search.parsePacmanish(text, Pkg.PACMAN, manager.query.trim()))
        onEnded: manager.setSearching(Pkg.PACMAN, false)
    }

    SourceSearch {
        id: aurSearch
        onAnswered: text => manager.mergeIn(Search.parsePacmanish(text, Pkg.AUR, manager.query.trim()))
        onEnded: manager.setSearching(Pkg.AUR, false)
    }

    SourceSearch {
        id: flatpakSearch
        onAnswered: text => manager.mergeIn(Search.parseFlatpak(text, manager.query.trim(), id => Packages.hasFlatpak(id)))
        onEnded: manager.setSearching(Pkg.FLATHUB, false)
    }

    // Re-mark search results after anything changes what is installed —
    // an install or removal from here, the Conf menu or a terminal all
    // end in a Packages refresh. Both ways: a removed package's row goes
    // back to installable.
    Connections {
        target: Packages
        function onRefreshed() {
            // What is installed decides what each default resolves to.
            Defaults.refresh()
            manager.results = manager.results.map(r => {
                r.installed = Packages.isInstalled(r)
                return r
            })
        }
    }

    // ── Install and remove ────────────────────────────────
    // services/Packages.qml's: which command, whether it needs the
    // password below or a terminal, and when it has landed. This window
    // hands it the row and its prompt, and reads whether a row is busy
    // from it as well.
    function say(title, body, isError) {
        Notifications.post(title, body || "", isError ? "critical" : "normal", "Apps", "")
    }

    // Enter or a click on a row.
    function activate(entry) {
        if (!entry) return
        if (entry.toggle) {
            manager.allPackages = !manager.allPackages
            manager.selectedIndex = 0
            resultList.positionViewAtBeginning()
            return
        }
        if (entry.installed) manager.remove(entry)
        else manager.install(entry)
    }

    function install(entry) {
        if (!entry || entry.installed || Packages.busy(entry.source, entry.id) !== "") return
        Packages.install({ source: entry.source, id: entry.id, name: entry.name }, pwPrompt)
    }

    // "terminal", "editor and browser", or "".
    function defaultRoles(entry) {
        return Defaults.rolesFor(entry.id).map(r => r.replace("-", " ")).join(" and ")
    }

    // A search result carries no scope, and a flatpak has to be removed
    // from the installation it is in (--user or --system), so the
    // inventory's own entry is what goes to Packages when there is one.
    function remove(entry) {
        if (!entry || !entry.installed || Packages.busy(entry.source, entry.id) !== "") return

        const roles = manager.defaultRoles(entry)
        if (roles !== "") {
            manager.say(entry.name + " is your default " + roles,
                "Pick another in System › Defaults before removing it.", true)
            return
        }

        const own = Packages.installed.find(e => e.source === entry.source && e.id === entry.id)
        Packages.remove(own || { source: entry.source, id: entry.id, name: entry.name }, pwPrompt)
    }

    // A failure that needed the password is already on the prompt, which
    // stays up to be tried again; anything else is said here. Packages
    // posts its own notification only for a job with no prompt, so this
    // is the one for everything started from this window.
    Connections {
        target: Packages
        function onFinished(action, entry, ok, message) {
            if (ok) manager.say(message)
            else if (!pwPrompt.shown) manager.say(message, "", true)
        }
    }

    // ── Keyboard ──────────────────────────────────────────
    function select(index) {
        const n = manager.visibleResults.length
        if (n === 0) return
        manager.selectedIndex = Math.max(0, Math.min(n - 1, index))
        resultList.positionViewAtIndex(manager.selectedIndex, ListView.Contain)
    }

    function cycleFilter(delta) {
        const order = manager.filters
        const at = order.indexOf(manager.sourceFilter)
        manager.sourceFilter = order[(at + delta + order.length) % order.length]
        manager.selectedIndex = 0
        resultList.positionViewAtBeginning()
    }

    // The dim word at the right end of the field, for what the
    // placeholder can't say once there is text in the way.
    readonly property string fieldNote: !manager.browsing && manager.searching ? "searching…"
        : manager.sourceFilter !== "All" && searchInput.text !== "" ? manager.labelFor(manager.sourceFilter)
        : ""

    // Only the slab takes clicks — a near-miss on the backdrop does
    // nothing rather than dismissing it, same as the Conf menu.
    mask: Region { item: box }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: manager.shown ? 0.5 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard }
        }
    }

    // ── The slab ──────────────────────────────────────────
    // The Conf menu's (menu/ConfMenu.qml), wider: a package name and its
    // version want more than the menu's 340px.
    Item {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.18)
        implicitWidth: slab.implicitWidth
        implicitHeight: slab.implicitHeight

        opacity: manager.shown ? 1 : 0
        scale: manager.shown ? 1 : 0.98

        Behavior on opacity { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard } }
        Behavior on scale { NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingQuint } }

        Rectangle {
            id: slab

            readonly property int pad: 18

            implicitWidth: Math.min(560, Math.round(manager.width * 0.6))
            implicitHeight: content.implicitHeight + slab.pad * 2
            Behavior on implicitHeight {
                NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingDecel }
            }

            color: Appearance.bar
            // Square, like every window on this desktop.
            radius: 0
            border.width: Theme.hyprBorderWidth
            border.color: Appearance.border

            layer.enabled: true
            layer.effect: PopupShadow {}
            HyprFrame {}

            ColumnLayout {
                id: content
                anchors.fill: parent
                anchors.margins: slab.pad
                spacing: Theme.space4

                // ── Field ─────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 28

                    TextInput {
                        id: searchInput
                        anchors.left: parent.left
                        anchors.right: note.left
                        anchors.rightMargin: Theme.space2
                        anchors.verticalCenter: parent.verticalCenter
                        color: Appearance.fgStrong
                        font.family: Theme.font
                        font.pixelSize: ConfStyle.fontRow
                        clip: true
                        cursorVisible: true
                        selectByMouse: true
                        selectionColor: Appearance.selected

                        onTextChanged: {
                            manager.query = text
                            manager.selectedIndex = 0
                            debounce.restart()
                        }

                        Keys.onPressed: (event) => {
                            const ctrl = event.modifiers & Qt.ControlModifier
                            if (event.key === Qt.Key_Escape) {
                                // Out of a search first, then out of the
                                // window, the way the Conf menu backs out.
                                if (searchInput.text !== "") searchInput.text = ""
                                else manager.close()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_N && ctrl)) {
                                manager.select(manager.selectedIndex + 1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_P && ctrl)) {
                                manager.select(manager.selectedIndex - 1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Home) {
                                manager.select(0)
                                event.accepted = true
                            } else if (event.key === Qt.Key_End) {
                                manager.select(manager.visibleResults.length - 1)
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
                                    manager.activate(manager.visibleResults[manager.selectedIndex])
                                }
                                event.accepted = true
                            } else if (event.key === Qt.Key_Tab) {
                                manager.cycleFilter(1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Backtab) {
                                manager.cycleFilter(-1)
                                event.accepted = true
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text.length === 0
                        text: manager.sourceFilter === "All" ? "Search to install…"
                            : "Filter " + manager.labelFor(manager.sourceFilter) + "…"
                        color: Appearance.placeholder
                        font.family: Theme.font
                        font.pixelSize: ConfStyle.fontRow
                    }

                    Text {
                        id: note
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: manager.fieldNote
                        color: Appearance.fgMuted
                        font.family: Theme.font
                        font.pixelSize: ConfStyle.fontHint
                    }
                }

                // ── The list ──────────────────────────────
                Item {
                    Layout.fillWidth: true
                    implicitHeight: manager.visibleResults.length > 0
                        ? Math.min(manager.visibleResults.length, manager.maxVisibleRows) * ConfStyle.rowHeight
                        : 52

                    // What the empty space means, in the space the rows
                    // would have filled.
                    Text {
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: manager.visibleResults.length === 0
                        text: manager.browsing
                            ? (!Packages.loadedOnce ? "Reading what is installed…"
                               : "No " + manager.labelFor(manager.sourceFilter) + " apps installed")
                            : manager.searching ? "Searching…"
                            : manager.results.length > 0
                                ? "No " + manager.labelFor(manager.sourceFilter) + " packages match"
                            : "Nothing matched “" + manager.query.trim() + "”"
                        color: Appearance.fgMuted
                        font.family: Theme.font
                        font.pixelSize: ConfStyle.fontRow
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: Theme.space2
                        visible: manager.visibleResults.length > 0

                        ListView {
                            id: resultList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: manager.visibleResults
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: row
                                required property var modelData
                                required property int index

                                readonly property bool selected: row.index === manager.selectedIndex
                                readonly property string busy: row.modelData.toggle ? ""
                                    : Packages.busy(row.modelData.source, row.modelData.id)
                                readonly property bool isDefault: row.modelData.installed === true
                                    && !row.modelData.toggle && manager.defaultRoles(row.modelData) !== ""
                                // Green for what you have or chose, like
                                // Conf's install rows. The installed list
                                // is all installed, so there it is only
                                // the defaults that stand out.
                                readonly property bool green: row.busy === "" && (row.isDefault
                                    || (!manager.browsing && row.modelData.installed === true))

                                width: resultList.width
                                height: ConfStyle.rowHeight
                                radius: 0
                                color: row.selected ? Appearance.selected : Appearance.clear(Appearance.selected)
                                Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space3
                                    anchors.rightMargin: Theme.space3
                                    spacing: Theme.space2

                                    Text {
                                        Layout.preferredWidth: 20
                                        text: row.modelData.toggle ? "\u{F0279}"
                                            : manager.sourceIcons[row.modelData.source] || ""
                                        color: row.selected ? Appearance.fgStrong : Appearance.fgSoft
                                        font.family: Theme.font
                                        font.pixelSize: ConfStyle.fontIcon
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: row.modelData.name
                                        color: row.selected ? Appearance.fgStrong : Appearance.fg
                                        font.family: Theme.font
                                        font.pixelSize: ConfStyle.fontRow
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: row.modelData.toggle ? String(row.modelData.count)
                                            : row.busy === "install" ? "installing…"
                                            : row.busy === "remove" ? "removing…"
                                            : row.isDefault ? "default"
                                            : !manager.browsing && row.modelData.installed ? "installed"
                                            : row.modelData.version || ""
                                        visible: text !== ""
                                        color: row.green ? Appearance.green : Appearance.fgDim
                                        font.family: Theme.font
                                        font.pixelSize: ConfStyle.fontHint
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 124
                                    }
                                }

                                HoverHandler {
                                    cursorShape: Qt.PointingHandCursor
                                    onHoveredChanged: if (hovered) manager.selectedIndex = row.index
                                }

                                TapHandler {
                                    onTapped: {
                                        manager.selectedIndex = row.index
                                        manager.activate(row.modelData)
                                        searchInput.forceActiveFocus()
                                    }
                                }
                            }
                        }

                        // Thin and square, as on the Conf slab.
                        ListScrollBar {
                            Layout.fillHeight: true
                            view: resultList
                            barWidth: 3
                            barRadius: 0
                            trackColor: Appearance.scrollTrack
                            thumbColor: Appearance.scrollThumb
                        }
                    }
                }
            }
        }
    }

    // Same modal main uses for every privileged action, and the same
    // singleton behind it — this window only supplies the command.
    PasswordPrompt { id: pwPrompt }
}
