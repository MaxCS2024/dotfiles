// The network rail — a three-fifths-height slide-out on the top right.
//
// Geometry is deliberately the notification stack's, not a panel's:
// notifications/NotificationPopups.qml holds itself `inset` (8px) off the
// screen edges, and Hyprland tiles windows at `gaps_out` 15
// (hypr/modules/decorations.lua), so a toast overhangs the window column by
// 7px on every edge it touches. That overhang is the whole look — the rail
// reads as belonging to the desktop's furniture rather than to the tiling
// grid — and this reproduces it exactly: same 8px inset, the same
// enter/exit curves and a width in the same family (450 against a toast's
// 320). It ran the full height between the bar and the screen floor until
// 2026-09-18, when the user asked for half as long, then for a fifth of
// that back: it is now anchored top and right only, and takes three fifths
// of that column. The overhang is unchanged
// where the card still touches a screen edge — 7px at the top and the
// right — and the bottom edge, which now floats mid-screen, gets none
// because there is no edge there to hold itself off.
//
// Colours come from theme/Appearance.qml rather than config/Theme.qml,
// unlike NotificationCard next door: Appearance falls through to the same
// Theme tokens by default but also honours a pinned custom palette, which
// is what every surface written since the bento dashboard does. Geometry,
// motion and the Hyprland frame still come from Theme/common so the card
// material itself is the toasts'.
//
// Content is the glanceable half of quicksettings/NetworkTab.qml (status,
// interface, IP, DNS, the AP list) plus the two things a tab that size had
// no room for — live throughput and the airplane-mode switch. The tab is
// still there and still reachable from the footer; this is the surface you
// open to look, that one is the surface you open to configure.
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"
import "../common/qrcode.js" as QrCode

ShellSurface {
    id: panel

    surfaceNamespace: "quickshell:network"
    surfaceName: "network"
    focusTarget: card

    // Matched to notifications/NotificationPopups.qml — see the header.
    // `inset` is the gap held off all three screen edges the rail touches.
    // 450, where a toast is still 320. Widened three times at the user's
    // asking on 2026-09-17: 320 → 360 → 400, then 400 plus an eighth of
    // itself. Two lists of network names live in this column, and an SSID
    // like Tele2_4837C6_EXT_Djupvik was eliding in the middle of every
    // one of them at the first of those widths. The overhang the header
    // describes is unchanged — that is the inset's doing, not the
    // width's.
    readonly property int cardWidth: 450

    // Three fifths of the column the rail used to fill, measured off the
    // same insets that column was held by. It was halved on 2026-09-18 at
    // the user's asking and then given back a fifth of itself the same day
    // — the width's own 400-plus-an-eighth, one axis over — which is a half
    // plus a tenth, hence 3/5 rather than a factor applied to a factor.
    // Derived rather than a number: this surface is already the screen
    // below the bar, so it tracks the bar's height and the monitor's
    // without being told either. Rounded, because a fraction would
    // otherwise put the card's bottom edge on a part pixel and soften the
    // border there.
    //
    // Everything above the AP list in the Wi-Fi tab is fixed or capped, so
    // this is the list's height — see the "Other networks" section.
    readonly property int cardHeight: Math.round((panel.height - panel.inset * 2) * 3 / 5)

    // Far enough that the card *and* its shadow are past the screen edge.
    readonly property int slideDistance: panel.cardWidth + panel.inset + 24

    // Which tab the card is showing: 0 = Wi-Fi, 1 = Bluetooth & DNS.
    // Deliberately not persisted — the rail is a glance surface, and it
    // should open on what you are connected to, not on wherever you last
    // went to change a setting.
    property int tab: 0

    // Whether the Custom DNS field is showing. On the panel rather than
    // inside the delegate that toggles it, because the Repeater owns that
    // delegate's lifetime and a provider change rebuilds it.

    // Full screen (below the bar), not a 352px strip hugging the right
    // edge. The rail itself is still a 450px card anchored to that edge —
    // see `card` below, which is what actually looks like the toast stack
    // — but the share sheet has to be able to centre a QR code on the
    // *screen*, and an overlay can only centre itself within the surface
    // it lives on. The alternative was a second layer-shell window for the
    // sheet, which would then need its own HyprlandFocusGrab arguing with
    // this one over the same click. The extra area costs a transparent
    // surface and nothing else: `mask` below keeps it click-through
    // whenever the sheet isn't up, exactly as the toast stack does with
    // its own full-height surface.
    anchors { top: true; bottom: true; left: true; right: true }
    // Reserve nothing, respect what the bar reserves — which is what puts
    // this surface's top edge under the bar rather than behind it.
    exclusiveZone: 0
    // Only the card takes clicks, so the rest of the screen this surface
    // now covers stays click-through — the same idiom the toast stack and
    // the OSDs use. `null` means "the whole window", which is what the
    // share sheet needs so its scrim can be clicked to dismiss; bar/Bar.qml
    // switches its own mask the same way.
    mask: panel.shareShown ? null : cardMask
    Region { id: cardMask; item: cardSlot }

    // The input region is taken from THIS, an empty item pinned where the
    // card comes to rest, and never from `card` itself.
    //
    // `card` carries the slide-in Translate, and a mask whose item is
    // being transformed leaves the compositor and Qt disagreeing about
    // where this surface accepts input: a click shortly after opening
    // reached the QML scene (a button handler ran) while Hyprland treated
    // the same click as landing outside the grabbed surface, cleared the
    // focus grab, and closed the rail. Logged from three consecutive real
    // opens — "open() -> focusGrab CLEARED -> close()", every one of them
    // inside the first 1.5s, i.e. around the slide.
    //
    // This is also the one thing that made the rail different from the two
    // surfaces in this shell that have always worked: powermenu's `box`
    // and the toast stack's `column` are both mask items that never move,
    // and both translate their *children* instead. Matching that is the
    // fix — the card still slides, the region it claims just stops sliding
    // with it.
    Item {
        id: cardSlot
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: panel.inset
        anchors.rightMargin: panel.inset
        width: panel.cardWidth
        // No bottom anchor since the halving — the card hangs from the top
        // inset and stops at `cardHeight`.
        height: panel.cardHeight
    }

    // Claim the corner — see Panels.claimRightRail for why these four
    // are exclusive.
    //
    // The scanner is always on (services/Network.qml), so scan() is only
    // the "Scanning…" pulse — but opening the rail is exactly the moment
    // the list wants to look freshly taken. The profile list has no
    // watcher behind it — nmcli is a question asked, not a subscription
    // — so the open is where it is asked. And the header caption goes
    // back to the signal strength: the speed result borrows that line
    // (see the Text itself), and a figure measured before the rail was
    // last closed is describing a network this machine may not be on any
    // more.
    onSurfaceOpened: {
        Panels.claimRightRail("network")
        Network.scan()
        Network.refreshKnown()
        Network.clearSpeedTest()
        panel.tab = 0
    }

    // The share sheet is a second surface over this one and does not
    // survive the rail going away underneath it.
    onSurfaceClosed: panel.closeShare()

    // Clipboard for the two address cells in the stat grid. `sh -c` with
    // the value passed as $1 rather than spliced into the string: an SSID
    // or an address is not this shell's to quote, and bar/ClipboardButton
    // next door interpolates only ids it generated itself.
    Process { id: copyProc }
    function copyValue(value) {
        if (value === "") return
        copyProc.running = false
        copyProc.command = ["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", value]
        copyProc.running = true
    }

    // Ping costs packets, so it runs while the rail is up and not
    // otherwise — see the Reachability block in services/Network.qml.
    // A Binding rather than a line in open()/close(), so a rail that is
    // torn down some other way can't leave the poll running behind it.
    Binding {
        target: Network
        property: "pingActive"
        value: panel.shown
    }

    Connections {
        target: Panels
        // Another rail took the corner. See Panels.claimRightRail.
        function onRightRailClaimed(name) {
            if (name !== "network") panel.close()
        }

    }

    // Tells the toast stack how much of the right edge to keep clear —
    // see Panels.rightRailWidth. Tied to `shown`, not to `visible`, so the
    // toasts start moving back as the rail begins sliding out rather than
    // after it has gone.
    Binding {
        target: Panels
        property: "rightRailWidth"
        value: panel.inset + panel.cardWidth
        when: panel.shown
    }

    // A plain connect is tried first and only the NoSecrets failure prompts,
    // and a second pskRequired for the same ssid (wrong password) shows an
    // inline error rather than reopening the prompt.
    property string _pendingPskSsid: ""

    Connections {
        target: Network
        function onPskRequired(ssid) {
            panel._pendingPskSsid = ssid
            if (pwPrompt.shown) pwPrompt.showError("Incorrect password")
            else pwPrompt.open("Wi-Fi Password", ssid)
        }
    }

    // ── Wi-Fi share sheet ────────────────────────────────
    // The PSK is pulled only while the sheet is up and dropped the moment
    // it closes — see Network.loadShare()'s comment. close() below clears
    // it too, so dismissing the whole rail (Escape, or focus moving away)
    // can't leave a password sitting in the service.
    property bool shareShown: false

    function openShare() {
        panel.shareShown = true
        Network.loadShare()
    }

    function closeShare() {
        panel.shareShown = false
        Network.clearShare()
    }

    Rectangle {
        id: card

        // Fills cardSlot above, so the drawn card and the region this
        // surface claims for input are the same rectangle by construction
        // — the overhang geometry is stated once, up there.
        anchors.fill: cardSlot

        radius: Theme.radius
        color: Appearance.surface
        // 2px to match Hyprland's own `border_size`, exactly as a toast
        // does — the colour here is what shows if HyprFrame is ever hidden.
        border.width: Theme.hyprBorderWidth
        border.color: Appearance.border
        clip: true

        focus: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                // One layer at a time: Escape out of the share sheet
                // leaves the rail up, which is what you want after
                // showing someone a code.
                if (panel.shareShown) panel.closeShare()
                else panel.close()
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
        // anchors about where the card belongs — the same reason the toast
        // slots translate instead of moving.
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
        // The Hyprland window border (common/HyprFrame.qml), declared first
        // so everything else paints over it — a toast, the Conf menu and the
        // settings panel all wear this same ring.
        HyprFrame {
            frameWidth: card.border.width
            targetRadius: card.radius
        }

        ColumnLayout {
            id: body

            anchors.fill: parent
            anchors.margins: Theme.space4
            spacing: Theme.space3

            // ── Header ───────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                // Network.icon, the same glyph bar/NetworkButton wears in
                // the bar — so the button you pressed and the card it
                // opened are showing you the same mark. It is the wifi
                // glyph on wifi, but it follows the connection rather than
                // being fixed: ethernet on a wired link, wifi-off when
                // there is none, which is the one case where a wifi glyph
                // would be claiming something untrue.
                //
                // A badge standing beside the whole header, where it used
                // to sit on the name's own line at the name's own size
                // (user request 2026-09-18, the same day the notification
                // rail took this shape). The case against it was that a
                // mark spanning both lines competes with the name for a
                // row that also carries three controls; what decides it
                // the other way is that the two rails are one surface on
                // two subjects, and the first thing on the card is what
                // says which of them you opened. fontHuge, as next door.
                // Not bold — a Nerd Font glyph has no bold cut to take.
                Text {
                    text: Network.icon
                    color: Appearance.fgStrong
                    font.pixelSize: Theme.fontHuge
                    font.family: Theme.font
                    Layout.alignment: Qt.AlignVCenter
                }

                // The network, not the word "Network" (user request
                // 2026-09-17): the rail is opened to find out what this
                // machine is on, and the title is the first thing read.
                // Network.displayName is the SSID, or "Ethernet", or
                // "Disconnected" — never blank, so the header never
                // collapses. It already elides, which an SSID needs and
                // the old word never did.
                //
                // The line under it is what the hero card used to say
                // beside a copy of this same name. The card went with the
                // duplication (user request 2026-09-17) and this is the
                // half of it that was never anywhere else: the strength,
                // and the three states a percentage has no way to
                // describe. It sits under the title rather than beside it
                // so that a long SSID and a caption are not competing for
                // one row with three buttons.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1

                    SectionTitle { text: Network.displayName }

                    // The speed test borrows this line while it has
                    // something to say (user request 2026-09-18). Moving
                    // the test up to the button row left its reading with
                    // nowhere to land, and this is the caption directly
                    // under the button that starts it — no row of its own,
                    // no height taken off the network lists. It gives the
                    // line back on the next open(), which clears the
                    // result: the rail is a glance surface, and what it
                    // should say when you open it is what you are
                    // connected to, not what a test measured an hour ago.
                    Text {
                        text: Network.speedTesting ? "Testing speed…"
                            : Network.speedError !== "" ? Network.speedError
                            : Network.speedDown > 0
                                ? Network.speedDown.toFixed(0) + " Mbps · "
                                  + Network.speedLatency.toFixed(0) + " ms"
                            : AirplaneMode.enabled ? "Airplane mode"
                            : Network.type === "ethernet" ? "Wired connection"
                            : Network.type === "wifi" ? Network.strength + "% signal"
                            : "No connection"
                        // fgSoft rather than fgMuted — see the note in
                        // bar/Clock.qml that quicksettings/ and
                        // systemsettings/ already point back at: muted
                        // reads too dim to be a caption under a name.
                        // A finished result steps up to fg: it is the one
                        // thing this line ever says that was asked for
                        // rather than merely true.
                        color: Network.speedError !== "" ? Appearance.orange
                             : (Network.speedDown > 0 && !Network.speedTesting) ? Appearance.fg
                             : Appearance.fgSoft
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }
                }

                // Share the current Wi-Fi as a QR code. Wi-Fi only —
                // there is nothing to hand a phone about a wired link,
                // and a button that is present but inert is worse than
                // one that isn't there.
                Rectangle {
                    visible: panel.tab === 0 && Network.type === "wifi" && Network.connected
                    implicitWidth: 28
                    implicitHeight: 24
                    radius: Theme.radius
                    color: shareHover.hovered ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong)
                    border.width: 1
                    border.color: Appearance.border

                    Text {
                        anchors.centerIn: parent
                        text: "\uf029"
                        color: Appearance.fgSoft
                        font.pixelSize: Theme.fontMedium
                        font.family: Theme.font
                    }

                    HoverHandler { id: shareHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.openShare()
                    }
                }

                // Speed test. Was a labelled row down in the detail block
                // until 2026-09-18, where it sat under three readings that
                // are all free and continuous and looked like a fourth.
                // It is the only thing on this card that costs something
                // to ask for — fast.com, three parallel transfers, about
                // 75MB — so it belongs with the other deliberate actions
                // rather than among the things the card simply knows. See
                // Network.runSpeedTest.
                //
                // Wi-Fi tab only, like the share and rescan buttons it
                // sits beside: the reading lands in the caption under
                // this row, and that caption is describing the connection
                // the Wi-Fi tab is about.
                Rectangle {
                    visible: panel.tab === 0
                    implicitWidth: 28
                    implicitHeight: 24
                    radius: Theme.radius
                    color: speedHover.hovered ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong)
                    border.width: 1
                    border.color: Appearance.border

                    Text {
                        anchors.centerIn: parent
                        // nf-md-speedometer, and nf-md-timer_sand while it
                        // runs — the same swap the old row made, and the
                        // same surrogate-pair form the airplane glyph
                        // above explains. A speedometer rather than the
                        // row's play triangle: with the label gone the
                        // glyph is all there is to say which button this
                        // is, and a triangle only says "start something".
                        text: Network.speedTesting ? "\udb81\udd1f" : "\udb81\udcc5"
                        color: Network.speedTesting ? Appearance.accent : Appearance.fgSoft
                        font.pixelSize: Theme.fontMedium
                        font.family: Theme.font

                        Behavior on color {
                            ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                        }
                    }

                    HoverHandler { id: speedHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: !Network.speedTesting
                        onClicked: Network.runSpeedTest()
                    }
                }

                // Airplane mode, a slide toggle since 2026-09-18 at the
                // user's asking. It was a glyph button tinted when armed,
                // which is the shape every other control in this row has —
                // and the two are not the same kind of thing: the buttons
                // do something once and are finished, this one puts the
                // machine into a state and leaves it there. A switch says
                // that on sight, and says it at rest rather than only for
                // the moment after it is pressed.
                //
                // Last in the row, where the rescan button used to be. A
                // switch between two glyph buttons reads as a third
                // button someone drew wrong; at the edge it reads as the
                // one thing in the header that isn't a button.
                //
                // Unlabelled, at the user's asking — the airplane glyph
                // sat to its left for one commit. So the header carries a
                // switch that does not say what it switches, and the
                // caption under the title is the only thing that names
                // it, once it is already on ("Airplane mode", where the
                // signal strength otherwise goes).
                //
                // No `visible` binding, unlike the two beside it: this is
                // a radio mode, not a Wi-Fi tab action, and it is the one
                // control that has to stay reachable from the Bluetooth
                // tab — turning the radios off is how you get there.
                //
                // Checked means the radios are *on* — the inverse of
                // AirplaneMode.enabled. Unlabelled, a switch in the
                // network panel's header reads as "network", and with
                // `checked: AirplaneMode.enabled` it sat off while the
                // network was up, which read as broken.
                ToggleSwitch {
                    checked: !AirplaneMode.enabled
                    trackOffColor: Appearance.trackBg
                    trackOnColor: Appearance.accent
                    borderColor: Appearance.border
                    knobColor: Appearance.fgStrong
                    onToggled: AirplaneMode.toggle()
                }
            }

            // ── Tabs ─────────────────────────────────────
            // Two levels of the same subject: what this machine is
            // connected to right now, and the two things you change
            // rather than watch. Bluetooth and DNS share a tab because
            // neither fills one on its own and both are "set it and
            // forget it" — see the sections themselves.
            //
            // A segmented control: one track holds all three, and the
            // selected tab is marked by a plate that slides behind it
            // rather than by each button drawing its own box.
            Rectangle {
                id: tabTrack
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: 24 + 2 * tabTrack.pad
                radius: Theme.radius
                color: Appearance.trackBg
                border.width: 1
                border.color: Appearance.border

                readonly property int pad: Theme.space1

                // Behind the Repeater, so it paints under the labels.
                //
                // Placed by arithmetic on the tab index, not by reading
                // tabRepeater.itemAt(panel.tab): itemAt() isn't a notifying
                // property, so a binding that ran before the delegates
                // existed stayed null, and since opening only re-assigns
                // tab = 0 the rail opened with nothing selected. The tabs
                // are equal width (fillWidth, no implicit width), so the
                // slot is all this needs.
                Rectangle {
                    id: tabHighlight
                    readonly property real slot: (tabRow.width - tabRow.spacing * (tabRepeater.count - 1)) / Math.max(1, tabRepeater.count)
                    x: tabRow.x + panel.tab * (tabHighlight.slot + tabRow.spacing)
                    y: tabRow.y
                    width: tabHighlight.slot
                    height: tabRow.height
                    radius: Theme.radius
                    color: SlabStyle.tintSelected

                    Behavior on x {
                        NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingDecel }
                    }
                }

                RowLayout {
                    id: tabRow
                    anchors.fill: parent
                    anchors.margins: tabTrack.pad
                    spacing: tabTrack.pad

                    Repeater {
                        id: tabRepeater
                        model: ["Wi-Fi", "Bluetooth", "DNS"]

                        delegate: Rectangle {
                            id: tabBtn
                            required property int index
                            required property string modelData

                            readonly property bool current: panel.tab === tabBtn.index

                            Layout.fillWidth: true
                            implicitHeight: 24
                            radius: Theme.radius
                            color: !tabBtn.current && tabHover.hovered
                                ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong)

                            Behavior on color {
                                ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: tabBtn.modelData
                                color: tabBtn.current ? Appearance.fgStrong : Appearance.fgSoft
                                font.pixelSize: Theme.fontSmall
                                font.family: Theme.font
                            }

                            HoverHandler { id: tabHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.tab = tabBtn.index
                            }
                        }
                    }
                }
            }

            // ── Wi-Fi tab ────────────────────────────────
            // The three tabs and the Modes row below are siblings in
            // network/, each taking nothing but its visibility. They were
            // 1,000 lines inside this file until 2026-09-21, and every
            // commit that touched one of them had to be made in a
            // 1,752-line file regardless of which tab it was about.
            WifiTab {
                visible: panel.tab === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                onCopyRequested: (value) => panel.copyValue(value)
                onDnsRequested: panel.tab = 2
            }

            // ── Bluetooth tab ────────────────────────────
            BluetoothTab {
                visible: panel.tab === 1
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            // ── DNS tab ──────────────────────────────────
            DnsTab {
                visible: panel.tab === 2
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            // ── Modes ────────────────────────────────────
            // network/ModesRow.qml — outside all three tabs, so it stays
            // reachable whichever one is open.
            ModesRow {
                Layout.fillWidth: true
            }

        }

        // Inside the card rather than the window so it is covered by the
        // same mask — the gutter beside the card stays click-through even
        // while the prompt is up.
        PasswordPrompt {
            id: pwPrompt
            onAccepted: (password) => Network.connectWithPsk(panel._pendingPskSsid, password)
            onCancelled: panel._pendingPskSsid = ""
        }
    }

    // ── Share sheet ──────────────────────────────
    // Centred on the screen, not on the rail (user request 2026-09-16) —
    // a code being held up for someone else to scan is the one thing this
    // shell draws that another person is meant to look at, and 264px of it
    // tucked into a column on the right edge is not that.
    //
    // A sibling of the card rather than a child of it, so it is neither
    // clipped by the card nor carried along by the card's slide, and a
    // plain overlay rather than a second layer-shell window, so the rail's
    // single HyprlandFocusGrab still covers everything on screen — see the
    // window's own anchors comment for why that surface went full screen.
    Rectangle {
        id: shareSheet

        anchors.fill: parent
        z: 90
        visible: shareSheet.opacity > 0
        enabled: panel.shareShown
        // Deeper than a card-sized scrim needed: this one covers the whole
        // screen, and the point of it is that nothing competes with the
        // code. Same value the power menu uses for the same reason.
        color: Qt.rgba(0, 0, 0, 0.62)
        opacity: panel.shareShown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.animPanel; easing.type: Theme.easingStandard }
        }

        // The payload only exists while the sheet is up, because the
        // credentials behind it only exist while the sheet is up.
        readonly property string payload: Network.shareSsid === "" ? ""
            : QrCode.wifiPayload(Network.shareSsid, Network.shareSecurity,
                                 Network.sharePassword)

        // The scrim is not live until the sheet has finished appearing.
        //
        // Without this the click that OPENS the sheet also dismisses it:
        // the QR button's own release handler is what sets shareShown, so
        // by the time that click finishes being delivered this scrim
        // already exists underneath the pointer and takes it as a dismiss.
        // Confirmed from a log of five consecutive real clicks, every one
        // of them "QR button clicked -> openShare() -> scrim clicked ->
        // closeShare()", which is why the code never appeared to open.
        // Arming on the reveal animation rather than on a bare timer ties
        // it to the thing it actually has to outlast.
        property bool armed: false

        Timer {
            interval: Theme.animPanel
            running: panel.shareShown
            onTriggered: shareSheet.armed = true
            onRunningChanged: if (!running) shareSheet.armed = false
        }

        // A click anywhere on the scrim dismisses; the plate below swallows
        // its own so a click on the code doesn't close it.
        MouseArea {
            anchors.fill: parent
            enabled: shareSheet.armed
            onClicked: panel.closeShare()
        }

        // No card behind any of this: the code and its labels sit straight
        // on the scrim, which is already dark enough to carry them.
        Item {
            id: sharePlate

            anchors.centerIn: parent
            // Fixed rather than a fraction of the screen: the code wants to
            // be a comfortable scanning size on any monitor, and a code
            // sized off a 4K screen would be a wall of white.
            width: 332
            height: sheetCol.implicitHeight

            // Rises and settles rather than appearing — the same decel
            // curve everything else in this panel moves on.
            opacity: panel.shareShown ? 1 : 0
            scale: panel.shareShown ? 1 : 0.94
            Behavior on scale {
                NumberAnimation { duration: panel.enterDuration; easing.type: Theme.easingDecel }
            }

            // Swallows clicks on the code and its labels so they don't
            // reach the scrim underneath and dismiss the sheet.
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: sheetCol
                anchors.centerIn: parent
                width: parent.width
                spacing: Theme.space2

                Text {
                    text: "Share Wi-Fi"
                    color: Appearance.fgStrong
                    font.bold: true
                    font.pixelSize: Theme.fontMedium
                    font.family: Theme.font
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                // The white plate is part of the code, not decoration —
                // see NetworkQrCard.qml on quiet zones and polarity.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: width
                    radius: Theme.radius
                    color: "#ffffff"
                    visible: qr.valid && shareSheet.payload !== ""

                    NetworkQrCard {
                        id: qr
                        anchors.fill: parent
                        anchors.margins: Theme.space2
                        payload: shareSheet.payload
                    }
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: text !== ""
                    text: Network.shareLoading ? "Reading credentials\u2026"
                        : Network.shareError !== "" ? Network.shareError
                        : shareSheet.payload === "" ? ""
                        : !qr.valid ? "This network's details are too long to encode"
                        : Network.shareSsid
                    color: Network.shareError !== "" ? Appearance.red : Appearance.fgStrong
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: qr.valid && shareSheet.payload !== ""
                    text: "Scan to join"
                    color: Appearance.fgSoft
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.font
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.radius
                    color: closeHover.hovered ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong)
                    border.width: 1
                    border.color: Appearance.border

                    Text {
                        anchors.centerIn: parent
                        text: "Done"
                        color: Appearance.fgSoft
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                    }

                    HoverHandler { id: closeHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.closeShare()
                    }
                }
            }
        }
    }
}
