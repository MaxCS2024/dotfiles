import Quickshell
import QtQuick
import QtQuick.Layouts
import "common"
import "common/localBin.js" as LocalBin
import "services"
import "style"

// The app launcher, in a config of its own so it works with or without
// the bar (moved out of main/launcher/ on 2026-10-09). shell.qml holds its
// IPC target and the SUPER+P shortcut. ShellSurface is ../shared's
// stand-in for the bar's.
//
// Every colour, size, font and duration here comes from `Style`, the skin
// that style/qmldir names (Main.qml, the bar's theme; Island.qml, the
// dynamic island's black and white). This file is the behaviour and the
// layout; a new look is a new skin, not an edit here.
ShellSurface {
    id: launcher

    surfaceNamespace: "quickshell:launcher"
    focusTarget: searchInput

    anchors { top: true; bottom: true; left: true; right: true }

    // The skin's panel duration, not ShellSurface's 200, so the window
    // isn't hidden before the fade is done.
    exitDuration: Style.animPanel

    // Every open is a fresh search. The hide timer used to clear the
    // field as well, a moment after the window went; it does not need to,
    // because this runs before the next one is ever seen — and leaving
    // the text up through the fade shows what was just dismissed.
    onSurfaceOpened: {
        searchInput.text = ""
        launcher.query = ""
        launcher.selectedIndex = 0
        launcher.runFilter()
    }

    property int maxResults: 50
    property string query: ""
    property int selectedIndex: 0

    readonly property var appEntries: [...DesktopEntries.applications.values]
        .filter(e => e.name && !e.noDisplay)
        .map(e => ({
            name: e.name,
            comment: e.comment || "",
            generic: e.genericName || "",
            keywords: (e.keywords || []).join(" "),
            icon: e.icon || "",
            entryRef: e
        }))

    property var results: []

    function launchSelected() {
        const item = launcher.results[launcher.selectedIndex]
        if (item && item.entryRef) {
            launcher.launch(item.entryRef)
            launcher.close()
        }
    }

    // Quickshell's execute() ignores Terminal=true: btop, nvim or yazi
    // started that way gets no terminal and exits on the spot, with
    // nothing on screen. Those open in the terminal System › Defaults
    // picked, through `relay default exec terminal` the way the bar's
    // Terminal.run does it, tiled and with no "press Enter": an app you
    // opened, not a task to watch. The command has its field codes (%F)
    // stripped already, which is what an app launched with no files wants.
    function launch(entry) {
        if (!entry.runInTerminal) {
            entry.execute()
            return
        }
        const cd = entry.workingDirectory
            ? "cd " + launcher.quote([entry.workingDirectory]) + " && " : ""
        Quickshell.execDetached(LocalBin.argv("relay",
            ["default", "exec", "terminal", "--", cd + launcher.quote(entry.command)]))
    }

    // An argv as one sh command line, each word single-quoted
    // (main/services/Terminal.qml's quote()).
    function quote(argv) {
        return argv.map(a => "'" + String(a).split("'").join("'\\''") + "'").join(" ")
    }

    function score(haystack, needle) {
        const h = haystack.toLowerCase()
        const n = needle.toLowerCase()
        if (n === "") return 0
        if (h === n) return 1000
        if (h.startsWith(n)) return 800 - h.length

        const idx = h.indexOf(n)
        if (idx !== -1) {
            const boundary = idx === 0 || h[idx - 1] === " " || h[idx - 1] === "-"
            return (boundary ? 600 : 400) - idx - h.length * 0.1
        }

        let hi = 0, matched = 0, gaps = 0, lastHit = -1
        for (let ni = 0; ni < n.length; ni++) {
            const found = h.indexOf(n[ni], hi)
            if (found === -1) return -1
            if (lastHit !== -1 && found > lastHit + 1) gaps += found - lastHit - 1
            lastHit = found
            hi = found + 1
            matched++
        }
        if (matched < n.length) return -1
        return 200 - gaps * 2 - h.length * 0.1
    }

    function entryScore(e, q) {
        const nameScore = launcher.score(e.name, q)
        if (nameScore >= 0) return nameScore

        const genericScore = launcher.score(e.generic, q)
        if (genericScore >= 0) return genericScore - 250

        const keywordScore = launcher.score(e.keywords, q)
        if (keywordScore >= 0) return keywordScore - 350

        const commentScore = launcher.score(e.comment, q)
        if (commentScore >= 0) return commentScore - 450

        return -1
    }

    function runFilter() {
        const q = launcher.query.trim()

        if (q === "") {
            launcher.results = [...launcher.appEntries]
                .sort((a, b) => a.name.localeCompare(b.name))
                .slice(0, launcher.maxResults)
            launcher.selectedIndex = 0
            return
        }

        const scored = []
        for (const e of launcher.appEntries) {
            const s = launcher.entryScore(e, q)
            if (s >= 0) scored.push({ entry: e, s: s })
        }

        scored.sort((a, b) => {
            if (b.s !== a.s) return b.s - a.s
            return a.entry.name.localeCompare(b.entry.name)
        })

        launcher.results = scored.slice(0, launcher.maxResults).map(x => x.entry)
        launcher.selectedIndex = 0
    }

    function ensureVisible() {
        resultsList.positionViewAtIndex(launcher.selectedIndex, ListView.Contain)
    }

    // The window still spans the whole screen (the
    // simplest way to keep `box`'s anchors.horizontalCenter math), but
    // `mask` restricts pointer input to `box`'s own rect, so clicks
    // outside it fall straight through to whatever is underneath instead
    // of being caught and swallowed by an invisible full-screen
    // MouseArea. HyprlandFocusGrab is what notices "the user clicked
    // something outside this window" now that this surface no longer
    // intercepts that click itself — the compositor-level replacement
    // for the old catcher's onClicked. (This note lived in
    // quicksettings/SettingsPanel.qml, which every other window pointed
    // at, until that panel was deleted on 2026-09-21.)
    mask: Region { item: box }

    Rectangle {
        id: box
        width: Style.width

        property int restY: Style.top
        // Just the search row plus its margins — the size the box sits
        // at before any results are revealed. Derived from searchRow's
        // own position/size (not layout spacing) so it's an exact pixel
        // boundary: separator and results are positioned starting AT
        // this value, guaranteeing zero px of them show while collapsed
        // regardless of font metrics.
        property int collapsedHeight: searchRow.y + searchRow.height + Style.padding

        readonly property int rowHeight: Style.rowHeight
        readonly property int maxVisibleRows: 8
        readonly property int emptyStateHeight: Style.emptyHeight
        // Sized to how many rows are actually showing, capped so a broad
        // query can't grow the box past a reasonable size — beyond that
        // it scrolls instead. A query with zero matches still gets a
        // little room for the "No matching apps" state rather than
        // collapsing to nothing.
        readonly property int resultsHeight: launcher.results.length > 0
            ? Math.min(launcher.results.length, maxVisibleRows) * rowHeight
            : emptyStateHeight
        // resultsArea.y (searchRow + separator + both gaps) plus the
        // content height plus a matching bottom margin.
        readonly property int expandedHeight: collapsedHeight + 9 + resultsHeight + Style.padding

        anchors.horizontalCenter: parent.horizontalCenter
        y: restY
        // Collapsed to just the search row until there's an actual query —
        // opening the launcher with nothing typed shows only the search
        // bar, not a dropdown full of every installed app. Once typing
        // starts, this grows to fit however many results actually matched.
        height: (launcher.shown && launcher.query.length > 0) ? expandedHeight : collapsedHeight
        // One rectangle, one border, one set of rounded corners — grows
        // straight down from the collapsed (search-only) height to the
        // full height, clipping the results underneath until there's
        // room for them. That's what reads as "results drop down from
        // behind the search bar": there's no second panel to seam
        // against, just this shape unrolling downward.
        Behavior on height { NumberAnimation { duration: Style.animPanel; easing.type: Style.easingPanel } }
        clip: true

        opacity: launcher.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Style.animFast; easing.type: Style.easingFast } }

        // Capped at half the search row's height, so a skin can ask for
        // a large radius and get a pill that keeps its round ends as the
        // box grows.
        radius: Math.min(Style.radius, box.collapsedHeight / 2)
        color: Style.background
        border.color: Style.borderColor
        border.width: Style.borderWidth

        layer.enabled: Style.shadow
        layer.effect: PopupShadow {}
        // The window border from the compositor, drawn around a layer
        // surface — see common/HyprFrame.qml. Declared first so
        // everything below paints over it. The radius stays the
        // launcher's own rather than Hyprland's square 0, so the ring
        // follows this box's corner as it unrolls.
        Loader {
            anchors.fill: parent
            active: Style.frame
            sourceComponent: HyprFrame {
                frameWidth: box.border.width
                targetRadius: box.radius
            }
        }

        // Everything below is positioned explicitly (not via layout
        // spacing) against box.collapsedHeight, so the reveal boundary
        // is an exact pixel line rather than something derived from
        // spacing math that could drift with font metrics.
        Item {
            id: searchRow
            x: Style.padding
            y: Style.padding
            width: box.width - Style.padding * 2
            height: searchInput.implicitHeight

            TextInput {
                id: searchInput
                anchors.fill: parent
                color: Style.searchText
                font.pixelSize: Style.searchSize
                font.family: Style.font
                font.weight: Style.fontWeight
                clip: true
                cursorVisible: true
                // Flip cursorVisible above to false and uncomment this to
                // hide the caret again. TextInput's docs: cursorVisible is
                // "set and unset ... automatically" on focus changes — Qt
                // force-sets it true internally the moment this gets active
                // focus, which silently breaks a plain `cursorVisible: false`
                // binding, so it has to be re-asserted on every focus change.
                // onActiveFocusChanged: cursorVisible = false

                onTextChanged: {
                    launcher.query = text
                    launcher.runFilter()
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        launcher.close()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Down
                            || (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier))) {
                        launcher.selectedIndex =
                            Math.min(launcher.selectedIndex + 1, launcher.results.length - 1)
                        launcher.ensureVisible()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up
                            || (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))) {
                        launcher.selectedIndex = Math.max(launcher.selectedIndex - 1, 0)
                        launcher.ensureVisible()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Home) {
                        launcher.selectedIndex = 0
                        launcher.ensureVisible()
                        event.accepted = true
                    } else if (event.key === Qt.Key_End) {
                        launcher.selectedIndex = Math.max(0, launcher.results.length - 1)
                        launcher.ensureVisible()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        launcher.launchSelected()
                        event.accepted = true
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Search apps…"
                color: Style.placeholder
                font.pixelSize: Style.searchSize
                font.family: Style.font
                font.weight: Style.fontWeight
                visible: searchInput.text.length === 0
            }
        }

        Rectangle {
            id: separator
            x: Style.padding
            y: box.collapsedHeight
            width: box.width - Style.padding * 2
            height: 1
            color: Style.separator
            // box.clip should already keep this out of view while collapsed,
            // but the shadow layer on box (layer.enabled + MultiEffect) can
            // end up compositing a bit outside the clipped region, so this
            // is a second, unconditional guard: no query, nothing painted.
            visible: launcher.query.length > 0
        }

        Item {
            id: resultsArea
            x: Style.padding
            y: separator.y + separator.height + 8
            width: box.width - Style.padding * 2
            // Matches box.resultsHeight exactly — box grows to fit this
            // area, not the other way around, so there's never dead space
            // (or a scrollbar-only sliver) below the last visible row.
            height: box.resultsHeight
            visible: launcher.query.length > 0

            Text {
                anchors.centerIn: parent
                text: "No matching apps"
                color: Style.emptyText
                font.pixelSize: Style.emptySize
                font.family: Style.font
                font.weight: Style.fontWeight
                visible: launcher.results.length === 0
            }

            RowLayout {
                anchors.fill: parent
                spacing: Style.gap
                visible: launcher.results.length > 0

                ListView {
                    id: resultsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: launcher.results

                    WheelHandler {
                        onWheel: (event) => {
                            const step = box.rowHeight * 3
                            resultsList.contentY = Math.max(
                                0,
                                Math.min(
                                    Math.max(0, resultsList.contentHeight - resultsList.height),
                                    resultsList.contentY - (event.angleDelta.y / 120) * step
                                )
                            )
                        }
                    }

                    delegate: Rectangle {
                        id: resultRow
                        required property var modelData
                        required property int index

                        readonly property bool selected: resultRow.index === launcher.selectedIndex

                        width: resultsList.width
                        height: box.rowHeight
                        radius: Style.rowRadius
                        color: resultRow.selected ? Style.rowSelected : Style.rowRest

                        Behavior on color { ColorAnimation { duration: Style.animFast; easing.type: Style.easingFast } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Style.rowPadX
                            anchors.rightMargin: Style.rowPadX
                            spacing: Style.gap

                            Item {
                                Layout.preferredWidth: Style.iconSize
                                Layout.preferredHeight: Style.iconSize

                                Image {
                                    id: appIcon
                                    anchors.fill: parent
                                    // AppIcons, not Quickshell.iconPath: an
                                    // app installed since the shell started
                                    // had a letter tile (see that file).
                                    source: AppIcons.path(resultRow.modelData.icon)
                                    // Matches the container above so the
                                    // SVG rasterises at the size it is drawn
                                    // rather than being rescaled into it — see
                                    // bar/SystemTray.qml for the measurement.
                                    sourceSize.width: Style.iconSize
                                    sourceSize.height: Style.iconSize
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    visible: status === Image.Ready
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Style.tileRadius
                                    color: resultRow.selected ? Style.tileSelected : Style.tile
                                    visible: appIcon.status !== Image.Ready

                                    Text {
                                        anchors.centerIn: parent
                                        text: resultRow.modelData.name.length > 0
                                            ? resultRow.modelData.name.charAt(0).toUpperCase() : "?"
                                        color: resultRow.selected ? Style.rowTextSelected : Style.rowText
                                        // Scales with the tile it centres in,
                                        // which is the icon for an app that
                                        // hasn't got one.
                                        font.pixelSize: Style.rowTextSize
                                        font.family: Style.font
                                        font.weight: Style.fontWeight
                                    }
                                }
                            }

                            Text {
                                text: resultRow.modelData.name
                                color: resultRow.selected ? Style.rowTextSelected : Style.rowText
                                font.pixelSize: Style.rowTextSize
                                font.family: Style.font
                                font.weight: Style.fontWeight
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                            }

                            Text {
                                text: resultRow.modelData.comment
                                color: resultRow.selected ? Style.rowDetailSelected : Style.rowDetail
                                font.pixelSize: Style.rowDetailSize
                                font.family: Style.font
                                font.weight: Style.fontWeight
                                elide: Text.ElideRight
                                Layout.maximumWidth: Style.rowDetailWidth
                            }
                        }

                        HoverHandler {
                            onHoveredChanged: {
                                if (hovered) launcher.selectedIndex = resultRow.index
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                launcher.selectedIndex = resultRow.index
                                launcher.launchSelected()
                            }
                        }
                    }
                }

                // The thumb arithmetic is shared with the Conf menu
                // (common/ListScrollBar.qml); the rail's look is the skin's.
                ListScrollBar {
                    Layout.fillHeight: true
                    view: resultsList
                    barWidth: Style.scrollWidth
                    barRadius: Style.scrollRadius
                    trackColor: Style.scrollTrack
                    thumbColor: Style.scrollThumb
                }
            }
        }
    }

}
