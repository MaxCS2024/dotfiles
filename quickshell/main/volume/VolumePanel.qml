// The volume rail — the right-edge slide-out over sound.
//
// Geometry, motion and material are notifications/NotificationHistoryPanel
// .qml's, which took them from network/NetworkPanel.qml, because all of
// them are the same kind of surface: a card held 8px off the screen edges it
// touches, which is the overhang notifications/NotificationPopups.qml has
// always had against Hyprland's `gaps_out` of 15 (hypr/modules/
// decorations.lua) — a toast, and now a third rail, overhangs the tiled
// window column by 7px and reads as part of the desktop's furniture
// rather than of the tiling grid.
//
// It differs from its two siblings in one way, at the user's asking: the
// card is exactly as tall as what is in it. The network rail is three
// fifths of the column and the notification rail is all of it, because
// both of those hold a list that is worth every row the screen will give
// it. This holds a fixed set of controls plus however many apps happen to
// be playing — usually none or two — and a card that stops where its
// content stops is the honest height for that. `cardHeight` below is the
// body's own implicit height, capped at the column so a machine with a
// dozen streams still fits on screen; the two lists inside are capped in
// rows for the same reason, and scroll past their cap.
//
// Content is quicksettings/VolumeTab.qml and quicksettings/MixerTab.qml —
// the two leaves of the settings panel's "sound" group — on one card:
// the output and microphone sliders, the output device picker, and the
// per-app mixer. Those tabs are still there and still reachable from the
// footer; this is the surface you open to reach for a slider, that one is
// the surface you open to configure. Same split the other two rails keep.
//
// Colours come from theme/Appearance.qml rather than config/Theme.qml,
// like every surface written since the bento dashboard — it falls through
// to the same Theme tokens by default but also honours a pinned custom
// palette. Geometry, motion and the Hyprland frame still come from
// Theme/common so the card material is the toasts'.
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:volume"
    surfaceName: "volume"
    focusTarget: card

    // 400, the notification rail's width rather than the network rail's
    // 450: nothing here is an SSID eliding in the middle. An app name
    // over a slider is the widest thing on the card.
    readonly property int cardWidth: 400

    // Room on the left of the card for its own shadow, which a
    // layer-shell surface clips like anything else — the same pad, for
    // the same reason, as the toast stack's. Nothing is needed on the
    // right: that edge is the screen's, and the card is held `inset` off
    // it, which is already more than the blur reaches.
    readonly property int shadowPad: 24

    // The card's own padding, named because `cardHeight` has to add it
    // back to a body that is measured without it.
    readonly property int cardPadding: 14

    // What the whole card is worth: its content, plus the padding either
    // side of it, and never more than the column the bar leaves.
    //
    // No binding loop, despite the card sizing to the layout it contains
    // and the layout filling the card: a ColumnLayout's implicitHeight is
    // computed from its children's implicit heights, not from its own
    // height, and nothing in `body` declares Layout.fillHeight — the two
    // lists ask for a row-counted preferredHeight instead. The only thing
    // that flows the other way is the cap, and that is a constant.
    readonly property int cardHeight: Math.min(
        panel.height - panel.inset * 2,
        body.implicitHeight + panel.cardPadding * 2)

    // Far enough that the card *and* its shadow are past the screen edge.
    readonly property int slideDistance: panel.cardWidth + panel.inset + 24

    // Sinks are the output devices themselves — the picker below — as
    // distinct from the streams a client plays *into* one, which is the
    // mixer. `!n.isStream` is what separates them; both are `isSink` on
    // this side of the graph. Lifted verbatim from quicksettings/
    // VolumeTab.qml, whose list this is.
    readonly property var audioSinks: Pipewire.nodes.values.filter(
        n => n.isSink && n.audio && !n.isStream)

    // AudioOutStream marks a client's playback stream into a sink (a
    // browser tab, a game, a music player) — distinct from AudioInStream,
    // which is a capture stream. quicksettings/MixerTab.qml's filter.
    //
    // Sorted by node id, which is the graph's own creation order and is
    // never reused: `Pipewire.nodes.values` comes back in whatever order
    // the registry holds it, and a row that changes places while you are
    // reaching for its mute is its own kind of unidentifiable. The rows
    // are grouped below and the groups inherit this order, so the app
    // that started playing first stays at the top of the list.
    readonly property var streams: Pipewire.nodes.values.filter(
        n => n.isStream && n.audio && (n.type & PwNodeType.AudioOutStream))
        .sort((a, b) => a.id - b.id)

    // Both lists have to be tracked or their `audio` interfaces stay
    // unbound — a slider would read 0 and setting it would go nowhere.
    // services/Volume.qml already tracks the default sink; this is every
    // other node on the card.
    PwObjectTracker { objects: panel.audioSinks }
    PwObjectTracker { objects: panel.streams }

    function isBt(node) { return (node.name || "").startsWith("bluez_") }

    function labelFor(node) {
        return node.description || node.nickname || node.name || "Unknown"
    }

    function propOf(node, key) {
        return (node.properties && node.properties[key]) || ""
    }

    function nameFor(node) {
        return panel.propOf(node, "application.name") || node.description
            || node.nickname || node.name || "Unknown"
    }

    // Browsers/players often set media.name to the track or tab title —
    // worth a second line, but only when it says something the app name
    // doesn't already (some clients just repeat the app name here).
    function subtitleFor(node) {
        const media = panel.propOf(node, "media.name")
        const appName = panel.nameFor(node)
        return (media && media !== appName) ? media : ""
    }

    function iconNameFor(node) {
        return panel.propOf(node, "application.icon-name")
            || panel.propOf(node, "application.name")
    }

    // One row per app, not per stream — what the mixer lists is the thing
    // making noise, not each connection it opens to make it.
    //
    // A browser opens a stream per tab that has made a sound and names
    // every one of them after itself, so two tabs playing drew two rows
    // both reading "Brave" with nothing to tell them apart. Nothing could
    // have: Chromium routes every tab through a single audio service
    // process and puts no tab title on the stream, and it publishes one
    // MPRIS player for the whole browser that follows whichever session
    // played last — neither end of that can name a tab while two of them
    // are playing. So the ambiguity is collapsed rather than labelled:
    // the streams that would have drawn the same row draw one row, and it
    // moves all of them together. Per-tab level is the page's own player,
    // which is where you would reach for it anyway.
    //
    // Keyed on the name the row would have shown, so what merges is
    // exactly what looked identical. An app playing one stream is a group
    // of one and its row is what it always was. A Map rather than an
    // object literal because the key is a client-supplied string, and
    // `Object.prototype` has names in it that a client is free to pick.
    readonly property var streamGroups: {
        const groups = []
        const byName = new Map()
        for (const node of panel.streams) {
            const name = panel.nameFor(node)
            const at = byName.get(name)
            if (at === undefined) {
                byName.set(name, groups.length)
                groups.push({ name: name, nodes: [node] })
            } else {
                groups[at].nodes.push(node)
            }
        }
        return groups
    }

    // A group of one keeps the stream's own second line. A group of
    // several cannot: media.name is per stream, and electing one of them
    // to speak for the row is how you get a caption that is wrong half
    // the time. How many streams the row is moving is the one thing that
    // is true of all of them — and it is also the answer to why the
    // browser only has one slider.
    function groupSubtitle(group) {
        if (group.nodes.length === 1) return panel.subtitleFor(group.nodes[0])
        return group.nodes.length + " streams"
    }

    // The oldest member's. Every stream an app opens carries the same
    // application.icon-name, which is the whole reason they group.
    function groupIconName(group) {
        return panel.iconNameFor(group.nodes[0])
    }

    // Absolute, not proportional: the slider *is* the app's level now, so
    // every stream under it lands on the value the slider shows. Scaling
    // the members against each other instead would preserve a balance the
    // row has no way to display, and a stream sitting at zero could never
    // be raised again by a slider that only multiplies.
    function setGroupVolume(group, v) {
        for (const node of group.nodes) {
            node.audio.volume = v
            if (v > 0 && node.audio.muted) node.audio.muted = false
        }
    }

    function setGroupMuted(group, m) {
        for (const node of group.nodes) node.audio.muted = m
    }

    // A strip, not the screen. Anchored top and bottom so the *available*
    // height is whatever the bar leaves (exclusiveZone 0 reserves nothing
    // and respects what the bar reserves) — which is only the cap on
    // `cardHeight`, not the card. The width is ours to state.
    anchors { top: true; bottom: true; right: true }
    implicitWidth: panel.shadowPad + panel.cardWidth + panel.inset
    exclusiveZone: 0
    // Only the card takes clicks, so the shadow gutter beside it and the
    // column below it stay click-through — the same idiom the toast stack
    // and the OSDs use. It matters more here than on the other two rails:
    // a content-sized card leaves most of this strip empty, and every
    // pixel of that empty part belongs to whatever is behind it.
    mask: cardMask
    Region { id: cardMask; item: cardSlot }

    // The input region is taken from THIS, an empty item pinned where the
    // card comes to rest, and never from `card` itself, which carries the
    // slide-in Translate. A mask whose item is being transformed leaves
    // the compositor and Qt disagreeing about where the surface accepts
    // input, and the failure is specific and ugly: a click during the
    // slide reaches the QML scene while Hyprland treats it as landing
    // outside the grabbed surface and clears the grab, closing the rail
    // under the pointer. network/NetworkPanel.qml has the full account —
    // it was found there, and this is the shape that fixed it.
    Item {
        id: cardSlot
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: panel.inset
        anchors.rightMargin: panel.inset
        width: panel.cardWidth
        // No bottom anchor — the card hangs from the top inset and stops
        // where its content does.
        height: panel.cardHeight

        // The height changes while the card is up: an app starts playing,
        // a headset connects, the microphone row appears. Animated for the
        // same reason the slide is — a card that jumps a row taller under
        // the pointer reads as a different card.
        Behavior on height {
            NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard }
        }
    }

    // Claim the corner. Why these four are exclusive, and why the rail
    // that loses the claim closes itself rather than being closed, is
    // Panels.claimRightRail's to explain.
    onSurfaceOpened: Panels.claimRightRail("volume")

    Connections {
        target: Panels
        // Another rail took the corner. See Panels.claimRightRail.
        function onRightRailClaimed(name) {
            if (name !== "volume") panel.close()
        }

    }

    // Tells the toast stack how much of the right edge to keep clear —
    // see Panels.rightRailWidth. Tied to `shown`, not to `visible`, so
    // the toasts start moving back as the rail begins sliding out rather
    // than after it has gone. The reservation is the full width even
    // though this card is short: the toasts stack from the top of the
    // same corner, which is exactly where this card is.
    Binding {
        target: Panels
        property: "rightRailWidth"
        value: panel.inset + panel.cardWidth
        when: panel.shown
    }

    Rectangle {
        id: card

        // Fills cardSlot above, so the drawn card and the region this
        // surface claims for input are the same rectangle by
        // construction — the overhang geometry is stated once, up there.
        anchors.fill: cardSlot

        radius: Theme.radius
        color: Appearance.surface
        // 2px to match Hyprland's own `border_size`, exactly as a toast
        // does — the colour here is what shows if HyprFrame is hidden.
        border.width: Theme.hyprBorderWidth
        border.color: Appearance.border
        clip: true

        focus: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                panel.close()
                event.accepted = true
            }
        }

        opacity: panel.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: panel.shown ? panel.enterDuration : panel.exitDuration
                easing.type: panel.shown ? Theme.easingDecel : Easing.InCubic
            }
        }

        // Translate rather than `x`, so the slide never argues with the
        // anchors about where the card belongs — the same reason the
        // toast slots translate instead of moving.
        transform: Translate {
            x: panel.shown ? 0 : panel.slideDistance
            Behavior on x {
                NumberAnimation {
                    duration: panel.shown ? panel.enterDuration : panel.exitDuration
                    easing.type: panel.shown ? Theme.easingDecel : Easing.InCubic
                }
            }
        }

        layer.enabled: true
        layer.effect: PopupShadow {}
        // The Hyprland window border (common/HyprFrame.qml), declared
        // first so everything else paints over it — a toast, the other
        // two rails and the Conf menu all wear this same ring.
        HyprFrame {
            frameWidth: card.border.width
            targetRadius: card.radius
        }

        ColumnLayout {
            id: body

            anchors.fill: parent
            anchors.margins: panel.cardPadding
            spacing: 12

            // ── Header ───────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Volume.icon, the glyph bar/VolumeButton wears in the bar
                // — so the button you pressed and the card it opened are
                // showing you the same mark. It follows the route and the
                // mute the way that button does: a headset glyph on a
                // Bluetooth sink, a crossed speaker in red when muted.
                //
                // A badge standing beside the whole header, at fontHuge,
                // like both other rails. Inert, also like both: the mute
                // control is the speaker on the output row below, where
                // the microphone's own mute sits on the row under that,
                // and a card with two mute controls for the same device
                // would have you guessing which one you pressed.
                Text {
                    text: Volume.icon
                    color: Volume.muted ? Appearance.red : Appearance.fgStrong
                    font.pixelSize: Theme.fontHuge
                    font.family: Theme.font
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1

                    // The device, not the word "Sound" — the same call the
                    // network rail makes with the SSID. What you open this
                    // to find out is what you are listening on; the
                    // controls under it are self-evident without a title
                    // naming them. Volume.deviceName is never blank (it
                    // falls back to "No device"), so the header never
                    // collapses, and SectionTitle already elides, which a
                    // description like "Family 17h/19h HD Audio Analog
                    // Stereo" needs.
                    SectionTitle { text: Volume.deviceName }

                    // The caption under the title, the same slot the other
                    // two rails keep for the one fact you opened the card
                    // to learn. Here that is how much is coming out of
                    // this device — mute first, because a muted card whose
                    // sliders are all up needs to say why nothing is
                    // audible, and then what is actually playing, which is
                    // what the mixer below is a list of.
                    Text {
                        text: Volume.muted ? "Muted"
                            : panel.streamGroups.length === 0 ? "Nothing playing"
                            : panel.streamGroups.length === 1 ? "1 app playing"
                            : panel.streamGroups.length + " apps playing"
                        // fgSoft rather than fgMuted — muted reads too dim
                        // to be a caption under a name (see bar/Clock.qml).
                        color: Volume.muted ? Appearance.red : Appearance.fgSoft
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }
                }
            }

            // ── Output ───────────────────────────────────
            // The shape quicksettings/VolumeTab.qml draws, and the one the
            // OSD draws: a mute glyph, a track, a percentage. The glyph is
            // the mute button, which is why it is the one thing on the row
            // that changes colour.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: Volume.icon
                    color: Volume.muted ? Appearance.red : Appearance.fg
                    font.pixelSize: 18
                    font.family: Theme.font

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                    }

                    MouseArea {
                        anchors.fill: parent
                        // Negative margins, not a bigger glyph: the hit
                        // target is 12px larger every way than the mark
                        // it is under. Every small glyph button in this
                        // shell is clicked this way.
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Volume.toggleMute()
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    interactive: true
                    showKnob: true
                    trackHeight: 4
                    value: Volume.volume / 100
                    trackColor: Appearance.trackBg
                    // Dimmed rather than recoloured while muted, exactly
                    // as a stream row below does: the level is still what
                    // it is, it just isn't reaching anything.
                    fillColor: Volume.muted ? Appearance.fgDim : Appearance.green
                    onMoved: (v) => {
                        Volume.setLinear(v)
                        if (v > 0 && Volume.muted) Volume.toggleMute()
                    }
                }

                Text {
                    text: Volume.muted ? "Muted" : Math.round(Volume.volume) + "%"
                    color: Volume.muted ? Appearance.red : Appearance.fg
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font
                    Layout.preferredWidth: 44
                    horizontalAlignment: Text.AlignRight
                }
            }

            // ── Microphone ───────────────────────────────
            // Hidden outright when there is no input device, rather than
            // shown at zero — on a machine with no microphone this row is
            // not a control that happens to be down, it is a control for
            // something that isn't there. A content-sized card is the one
            // surface where that distinction costs nothing to honour: the
            // card is simply a row shorter.
            RowLayout {
                visible: Mic.deviceName !== "No device"
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: Mic.icon
                    // Orange rather than red while recording is live, the
                    // one state on this card that is about something
                    // reaching the outside rather than leaving it.
                    color: Mic.muted ? Appearance.red
                         : Mic.inUse ? Appearance.orange
                         : Appearance.fg
                    font.pixelSize: 18
                    font.family: Theme.font

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Mic.toggleMute()
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    interactive: true
                    showKnob: true
                    trackHeight: 4
                    value: Mic.volume / 100
                    trackColor: Appearance.trackBg
                    fillColor: Mic.muted ? Appearance.fgDim : Appearance.orange
                    onMoved: (v) => {
                        Mic.setLinear(v)
                        if (v > 0 && Mic.muted) Mic.toggleMute()
                    }
                }

                Text {
                    text: Mic.muted ? "Muted" : Math.round(Mic.volume) + "%"
                    color: Mic.muted ? Appearance.red : Appearance.fg
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font
                    Layout.preferredWidth: 44
                    horizontalAlignment: Text.AlignRight
                }
            }

            // ── Output device ────────────────────────────
            // Capitals and tracking, the section-label shape the network
            // rail settled on (2026-09-18) — set with capitalization
            // rather than by shouting in the string, so the label still
            // reads as a sentence in the source and in a grep, and with
            // the tracking caps need at body size.
            //
            // Both this and the list under it go when there is only one
            // sink: a picker offering the device you are already on is a
            // row of chrome, and this card is meant to stop where its
            // content stops. The settings tab in the footer still lists
            // it, for the machine where a second device is expected to
            // appear and hasn't.
            Text {
                visible: panel.audioSinks.length > 1
                text: "Output device"
                color: Appearance.fg
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Theme.tracking(Theme.fontSmall, 0.12)
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 2
                elide: Text.ElideRight
            }

            // Height is the content's, capped at four rows — past that the
            // list scrolls, hence the bar beside it. Same arrangement as
            // the network rail's known-networks block, including the
            // explicit `Layout.fillHeight: false`: it defaults to true for
            // an item that is itself a layout, and a filling row inside a
            // card that sizes to its content is a card with no height of
            // its own.
            RowLayout {
                visible: panel.audioSinks.length > 1
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Math.min(panel.audioSinks.length, 4) * 30
                Layout.maximumHeight: Layout.preferredHeight
                spacing: 4

                ListView {
                    id: sinkList

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: panel.audioSinks
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: sinkRow
                        required property var modelData

                        readonly property bool isActive: sinkRow.modelData === Volume.sink

                        width: ListView.view.width
                        height: 30
                        radius: Theme.radius
                        color: sinkRow.isActive ? Appearance.selected
                             : (sinkHover.hovered ? Appearance.hover : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 8

                            // The tick keeps its column whether or not it
                            // is drawn, so the device names below it all
                            // start on the same x.
                            Text {
                                text: sinkRow.isActive ? "" : ""
                                color: Appearance.green
                                font.pixelSize: Theme.fontSmall
                                font.family: Theme.font
                                Layout.preferredWidth: 14
                            }

                            Text {
                                text: panel.isBt(sinkRow.modelData) ? "" : ""
                                color: Appearance.fgFaint
                                font.pixelSize: Theme.fontSmall
                                font.family: Theme.font
                            }

                            Text {
                                text: panel.labelFor(sinkRow.modelData)
                                color: Appearance.fg
                                font.pixelSize: Theme.fontNormal
                                font.family: Theme.font
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                            }
                        }

                        HoverHandler { id: sinkHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Pipewire.preferredDefaultAudioSink = sinkRow.modelData
                        }
                    }
                }

                ListScrollBar {
                    view: sinkList
                    Layout.fillHeight: true
                    trackColor: Appearance.scrollTrack
                    thumbColor: Appearance.scrollThumb
                }
            }

            // ── App mixer ────────────────────────────────
            Text {
                text: "Apps"
                color: Appearance.fg
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Theme.tracking(Theme.fontSmall, 0.12)
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 2
                elide: Text.ElideRight
            }

            // One line, not the centred glyph-and-caption empty state the
            // notification rail draws: that one is filling a list's worth
            // of column it would otherwise leave blank, and this card has
            // no such column to fill — it just ends a line earlier.
            Text {
                visible: panel.streamGroups.length === 0
                text: "Nothing is playing audio"
                color: Appearance.fgDim
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
            }

            // Four rows at 60 is the same 240px the sink list's four rows
            // are measured against — the point past which this stops being
            // a card you glance at. Grouping took the browser's pile of
            // tab streams out of this list, so the cap is rarely what
            // stops it now; it stays because a dozen apps playing at once
            // is still a card that has to fit on the screen.
            RowLayout {
                visible: panel.streamGroups.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: false
                // max(...,0) on the gap count: the row is hidden at zero
                // groups, so the negative this produced was never drawn,
                // but a layout asking for -4px of anything is one refactor
                // away from being a real height.
                Layout.preferredHeight: Math.min(panel.streamGroups.length, 4) * 60
                    + Math.max(0, Math.min(panel.streamGroups.length, 4) - 1) * 4
                Layout.maximumHeight: Layout.preferredHeight
                spacing: 4

                ListView {
                    id: streamList

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: panel.streamGroups
                    boundsBehavior: Flickable.StopAtBounds

                    // quicksettings/MixerTab.qml's row, unchanged but for
                    // the colours, which come from Appearance here — a
                    // stream should look the same wherever this shell
                    // shows it, the rule the notification rail keeps by
                    // reusing its history row outright.
                    delegate: Rectangle {
                        id: streamRow
                        // A group from panel.streamGroups: a display name
                        // and the streams it speaks for, which is usually
                        // one of them.
                        required property var modelData

                        readonly property var nodes: streamRow.modelData.nodes

                        readonly property string iconName: panel.groupIconName(streamRow.modelData)
                        readonly property bool hasIcon: streamRow.iconName !== ""
                            && Quickshell.hasThemeIcon(streamRow.iconName)

                        // Muted only once every member is: sound is still
                        // coming out otherwise, and the row would be
                        // claiming a silence you can hear through.
                        //
                        // Both of these read every member on every pass,
                        // with no early exit — a binding is only re-run for
                        // the properties it actually read, so a loop that
                        // broke at the first unmuted stream would stop
                        // watching the ones behind it.
                        readonly property bool muted: {
                            let all = streamRow.nodes.length > 0
                            for (const n of streamRow.nodes)
                                if (!n.audio.muted) all = false
                            return all
                        }

                        // The loudest member, so the row never reads
                        // quieter than what is audible. After any drag
                        // they all hold the same value anyway — see
                        // panel.setGroupVolume.
                        readonly property real volume: {
                            let v = 0
                            for (const n of streamRow.nodes)
                                v = Math.max(v, n.audio.volume)
                            return v
                        }

                        width: ListView.view.width
                        height: 60
                        radius: Theme.radius
                        color: streamHover.hovered ? Appearance.hover : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            Item {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24

                                Image {
                                    visible: streamRow.hasIcon
                                    anchors.fill: parent
                                    source: streamRow.hasIcon ? Quickshell.iconPath(streamRow.iconName) : ""
                                    // Matches the 24x24 container above so
                                    // the SVG rasterises at the size it is
                                    // drawn rather than being rescaled into
                                    // it — see bar/SystemTray.qml for the
                                    // measurement.
                                    sourceSize.width: 24
                                    sourceSize.height: 24
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }

                                // U+F001 (nf-fa-music), the stand-in for a
                                // client that names no icon or names one
                                // this theme hasn't got.
                                Text {
                                    visible: !streamRow.hasIcon
                                    anchors.centerIn: parent
                                    text: ""
                                    color: Appearance.fgFaint
                                    font.pixelSize: 15
                                    font.family: Theme.font
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: streamRow.modelData.name
                                        color: Appearance.fg
                                        font.pixelSize: Theme.fontNormal
                                        font.family: Theme.font
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: streamRow.muted ? "Muted"
                                            : Math.round(streamRow.volume * 100) + "%"
                                        color: streamRow.muted ? Appearance.red : Appearance.fgMuted
                                        font.pixelSize: Theme.fontSmall
                                        font.family: Theme.font
                                    }
                                }

                                Text {
                                    visible: panel.groupSubtitle(streamRow.modelData) !== ""
                                    text: panel.groupSubtitle(streamRow.modelData)
                                    color: Appearance.fgFaint
                                    font.pixelSize: Theme.fontTiny
                                    font.family: Theme.font
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                }

                                Slider {
                                    Layout.fillWidth: true
                                    interactive: true
                                    showKnob: true
                                    trackHeight: 4
                                    // Clamped, not scaled: PipeWire lets a
                                    // client sit above 1.0 and the track
                                    // has nowhere to draw that.
                                    value: Math.min(1, streamRow.volume)
                                    trackColor: Appearance.trackBg
                                    fillColor: streamRow.muted ? Appearance.fgDim : Appearance.green
                                    onMoved: (v) => panel.setGroupVolume(streamRow.modelData, v)
                                }
                            }

                            // U+F026 is the crossed speaker the whole shell
                            // mutes with; U+F028 the full one. Per app, so
                            // silencing the browser doesn't silence the
                            // music.
                            Text {
                                text: streamRow.muted ? "" : ""
                                color: streamRow.muted ? Appearance.red : Appearance.fgMuted
                                font.pixelSize: 15
                                font.family: Theme.font
                                Layout.preferredWidth: 18
                                horizontalAlignment: Text.AlignHCenter

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.setGroupMuted(streamRow.modelData, !streamRow.muted)
                                }
                            }
                        }

                        HoverHandler { id: streamHover }
                    }
                }

                ListScrollBar {
                    view: streamList
                    Layout.fillHeight: true
                    trackColor: Appearance.scrollTrack
                    thumbColor: Appearance.scrollThumb
                }
            }

        }
    }
}
