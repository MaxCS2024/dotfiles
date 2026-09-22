// The wallpaper gallery — the whole screen, dimmed, with the folder as a
// carousel: one image large in the middle, its neighbours falling away to
// either side, and the wheel to move between them (user request
// 2026-09-18). It was a grid of even tiles for one commit before that,
// and a 760x520 box of 168x110 thumbnails before that.
//
// The shape is the point. A grid asks you to compare nine images at a
// size none of them deserve; this shows you one at nearly the size it
// will actually be, with just enough of the next two on each side to say
// which way to keep going. Picking a wallpaper is looking at one image
// and then at the one after it, which is a motion, not a survey.
//
// The one surface in this shell that is deliberately not a card. Every
// other window here is a rectangle of `surface` with a Hyprland frame
// around it, because every other window is showing you *this shell's*
// information. This one is showing you pictures, and a frame around a
// picture is a frame competing with it. So the desktop dims and the
// images sit straight on the dim, which also means the image you are
// looking at is next to a black field rather than next to a panel colour
// the palette took from some other image.
//
// That is also why the text here is white rather than Appearance's
// foregrounds: those are tuned to sit on `surface`, and there is no
// surface here — a 92% black scrim is the background, and it is the
// same 92% black whatever the palette is doing.
//
// What is behind it all lives in Wallpapers.qml next door: the listing,
// which image each output is showing, the apply, the shuffle, and the
// hourly rotation that runs whether or not this window was ever built.
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:wallpaper"
    surfaceName: "wallpaper"
    focusTarget: filterInput

    // 220, not ShellSurface's 200: this fades on the shell-wide panel
    // duration, and a refactor is not the place to quietly shorten it.
    exitDuration: Theme.animPanel

    // Every open is a fresh look: the folder can change between opens,
    // and so can what is on screen — a rotation may have fired an hour
    // ago.
    onSurfaceOpened: {
        panel.filter = ""
        filterInput.text = ""
        panel.userMoved = false
        Wallpapers.refresh()
        panel.syncSelection()
    }

    // The margin the gallery keeps off the screen edges. Generous on
    // purpose: the dim needs to read as a border around the images, not
    // as a background they are bleeding off.
    readonly property int gutter: 56

    // Type-to-filter, over the display name rather than the path: the
    // folder is one directory, so the path adds nothing to match on, and
    // the extension and resolution suffix would match everything.
    property string filter: ""

    readonly property var shownFiles: {
        const q = panel.filter.trim().toLowerCase()
        if (q === "") return Wallpapers.files
        return Wallpapers.files.filter(p => Wallpapers.displayName(p).toLowerCase().indexOf(q) !== -1)
    }

    // The carousel owns the position — it is the thing that scrolls, and
    // a second copy of "which one is selected" would have to be kept in
    // step with it on every flick. Everything else reads it from here.
    readonly property int selectedIndex: flow.currentIndex
    readonly property string selectedPath:
        panel.shownFiles.length > 0 && panel.selectedIndex >= 0
            ? panel.shownFiles[panel.selectedIndex] : ""

    // Whether the selection has been moved by hand since this open. Until
    // it has, it follows the current wallpaper as the listing and awww's
    // cache arrive (both are async, and either can land after the window
    // is already up); after it has, it stays where it was put.
    property bool userMoved: false

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    // No mask, unlike every other window in this config: the dim is part
    // of the surface and clicking it is how the gallery is dismissed, so
    // the whole screen has to take clicks while this is up.

    // Open on the wallpaper that is already up, so the carousel starts
    // where you are and moving off it is a comparison against it.
    function syncSelection() {
        if (panel.userMoved) return
        const files = panel.shownFiles
        for (var i = 0; i < files.length; i++) {
            if (Wallpapers.isCurrent(files[i])) {
                flow.currentIndex = i
                return
            }
        }
        flow.currentIndex = 0
    }

    // Wraps, because the view wraps whether it is asked to or not: a
    // PathView lays the whole model around its path, so at the last image
    // the next two are already drawn to the right of the hero. Clamping
    // the position there would have meant a gallery that shows you what
    // comes next and then refuses to go to it. The caption's "9 of 9" is
    // what says where the end is.
    function move(step) {
        const n = panel.shownFiles.length
        if (n === 0) return
        panel.userMoved = true
        // Two modulos: JS keeps the sign of the dividend, so -1 % 9 is -1.
        flow.currentIndex = ((flow.currentIndex + step) % n + n) % n
    }

    // Home and End, which a wrapping move() cannot express — a step of
    // the whole length lands back where it started.
    function jumpTo(index) {
        const n = panel.shownFiles.length
        if (n === 0) return
        panel.userMoved = true
        flow.currentIndex = Math.max(0, Math.min(n - 1, index))
    }

    function applySelected() {
        if (panel.selectedPath === "") return
        Wallpapers.apply(panel.selectedPath)
        // Closed rather than left up under an "Applying…" state: the
        // thing you just asked to look at is behind this window, and
        // wallpaper/WallpaperPopup.qml says whether it worked.
        panel.close()
    }

    Connections {
        target: Wallpapers
        function onFilesChanged() { panel.syncSelection() }
        function onCurrentPathsChanged() { panel.syncSelection() }
    }

    // Filtering re-indexes the list under the selection, so it goes back
    // to the first match rather than pointing at whichever image happens
    // to have inherited the old index.
    onFilterChanged: flow.currentIndex = 0

    // ── The dim ──────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.92)
        opacity: panel.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: panel.shown ? Theme.animPanel : Theme.animFast
                easing.type: Theme.easingStandard
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: panel.close()
        }
    }

    // ── The gallery ──────────────────────────────────────
    Item {
        id: content

        anchors.fill: parent
        anchors.margins: panel.gutter

        // Fades and settles rather than sliding in from an edge: it fills
        // the screen, so there is no edge for it to come from. The scale
        // is small enough to read as the gallery arriving rather than as
        // a zoom.
        opacity: panel.shown ? 1 : 0
        scale: panel.shown ? 1 : 0.985
        transformOrigin: Item.Center

        Behavior on opacity {
            NumberAnimation {
                duration: panel.shown ? Theme.animPanel : Theme.animFast
                easing.type: panel.shown ? Theme.easingDecel : Easing.InCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: panel.shown ? Theme.animPanel : Theme.animFast
                easing.type: panel.shown ? Theme.easingDecel : Easing.InCubic
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 14

            // ── Header ───────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                // U+F0248 is nf-md-image_multiple_outline, the glyph this
                // window already wore and the one bar/WallpaperButton
                // wears in the bar. A badge beside the title, at the size
                // the two rails give theirs.
                Text {
                    text: "\udb80\ude48"
                    color: "#ffffff"
                    font.pixelSize: Theme.fontHuge
                    font.family: Theme.font
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    spacing: 1

                    Text {
                        text: "Wallpapers"
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: Theme.fontLarge
                        font.family: Theme.font
                    }

                    Text {
                        text: Wallpapers.loading ? "Loading…"
                            : Wallpapers.files.length === 0 ? Wallpapers.dirDisplay
                            : panel.filter.trim() !== ""
                                ? panel.shownFiles.length + " of " + Wallpapers.files.length + " images"
                            : Wallpapers.files.length === 1 ? "1 image"
                            : Wallpapers.files.length + " images"
                        color: Qt.rgba(1, 1, 1, 0.66)
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                    }
                }

                Item { Layout.fillWidth: true }

                // ── Filter ───────────────────────────────
                Rectangle {
                    implicitWidth: 260
                    implicitHeight: 32
                    radius: Theme.radius
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1
                    border.color: filterInput.activeFocus ? Appearance.accent : Qt.rgba(1, 1, 1, 0.18)

                    Behavior on border.color {
                        ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Filter…"
                        visible: filterInput.text === ""
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                    }

                    TextInput {
                        id: filterInput

                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: "#ffffff"
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                        clip: true
                        cursorVisible: true

                        onTextChanged: panel.filter = text

                        // The gallery's whole keyboard surface, because
                        // this is the item that holds focus while it is
                        // open — same arrangement as the launcher's own
                        // search field. Left/Right rather than Up/Down:
                        // the carousel is one row, and the arrows should
                        // point the way it moves.
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                // One layer at a time: a filter that has
                                // narrowed the gallery is what Escape
                                // undoes first, and only an empty field
                                // closes the window.
                                if (filterInput.text !== "") filterInput.text = ""
                                else panel.close()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                                panel.move(1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                                panel.move(-1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Home) {
                                panel.jumpTo(0)
                                event.accepted = true
                            } else if (event.key === Qt.Key_End) {
                                panel.jumpTo(panel.shownFiles.length - 1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                panel.applySelected()
                                event.accepted = true
                            }
                        }
                    }
                }

                // ── Shuffle ──────────────────────────────
                // U+F074 is nf-fa-shuffle. Applies a random one that
                // isn't already up and closes, for the same reason
                // picking one does: the result is behind this window.
                GalleryButton {
                    glyph: "\uf074"
                    label: "Shuffle"
                    enabled: Wallpapers.files.length > 1
                    onTapped: {
                        Wallpapers.shuffle()
                        panel.close()
                    }
                }

                // U+F021 is nf-fa-arrows_rotate, the refresh glyph
                // quicksettings/PowerTab.qml already uses for Reboot.
                GalleryButton {
                    glyph: "\uf021"
                    label: "Rescan"
                    onTapped: Wallpapers.refresh()
                }

                // ── Hourly rotation ──────────────────────
                // Labelled, unlike the switches in the two rails: those
                // sit under a caption that names the state they put the
                // machine in, and this one has no caption to lean on.
                RowLayout {
                    spacing: 8
                    Layout.leftMargin: 6

                    Text {
                        text: "Rotate hourly"
                        color: Qt.rgba(1, 1, 1, 0.66)
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                    }

                    ToggleSwitch {
                        checked: Settings.rotateWallpaperHourly
                        trackOffColor: Qt.rgba(1, 1, 1, 0.18)
                        trackOnColor: Appearance.accent
                        borderColor: Qt.rgba(1, 1, 1, 0.25)
                        knobColor: "#ffffff"
                        onToggled: Settings.rotateWallpaperHourly = !Settings.rotateWallpaperHourly
                    }
                }
            }

            // ── The carousel ─────────────────────────────
            Item {
                id: stage

                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: panel.shownFiles.length > 0

                // The hero, and every other image with it — one delegate
                // size, scaled down by the path as it moves off centre,
                // so the neighbours are literally the same card further
                // away rather than a second, smaller design.
                //
                // 16:9 because every wallpaper in this folder is, and a
                // crop to the screen's own ratio is what awww will do
                // anyway. Whichever of width and height runs out first
                // decides, so the hero grows to fill a wide screen and
                // stops when it would outgrow the space between the
                // header and the caption.
                readonly property int heroWidth:
                    Math.round(Math.min(stage.width * 0.5, stage.height * 16 / 9))
                readonly property int heroHeight: Math.round(stage.heroWidth * 9 / 16)

                PathView {
                    id: flow

                    anchors.fill: parent
                    model: panel.shownFiles
                    // Five: the hero, one neighbour either side, and one
                    // more on each side mostly off the screen edge, which
                    // is what keeps a scroll from arriving at an empty
                    // gap before the next image fades in.
                    // Five, of which three are ever really on screen: the
                    // hero and one neighbour each side. The outer pair
                    // live past the screen edge and exist so that a scroll
                    // brings an image in that was already loaded and
                    // placed, rather than one that pops into being at the
                    // edge of the frame.
                    pathItemCount: 5
                    // Pin the current item to the middle of the path and
                    // let the view come to rest there on its own — this
                    // is what makes a flick snap to an image rather than
                    // stopping between two.
                    preferredHighlightBegin: 0.5
                    preferredHighlightEnd: 0.5
                    highlightRangeMode: PathView.StrictlyEnforceRange
                    // Long enough to read as travel between two pictures,
                    // short enough that holding an arrow down still moves.
                    highlightMoveDuration: 280

                    // A straight line across the screen, running a little
                    // past both edges so the outermost pair are cut off
                    // by the screen rather than ending in mid-air. The
                    // attributes interpolate between the three points, so
                    // an image shrinks and dims continuously as it goes
                    // out — there is no step where it changes character.
                    path: Path {
                        // The ends run well past the screen — 18% of the
                        // width on each side. The five items sit at even
                        // fractions of the path, so widening it is what
                        // moves the neighbours out from under the hero:
                        // at 8% they were centred on the hero's own edges
                        // and all but a sliver of each was hidden behind
                        // it.
                        startX: -flow.width * 0.18
                        startY: flow.height / 2

                        PathAttribute { name: "iScale"; value: 0.45 }
                        PathAttribute { name: "iOpacity"; value: 0.3 }
                        PathAttribute { name: "iZ"; value: 0 }

                        PathLine { x: flow.width / 2; y: flow.height / 2 }

                        PathAttribute { name: "iScale"; value: 1 }
                        PathAttribute { name: "iOpacity"; value: 1 }
                        PathAttribute { name: "iZ"; value: 10 }

                        PathLine { x: flow.width * 1.18; y: flow.height / 2 }

                        PathAttribute { name: "iScale"; value: 0.45 }
                        PathAttribute { name: "iOpacity"; value: 0.3 }
                        PathAttribute { name: "iZ"; value: 0 }
                    }

                    // Scrolling, in the two units the two devices speak.
                    //
                    // A mouse reports angleDelta and nothing else: one
                    // notch is 120 of it, and one notch is one image. A
                    // touchpad reports pixelDelta — the distance the
                    // fingers actually travelled — and the angleDelta it
                    // carries alongside is a coarse rounding of that same
                    // motion, zero for most frames of an ordinary swipe.
                    // Reading angleDelta alone is why the trackpad moved
                    // nothing at all here (user report 2026-09-18).
                    //
                    // 56 pixels of finger per image. That is about a
                    // third of a comfortable two-finger swipe, so the
                    // gesture that moves one image is a small deliberate
                    // one and a long drag crosses a folder without
                    // becoming a blur.
                    readonly property int padStep: 56
                    readonly property int notchStep: 120
                    property real padAcc: 0
                    property real notchAcc: 0

                    // A floor between steps, for the touchpad only. A
                    // fast flick is thousands of pixels and would cross
                    // the whole folder in less time than it takes to see
                    // one image; a wheel notch is a discrete thing the
                    // hand did on purpose, and every one of those should
                    // land. What the floor turns away is dropped rather
                    // than queued, so the carousel moves while the
                    // fingers move and stops when they stop.
                    readonly property int stepInterval: 110
                    property real lastStep: 0

                    function scrollBy(pixels, angle, phase) {
                        // Momentum is the touchpad coasting after the
                        // fingers have lifted. A list may keep gliding
                        // under it; a picker should stay where it was let
                        // go, or letting go becomes its own guess.
                        if (phase === Qt.ScrollMomentum) return
                        if (phase === Qt.ScrollBegin || phase === Qt.ScrollEnd) {
                            flow.padAcc = 0
                            flow.notchAcc = 0
                        }

                        // Whichever unit this event brought, never both:
                        // a touchpad sends pixels and a rounding of the
                        // same motion as angle, and counting the two
                        // would step twice for one swipe.
                        const fromPad = pixels !== 0
                        var acc
                        if (fromPad) {
                            flow.notchAcc = 0
                            flow.padAcc += pixels
                            acc = flow.padAcc
                        } else {
                            flow.notchAcc += angle
                            acc = flow.notchAcc
                        }

                        if (Math.abs(acc) < (fromPad ? flow.padStep : flow.notchStep)) return
                        flow.padAcc = 0
                        flow.notchAcc = 0

                        if (fromPad) {
                            const now = Date.now()
                            if (now - flow.lastStep < flow.stepInterval) return
                            flow.lastStep = now
                        }

                        // Positive is away from the user on a wheel and
                        // leftward on a trackpad, and both of those mean
                        // the image before this one — the same sense
                        // Flickable reads into contentX and contentY.
                        panel.move(acc > 0 ? -1 : 1)
                    }

                    // One handler per axis, each reading only its own.
                    //
                    // A WheelHandler is filtered to its orientation
                    // before its signal ever fires, which is why the
                    // sideways fallback this code used to keep inside the
                    // vertical handler could never once have run: a
                    // purely horizontal swipe is not delivered to it.
                    // Giving each handler one axis is also what stops a
                    // diagonal swipe — which both of them do hear — from
                    // being counted twice.
                    //
                    // Horizontal is worth having on a carousel that lies
                    // horizontally: pushing the pictures sideways is the
                    // gesture the shape asks for.
                    WheelHandler {
                        orientation: Qt.Vertical
                        onWheel: (event) => flow.scrollBy(event.pixelDelta.y, event.angleDelta.y, event.phase)
                    }

                    WheelHandler {
                        orientation: Qt.Horizontal
                        onWheel: (event) => flow.scrollBy(event.pixelDelta.x, event.angleDelta.x, event.phase)
                    }

                    delegate: Item {
                        id: card

                        required property string modelData
                        required property int index

                        readonly property bool centered: card.index === flow.currentIndex
                        readonly property bool current: Wallpapers.isCurrent(card.modelData)
                        readonly property bool applying: Wallpapers.applying === card.modelData

                        width: stage.heroWidth
                        height: stage.heroHeight

                        // The path's attributes, read defensively: they
                        // are undefined for the instant between a
                        // delegate being created and being placed.
                        scale: card.PathView.iScale === undefined ? 0.45 : card.PathView.iScale
                        opacity: card.PathView.iOpacity === undefined ? 0.3 : card.PathView.iOpacity
                        z: card.PathView.iZ === undefined ? 0 : card.PathView.iZ

                        Rectangle {
                            id: plate

                            anchors.fill: parent
                            radius: Theme.radius
                            color: Qt.rgba(1, 1, 1, 0.06)
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: "file://" + card.modelData
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                // Decoded at the size it is drawn at
                                // rather than at full resolution five
                                // times over.
                                sourceSize.width: Math.round(plate.width)
                                sourceSize.height: Math.round(plate.height)
                            }

                            // The ring is its own item drawn after the
                            // image: a Rectangle paints its border under
                            // its own children, so a border set on the
                            // plate itself would be covered by the
                            // full-bleed Image above. (That bug was fixed
                            // here once already, two layouts ago; the
                            // note survives both.)
                            Rectangle {
                                anchors.fill: parent
                                radius: plate.radius
                                color: "transparent"
                                border.color: card.centered ? Appearance.accent : Qt.rgba(1, 1, 1, 0.14)
                                // Scaled up with the card when it is off
                                // centre, so a 2px ring on a 38% card
                                // doesn't vanish.
                                border.width: card.centered ? 3 : 2

                                Behavior on border.color {
                                    ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                                }
                            }

                            // What is on screen right now. On the image
                            // rather than in the caption below: the
                            // caption only ever describes the hero, and
                            // this is worth knowing about the one you are
                            // scrolling toward as well.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: 12
                                visible: card.current
                                implicitWidth: currentLabel.implicitWidth + 18
                                implicitHeight: 24
                                // Square, where every other badge in this
                                // shell is a pill (user request
                                // 2026-09-18). The pills elsewhere sit on
                                // panel surfaces among other rounded
                                // chrome; this one sits on a photograph,
                                // and a capsule on a picture reads as a
                                // sticker laid over it. A rectangle in
                                // the corner of a rectangle reads as a
                                // mark on it.
                                radius: Theme.radius
                                color: Appearance.accent

                                Text {
                                    id: currentLabel
                                    anchors.centerIn: parent
                                    text: "Current"
                                    color: "#000000"
                                    font.pixelSize: Theme.fontSmall
                                    font.bold: true
                                    font.family: Theme.font
                                }
                            }

                            // Only ever seen when something else started
                            // the apply — the shuffle button and a click
                            // on the hero both close the gallery.
                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(0, 0, 0, 0.6)
                                visible: card.applying

                                Text {
                                    anchors.centerIn: parent
                                    text: "Applying…"
                                    color: "#ffffff"
                                    font.pixelSize: Theme.fontNormal
                                    font.family: Theme.font
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: Wallpapers.applying === ""
                                // One click means "bring this one here",
                                // a second means "use it". A side image
                                // is too small to be sure of, and
                                // applying one you cannot see properly is
                                // the mistake this layout exists to stop
                                // you making.
                                onClicked: {
                                    if (card.centered) panel.applySelected()
                                    else panel.move(card.index - flow.currentIndex)
                                }
                            }
                        }
                    }
                }
            }

            // ── Caption ──────────────────────────────────
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                spacing: 3
                visible: panel.shownFiles.length > 0

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: panel.selectedPath === "" ? "" : Wallpapers.displayName(panel.selectedPath)
                    color: "#ffffff"
                    font.pixelSize: Theme.fontLarge
                    font.family: Theme.font
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: (panel.selectedIndex + 1) + " of " + panel.shownFiles.length
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                }
            }

            // ── Nothing to show ──────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: panel.shownFiles.length === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    Text {
                        // U+F0248 again, the folder this window is about.
                        text: "\udb80\ude48"
                        color: Qt.rgba(1, 1, 1, 0.3)
                        font.pixelSize: Theme.fontHuge
                        font.family: Theme.font
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: Wallpapers.loading ? "Looking…"
                            : Wallpapers.files.length === 0
                                ? "No images in " + Wallpapers.dirDisplay
                            : "Nothing matches “" + panel.filter.trim() + "”"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pixelSize: Theme.fontNormal
                        font.family: Theme.font
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // ── Footer ───────────────────────────────────
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Scroll or ← → to move · Enter to apply · Esc to close"
                color: Qt.rgba(1, 1, 1, 0.38)
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
            }
        }
    }
}
