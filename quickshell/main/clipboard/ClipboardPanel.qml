// The clipboard — a search field over the whole window, the history down
// the left, and whatever is selected in full on the right.
//
// The shape is the one the user asked for (2026-09-21) and it is the
// reason this is a window rather than another rail: a preview pane needs
// room to be a preview, and a 400px card beside a list is neither. So it
// is keybinds/KeybindsPanel.qml's family instead — a centred box over a
// scrim, a filter field that keeps focus the whole time, a focus grab,
// and Escape that clears the filter before it closes the window.
//
// What it replaces: the eight-row hover dropdown on bar/ClipboardButton
// .qml, which could show a preview line and nothing else — a clipboard
// entry is usually longer than the row it is listed in, and the whole
// point of picking one is seeing what you are about to paste.
// quicksettings/ClipboardTab.qml stays where it is; that one is the
// surface you open to wipe the history, this is the one you open to find
// something in it.
//
// cliphist is the store (DEPENDENCIES.md): `cliphist list` gives
// `id<TAB>preview` a line at a time, `cliphist decode <id>` gives the
// entry back whole. Every id that reaches a shell goes as `$1` and never
// spliced into the command string — an entry's *content* is somebody
// else's text, and the delete path below feeds a list line straight back
// into cliphist.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:clipboard"
    surfaceName: "clipboard"
    focusTarget: filterInput

    // Theme.animPanel (220), not ShellSurface's 200: this surface fades on the
    // shell-wide panel duration, and a refactor is not the place to
    // quietly shorten it.
    exitDuration: Theme.animPanel

    anchors { top: true; bottom: true; left: true; right: true }



    // [{ id, preview }], newest first — cliphist's own order.
    property var entries: []
    property int selectedIndex: 0

    // The field is the filter state; mirroring it into a property here
    // would be two things to keep in step (keybinds' call, same reason).
    readonly property string query: filterInput.text

    readonly property var filtered: {
        const q = panel.query.trim().toLowerCase()
        if (q === "") return panel.entries
        return panel.entries.filter(e => e.preview.toLowerCase().includes(q))
    }

    readonly property var selected:
        panel.selectedIndex >= 0 && panel.selectedIndex < panel.filtered.length
            ? panel.filtered[panel.selectedIndex] : null

    // What the pane is showing, as an id. The decode below hangs off
    // *this* and not off selectedIndex, because the index is not what
    // changes when the selection does: typing into the filter rebuilds
    // the list under a selectedIndex that stays 0, and the pane went on
    // showing the entry that used to be first (found 2026-09-21 — the
    // search narrowed to three rows while the preview still read the
    // URL from before the query).
    //
    // A string rather than the object: `filtered` is rebuilt on every
    // keystroke, so `selected` emits a change each time even when it
    // resolves to the same entry, and each of those would be another
    // cliphist process. A string only signals when the value is
    // genuinely different.
    readonly property string selectedId: panel.selected ? panel.selected.id : ""

    // cliphist stands in a line of its own for anything that isn't text
    // — "[[ binary data 39 KiB png 1920x1080 ]]". Decoding one of those
    // into a Text element would paint a screenful of mojibake, so the
    // preview pane shows the descriptor instead and says why.
    readonly property bool selectedIsBinary:
        panel.selected !== null && /^\[\[\s*binary data/.test(panel.selected.preview)

    // The decoded entry, and whether `head -c` cut it short.
    property string body: ""
    property bool bodyTruncated: false
    property bool bodyLoading: false

    // 200k of text is already far more than anyone reads in a preview
    // pane, and it is the ceiling that keeps a pasted logfile from
    // arriving as a 40MB string in a QML property.
    readonly property int bodyLimit: 200000

    // ── cliphist ──────────────────────────────────────────
    function refresh() {
        listProc.running = false
        listProc.running = true
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]

        property var found: []
        onRunningChanged: if (running) found = []

        stdout: SplitParser {
            onRead: (line) => {
                const tab = line.indexOf("\t")
                if (tab === -1) return
                listProc.found.push({ id: line.slice(0, tab), preview: line.slice(tab + 1) })
            }
        }

        onExited: {
            panel.entries = listProc.found
            panel.selectedIndex = 0
            // Explicit, unlike everywhere else: reopening the window
            // usually lands on the same entry it closed on, and an id
            // that has not changed signals nothing to decode against.
            panel.loadBody()
        }
    }

    // Debounced: holding Down walks the list a row every few
    // milliseconds, and each row would otherwise be a process spawn that
    // the next keystroke immediately makes pointless.
    Timer {
        id: bodyDebounce
        interval: 90
        onTriggered: panel.loadBody()
    }

    onSelectedIdChanged: {
        panel.body = ""
        panel.bodyTruncated = false
        bodyDebounce.restart()
    }

    function loadBody() {
        bodyDebounce.stop()
        if (!panel.selected || panel.selectedIsBinary) {
            panel.body = ""
            panel.bodyLoading = false
            return
        }
        panel.bodyLoading = true
        // One byte past the limit is how the truncation is detected —
        // asking for exactly the limit can't tell "this is the whole
        // thing" from "this is where it was cut".
        decodeProc.command = ["sh", "-c",
            "cliphist decode \"$1\" | head -c " + (panel.bodyLimit + 1), "sh", panel.selected.id]
        decodeProc.running = false
        decodeProc.running = true
    }

    Process {
        id: decodeProc
        // onStreamFinished and not onExited: the two can land in either
        // order, so the text is read where the text is (see the shell's
        // notes on Process ordering).
        stdout: StdioCollector {
            onStreamFinished: {
                panel.bodyTruncated = text.length > panel.bodyLimit
                panel.body = panel.bodyTruncated ? text.slice(0, panel.bodyLimit) : text
                panel.bodyLoading = false
            }
        }
    }

    Process { id: copyProc }

    // `cliphist wipe` empties the store in one call — no per-id loop like
    // panel.deleteQueue below, which exists because deleting one entry
    // needs its whole `id\tpreview` line back out of `cliphist list`.
    Process { id: wipeProc }

    function wipeAll() {
        wipeProc.running = false
        wipeProc.command = ["cliphist", "wipe"]
        wipeProc.running = true
        panel.entries = []
        panel.selectedIndex = 0
    }

    function copySelected() {
        if (!panel.selected) return
        copyProc.command = ["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", panel.selected.id]
        copyProc.running = false
        copyProc.running = true
        panel.close()
    }

    // Deletes queue rather than restarting one Process. Ctrl+Delete is a
    // key you hold down a run of rows with, and `running = false` on a
    // Process that is still working kills it: the second press would have
    // cancelled the first delete mid-flight, leaving the row gone from
    // this list and still in cliphist — back again on the next open.
    // One at a time, in order, and the queue drains itself.
    property var deleteQueue: []

    Process {
        id: deleteProc
        onExited: panel._drainDeletes()
    }

    function _drainDeletes() {
        if (deleteProc.running || panel.deleteQueue.length === 0) return
        const id = panel.deleteQueue.shift()
        // cliphist delete takes a whole `list` line on stdin rather than
        // an id as an argument, so the line has to be found again — the
        // same round trip quicksettings/ClipboardTab.qml makes, with the
        // id passed in as $1 instead of spliced into the awk program.
        deleteProc.command = ["sh", "-c",
            "cliphist list | awk -F'\\t' -v id=\"$1\" '$1==id{print;exit}' | cliphist delete",
            "sh", id]
        deleteProc.running = true
    }

    function deleteSelected() {
        if (!panel.selected) return
        const id = panel.selected.id
        panel.deleteQueue.push(id)
        panel._drainDeletes()

        // Dropped locally rather than waiting for a re-list: the process
        // is a few milliseconds and the row should go when it is asked
        // to. The index stays where it is, so the next entry moves up
        // under the selection, which is what deleting down a list wants.
        panel.entries = panel.entries.filter(e => e.id !== id)
        const max = Math.max(0, panel.filtered.length - 1)
        if (panel.selectedIndex > max) panel.selectedIndex = max
    }

    // ── Selection ─────────────────────────────────────────
    function moveSelection(delta) {
        if (panel.filtered.length === 0) return
        panel.selectedIndex = Math.max(0,
            Math.min(panel.filtered.length - 1, panel.selectedIndex + delta))
        list.positionViewAtIndex(panel.selectedIndex, ListView.Contain)
    }

    // A new query selects its first match. This used to fire on `filtered`
    // and only when the index had fallen off the end, which is not the
    // same thing at all: three rows down a list, typing a letter left the
    // highlight on the fourth surviving match rather than the first, so
    // the pane showed an arbitrary entry and Enter would have copied it
    // (found 2026-09-21). Hanging it on the query means every keystroke
    // that narrows or widens the list lands you at the top of it, which
    // is what a search field is for.
    onQueryChanged: panel.selectedIndex = 0

    // Still needed on its own: entries arrive and disappear without the
    // query changing — a delete, or the list coming back from cliphist —
    // and an index past the end selects nothing at all.
    onFilteredChanged: {
        if (panel.selectedIndex >= panel.filtered.length)
            panel.selectedIndex = Math.max(0, panel.filtered.length - 1)
    }

    // ── Open / close ──────────────────────────────────────
    onSurfaceOpened: {
        filterInput.text = ""
        panel.selectedIndex = 0
        panel.body = ""
        // The history is a file another process writes, so it is asked
        // for on every open rather than watched.
        panel.refresh()
    }

    // Only the window takes clicks — a near-miss on the backdrop does
    // nothing rather than dismissing it, same as the Conf menu, the
    // keybinds window and the power menu. Focus leaving by any other
    // route still closes.
    mask: Region { item: box }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: panel.shown ? 0.5 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard }
        }
    }

    // ── The window ────────────────────────────────────────
    Rectangle {
        id: box

        anchors.horizontalCenter: parent.horizontalCenter
        // Wider than the keybinds window's 800: this one is two columns,
        // and the right-hand one is the whole reason to open it. Capped
        // against the surface so it still fits a small screen.
        width: Math.min(940, Math.round(parent.width * 0.76))
        // Fixed rather than fitted to content, unlike the keybinds
        // window: a preview pane that changed height with whatever entry
        // was selected would move the list under the pointer on every
        // keystroke.
        height: Math.min(580, Math.round(parent.height * 0.8))
        y: Math.round((parent.height - box.height) / 2.6)
        radius: Theme.radius
        color: Appearance.surface
        border.width: Theme.hyprBorderWidth
        border.color: Appearance.border

        opacity: panel.shown ? 1 : 0
        scale: panel.shown ? 1 : 0.97
        Behavior on opacity {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard }
        }
        Behavior on scale {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingDecel }
        }

        layer.enabled: true
        layer.effect: PopupShadow {}
        HyprFrame {
            frameWidth: box.border.width
            targetRadius: box.radius
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space4
            spacing: Theme.space3

            // ── Search, and the one control that empties the store ──
            // The field takes the width, which is what was asked for and
            // also what it is worth: it is the only thing on the surface
            // that takes typing, and both columns below answer to it.
            //
            // Wipe came across from quicksettings/ClipboardTab.qml when
            // that tab was deleted with the rest of the settings panel
            // (2026-09-21): `cliphist wipe` was reachable from nowhere
            // else in the shell, and the per-entry delete this window
            // already had is a different question — one entry you regret
            // against the whole history. It sits beside the field rather
            // than inside it, because a destructive control inside a
            // search box reads as "clear what I typed", which is the one
            // thing it does not do.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: Theme.radius
                    color: Appearance.surfaceAlt

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space3
                        anchors.rightMargin: Theme.space3
                        spacing: Theme.space2

                        // U+F0349 is nf-md-magnify, the glyph the keybinds
                        // window's filter wears.
                        Text {
                            text: "\u{F0349}"
                            color: Appearance.fgFaint
                            font.pixelSize: ConfStyle.fontHint
                            font.family: Theme.font
                        }

                        TextInput {
                            id: filterInput

                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            color: Appearance.fg
                            font.pixelSize: ConfStyle.fontRow
                            font.family: Theme.font
                            clip: true
                            selectByMouse: true
                            selectionColor: Appearance.selected
                            verticalAlignment: TextInput.AlignVCenter

                            // This field holds focus for as long as the
                            // window is open — it is the only thing on the
                            // surface that can — so every key that means
                            // something to the list has to be caught here.
                            // None of them mean anything to a single-line
                            // field, so nothing is taken from it.
                            Keys.onPressed: (event) => {
                                switch (event.key) {
                                case Qt.Key_Escape:
                                    // Clear a typed filter first, close
                                    // second: one key that always means
                                    // "back out of the last thing I did".
                                    if (filterInput.text !== "") filterInput.text = ""
                                    else panel.close()
                                    break
                                case Qt.Key_Down:     panel.moveSelection(1); break
                                case Qt.Key_Up:       panel.moveSelection(-1); break
                                case Qt.Key_PageDown: panel.moveSelection(8); break
                                case Qt.Key_PageUp:   panel.moveSelection(-8); break
                                case Qt.Key_Home:     panel.moveSelection(-panel.filtered.length); break
                                case Qt.Key_End:      panel.moveSelection(panel.filtered.length); break
                                case Qt.Key_Return:
                                case Qt.Key_Enter:
                                    panel.copySelected()
                                    break
                                case Qt.Key_Delete:
                                    // Ctrl to delete, because Delete alone
                                    // belongs to the field the cursor is in.
                                    if (event.modifiers & Qt.ControlModifier) panel.deleteSelected()
                                    else return
                                    break
                                default:
                                    return
                                }
                                event.accepted = true
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: filterInput.text.length === 0
                                text: "Search the clipboard…"
                                color: Appearance.placeholder
                                font.pixelSize: ConfStyle.fontRow
                                font.family: Theme.font
                            }
                        }
                    }
                }

                // Danger tones only under the pointer, like the
                // notification rail's own clear control and for the same
                // reason — a permanently red edge would be the loudest
                // thing on a surface whose job is the list below it.
                // Hidden on an empty history rather than dimmed: the
                // empty state in the column underneath already says it.
                Rectangle {
                    visible: panel.entries.length > 0
                    implicitWidth: wipeLabel.implicitWidth + 20
                    implicitHeight: 40
                    radius: Theme.radius
                    color: wipeHover.hovered ? Appearance.dangerBg : Appearance.surfaceAlt
                    border.width: 1
                    border.color: wipeHover.hovered ? Appearance.dangerBorder : Appearance.clear(Appearance.dangerBorder)

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                    }

                    Text {
                        id: wipeLabel
                        anchors.centerIn: parent
                        text: "Wipe"
                        color: wipeHover.hovered ? Appearance.red : Appearance.fgSoft
                        font.pixelSize: ConfStyle.fontRow
                        font.family: Theme.font

                        Behavior on color {
                            ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                        }
                    }

                    HoverHandler { id: wipeHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.wipeAll()
                    }
                }
            }

            // ── History, and the entry in full ────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.space3

                // Left: the rows. Half the window — the list and the pane
                // each get the same width (user request 2026-09-21), which
                // is what two children asking for the same preferred width
                // and both filling comes to. It was a fixed 300 against a
                // filling pane before.
                //
                // Both sides say `Layout.fillWidth` and `preferredWidth: 1`
                // rather than one of them naming a number: a RowLayout hands
                // the slack to its filling children evenly, so equal
                // preferences make equal columns at any window width,
                // without either side knowing what the other took.
                // The ListView sits in a plain Item rather than being the
                // layout child itself, so the empty state can be centred
                // over it. A Flickable — which a ListView is — parents its
                // children to its *content item*, and `anchors.centerIn:
                // parent` inside one centres on content that is zero high
                // when there is nothing to show: the message pinned itself
                // to the top corner instead of the middle (found
                // 2026-09-21, in the preview pane, where it had also ended
                // up in the wrong column — the rows that are missing are
                // these ones).
                //
                // An Item is not a layout, so fillWidth does *not* default
                // to true here and is stated.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    Layout.fillHeight: true

                    Text {
                        anchors.centerIn: parent
                        visible: panel.filtered.length === 0
                        text: panel.entries.length === 0 ? "The clipboard history is empty"
                            : "No entry matches that"
                        color: Appearance.fgDim
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                    }

                ListView {
                    id: list

                    anchors.fill: parent
                    clip: true
                    spacing: 2
                    model: panel.filtered
                    boundsBehavior: Flickable.StopAtBounds
                    currentIndex: panel.selectedIndex

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index

                        readonly property bool current: row.index === panel.selectedIndex

                        width: ListView.view.width
                        height: 32
                        radius: Theme.radius
                        color: row.current ? SlabStyle.tintSelected
                             : rowHover.hovered ? Appearance.hover
                             : Appearance.clear(Appearance.hover)

                        // The selected row is its ground (the half-accent
                        // SlabStyle.tintSelected every selected thing in the
                        // shell uses) and the brighter ink, and nothing else — the accent bar
                        // that used to run down its leading edge is gone
                        // (user request 2026-09-21).

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space3
                            anchors.rightMargin: Theme.space2
                            verticalAlignment: Text.AlignVCenter
                            text: row.modelData.preview
                            color: row.current ? Appearance.fgStrong : Appearance.fg
                            font.pixelSize: Theme.fontNormal
                            font.family: Theme.font
                            elide: Text.ElideRight
                        }

                        HoverHandler { id: rowHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            // One click selects and shows; the copy
                            // is the button on the pane or Enter.
                            // Clicking a row to select it and having
                            // it copy and vanish in the same motion
                            // is the dropdown's behaviour, and the
                            // reason this window exists is to look
                            // before copying.
                            onClicked: panel.selectedIndex = row.index
                            onDoubleClicked: panel.copySelected()
                        }
                    }
                }
                }

                // Right: the whole entry.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    Layout.fillHeight: true
                    radius: Theme.radius
                    color: Appearance.surfaceAlt

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.space3
                        spacing: Theme.space2

                        // What this entry is, before what it says.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            Text {
                                text: {
                                    if (!panel.selected) return "Nothing selected"
                                    if (panel.selectedIsBinary) return "Binary entry"
                                    const chars = panel.body.length
                                    // The trailing newline a terminal copy
                                    // carries is not a line of its own:
                                    // counting it had every such entry
                                    // reading "2 lines" over one line of
                                    // text (found 2026-09-21). The
                                    // character count keeps it, because
                                    // that byte is genuinely what gets
                                    // pasted.
                                    const lines = panel.body === "" ? 0
                                        : panel.body.replace(/\n$/, "").split("\n").length
                                    return chars + (chars === 1 ? " character" : " characters")
                                        + " · " + lines + (lines === 1 ? " line" : " lines")
                                }
                                color: Appearance.fgMuted
                                font.pixelSize: Theme.fontSmall
                                font.family: Theme.font
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: panel.bodyTruncated
                                text: "shown to " + Math.round(panel.bodyLimit / 1000) + "k"
                                color: Appearance.orange
                                font.pixelSize: Theme.fontTiny
                                font.family: Theme.font
                            }
                        }

                        // The text itself. A read-only TextEdit rather
                        // than a Text so a part of an entry can be
                        // selected and taken without taking the whole
                        // thing — which is half of what a preview pane
                        // is for.
                        Flickable {
                            id: bodyView

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: width
                            contentHeight: bodyText.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds

                            // A read-only TextEdit rather than a Text
                            // so a part of an entry can be selected
                            // and taken without taking the whole thing
                            // — which is half of what a preview pane
                            // is for.
                            TextEdit {
                                id: bodyText

                                width: bodyView.width
                                readOnly: true
                                selectByMouse: true
                                selectionColor: Appearance.selected
                                wrapMode: TextEdit.Wrap
                                text: panel.selectedIsBinary ? panel.selected.preview
                                    : panel.bodyLoading && panel.body === "" ? ""
                                    : panel.body
                                color: panel.selectedIsBinary ? Appearance.fgMuted : Appearance.fg
                                font.pixelSize: Theme.fontNormal
                                // Mono, and the shell's mono is its
                                // only font — but named rather than
                                // inherited, because indentation and
                                // alignment are most of what a pasted
                                // block carries.
                                font.family: Theme.fontMono
                            }

                        }

                        // The hint line and the Copy/Delete buttons that
                        // used to close this column are gone (user request
                        // 2026-09-21). What they did is still here and
                        // still the faster way to do it: Enter copies the
                        // selection and closes, Ctrl+Delete removes it, and
                        // a double click on a row copies it. The pane is
                        // the entry now, and nothing else.
                    }
                }
            }
        }
    }
}
