import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

// The Wi-Fi half of the network rail: what this machine is connected to,
// the stat grid under it, and the two lists of networks — the ones it
// already has a profile for, and everything else the adapter can hear.
//
// 550 lines that reached out of the rail exactly twice, which is why this
// is a file of its own since 2026-09-21: to put an address on the
// clipboard, and to send the reader to the DNS tab. Both are signals now,
// so this knows nothing about the panel that shows it.
ColumnLayout {
    id: root

    // The address cells in the stat grid copy on click; the rail owns the
    // clipboard, because wl-copy is not this tab's business.
    signal copyRequested(string value)

    // The DNS row under the grid is a way in to the DNS tab.
    signal dnsRequested()
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 12

    // The live Down/Up tiles stood here until 2026-09-17,
    // when they went at the user's request along with the
    // interface row below; NetworkRateTile.qml, which had no
    // other caller, went with them.
    // Network.rxRate/txRate are still live and still read —
    // bar/NetworkButton.qml's tooltip prints both — and the
    // speed test in the detail block is the reading this tab
    // keeps: what the link can do rather than what happens to
    // be crossing it.

    // ── Detail ───────────────────────────────────
    // Labels are fgMuted and values are fg, here and in the
    // DNS row below (user request 2026-09-18). Both halves
    // used to be fg: the grid's two label columns and its two
    // value columns were the same tone, so "Ping 4 ms Packet
    // Loss 0%" read as one run of text and you had to parse
    // the words to find where each reading started. A tone
    // apart and the four columns separate at a glance, which
    // is the whole argument for a grid over eight rows.
    //
    // fgMuted is what common/InfoRow.qml already uses for its
    // own labels, so this block ends up the same label/value
    // pairing that component makes, laid out four across
    // rather than one to a line. It sat on fgFaint for one
    // commit because fgMuted was unreadable under a pinned
    // palette — rgb(44,47,58) on a card of rgb(36,40,59) —
    // and reads rgb(132,145,172) since that was fixed in
    // config/Theme.qml and theme/Appearance.qml. fgFaint is
    // still a defensible choice here and gives a little more
    // separation; this follows the convention instead.
    //
    // The DNS row moves with it: it sits directly under this
    // grid, and two label tones a line apart read as two
    // different kinds of row.
    //
    // The interface name was a row here until 2026-09-17
    // (user request). Network.iface is still what the IP
    // lookup, the throughput counters and the DNS query are
    // all keyed on — it just isn't something the rail says
    // out loud any more.
    // Four rows of two, rather than eight InfoRows: these are
    // eight short readings, and stacking them one to a line
    // would take the whole card for something you read at a
    // glance. Paired left to right so each line holds one
    // idea — the round trip, the instantaneous rate, the
    // total since the link came up, the addresses.
    //
    // Every cell stays mounted whether or not there is a
    // sample behind it and reads "--" until there is. The
    // ping is five seconds behind the open and the counters
    // one second, and a grid that grew a row at a time as
    // each arrived would shove the network lists down twice
    // in the first moments the rail is up.
    GridLayout {
        Layout.fillWidth: true
        columns: 4
        columnSpacing: 12
        rowSpacing: 4

        // Label, then value right-aligned against the middle
        // or the right edge — the same shape as the DNS and
        // Speed test rows below, run twice across.
        component StatLabel: Text {
            color: Appearance.fgMuted
            font.pixelSize: Theme.fontNormal
            font.family: Theme.font
            elide: Text.ElideRight
        }

        component StatValue: Text {
            color: Appearance.fg
            font.pixelSize: Theme.fontNormal
            font.family: Theme.font
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.minimumWidth: 0
        }

        // A StatValue that puts itself on the clipboard. The
        // only cue is the cell brightening under the pointer,
        // the same one the network rows below use — a copy
        // button per address would be two more glyphs in a
        // grid whose whole point is that it is dense.
        component CopyValue: Text {
            id: copyCell
            required property string value

            color: (copyHover.hovered && copyCell.value !== "")
                ? Appearance.fgStrong : Appearance.fg
            font.pixelSize: Theme.fontNormal
            font.family: Theme.font
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.minimumWidth: 0

            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

            HoverHandler { id: copyHover }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: copyCell.value !== ""
                onClicked: root.copyRequested(copyCell.value)
            }
        }

        // Loss colours its own cell and the latency beside
        // it: a 4ms round trip is a fine number and a
        // misleading one when a third of the echoes never
        // came back, so the pair is read together or not at
        // all.
        StatLabel { text: "Ping" }
        StatValue {
            text: Network.pingLatency >= 0
                ? Network.pingLatency.toFixed(0) + " ms" : "--"
            color: Network.pingLoss > 0 ? Appearance.red : Appearance.fg
        }
        StatLabel { text: "Packet Loss" }
        StatValue {
            text: Network.pingLoss >= 0 ? Network.pingLoss + "%" : "--"
            color: Network.pingLoss > 0 ? Appearance.red : Appearance.fg
        }

        // The Down/Up tiles this rail carried until
        // 2026-09-18 said the same thing in a lot more room.
        // Same counters, two cells.
        StatLabel { text: "Receiving" }
        StatValue { text: Network.rxBytes >= 0 ? Network.fmtRate(Network.rxRate) : "--" }
        StatLabel { text: "Sending" }
        StatValue { text: Network.txBytes >= 0 ? Network.fmtRate(Network.txRate) : "--" }

        StatLabel { text: "Downloaded" }
        StatValue { text: Network.rxBytes >= 0 ? Network.fmtBytes(Network.rxBytes) : "--" }
        StatLabel { text: "Uploaded" }
        StatValue { text: Network.txBytes >= 0 ? Network.fmtBytes(Network.txBytes) : "--" }

        // Both copyable: an address is something you are
        // reading in order to type it somewhere else, and
        // this is the surface you already have open when you
        // need it. The whole cell takes the click rather
        // than a glyph beside it — there is no destructive
        // reading of "copy", so it doesn't need the narrow
        // hit target the speed test does.
        StatLabel { text: "IP Address" }
        CopyValue {
            text: Network.ip || "--"
            value: Network.ip
        }
        StatLabel { text: "Gateway" }
        CopyValue {
            text: Network.gateway || "--"
            value: Network.gateway
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
            text: "DNS"
            // fgMuted, with the grid's labels above it — see
            // the section comment. This row is lifted from
            // quicksettings/NetworkTab.qml, which still sets
            // its own labels to fg; that surface has no grid
            // over it to agree with.
            color: Appearance.fgMuted
            font.pixelSize: Theme.fontNormal
            font.family: Theme.font
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
        }
        Text {
            text: Network.currentDns
            color: Appearance.fg
            font.pixelSize: Theme.fontNormal
            font.family: Theme.font
            elide: Text.ElideRight
            Layout.maximumWidth: 120
        }
        Text {
            text: "\uf061"
            color: dnsHover.hovered ? Appearance.fgStrong : Appearance.fgDim
            font.pixelSize: Theme.fontTiny
            font.family: Theme.font

            HoverHandler { id: dnsHover }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                // Was a deep link out to the settings
                // window's "dns" section, which meant closing
                // this window to go and change a value this
                // card now owns. It is a tab switch instead.
                onClicked: root.dnsRequested()
            }
        }
    }

    // The rule that used to run here is gone at the user's
    // asking (2026-09-18), and this is the 1px it occupied,
    // kept so the gap either side of it doesn't close up. The
    // section headers below are already in caps and already
    // sit in their own whitespace, so they were doing the
    // dividing twice over.
    //
    // An Item and not `Divider { visible: false }`: a Layout
    // skips an invisible child entirely, taking its row and
    // one of the two 12px gaps around it with it, which is
    // the spacing this is here to preserve.
    Item { Layout.fillWidth: true; implicitHeight: 1 }

    // ── Known networks ───────────────────────────
    // The ones in range that this machine already has a
    // profile for — yours, in effect, out of everything the
    // adapter can hear. Saved networks that aren't in range
    // are left out of it entirely (user request 2026-09-17);
    // see Network.knownNetworks, which is where that happens.
    //
    // Above the scan, and the connected one at the top: these
    // are the rows a click does something useful with, and
    // what is merely audible is the longer, less interesting
    // list underneath.
    //
    // Hidden entirely when there are none rather than left as
    // a header over nothing — a network this machine has
    // never joined is every row of a fresh install, and every
    // row anywhere but home.
    Text {
        // Capitals at the user's asking (2026-09-18), and
        // set with capitalization rather than by shouting
        // in the string so the label still reads as a
        // sentence in the source and in a grep. The
        // tracking comes with it: every capitalised label
        // in this shell carries some — bar/StatusMeters.qml
        // and lockscreen/LockScreen.qml at the same 0.12em
        // — because caps set at body tracking close up.
        text: "Known networks"
        color: Appearance.fg
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Theme.tracking(Theme.fontSmall, 0.12)
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.topMargin: 2
        visible: Network.knownCount > 0
        elide: Text.ElideRight
    }

    // Height is the content's, capped at five rows, while the
    // scan list below takes whatever the screen has left.
    // Fixing the short list and letting the live one breathe
    // is what keeps a machine with twenty profiles from
    // pushing everything in range off the bottom of the card.
    // Past five the list scrolls, hence the bar beside it.
    RowLayout {
        Layout.fillWidth: true
        // Explicitly NOT a filling row: Layout.fillHeight
        // defaults to true for an item that is itself a
        // layout, so leaving it out here had this block and
        // the scan list above splitting the card's spare
        // height between them — the live list squeezed to
        // about one row while a static list of six took 180px.
        Layout.fillHeight: false
        Layout.preferredHeight: Math.min(Network.knownCount, 5) * 30
        Layout.maximumHeight: Layout.preferredHeight
        visible: Network.knownCount > 0
        spacing: 4

        ListView {
            id: knownList

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: Network.knownNetworks
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: knownRow
                required property var modelData

                // Every row here is in range, so being on it
                // already is the only thing that leaves a
                // click nowhere to go.
                readonly property bool joinable: !knownRow.modelData.active

                // Every cue the hover drives — the fill, the
                // glyph and the two labels — reads off this one
                // expression, so a row can't end up half lit.
                readonly property bool lit: knownHover.hovered && knownRow.joinable

                width: knownList.width
                height: 30
                radius: Theme.radius
                // hoverStrong rather than hover (user request
                // 2026-09-18). `hover` is a single elevation
                // step over the card's own `surface`, which on
                // a dark palette is a handful of units of
                // lightness — enough under a 36px button,
                // invisible under a 30px row you are moving
                // across. The chips at the top of this card
                // are all on hoverStrong already, so the rows
                // now answer at the volume the rest of the
                // surface does.
                color: knownRow.lit ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong)

                Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    // The fill is only half of it: a row
                    // lighting up is mostly its text going
                    // brighter, and lifting three already-dim
                    // tokens by one step each buys more
                    // legible motion than another step of
                    // background would — and takes no contrast
                    // away from the connected row, which keeps
                    // its green either way.
                    Text {
                        text: "\uf1eb"
                        color: knownRow.modelData.active ? Appearance.green
                            : knownRow.lit ? Appearance.fg : Appearance.fgFaint
                        font.pixelSize: Theme.fontNormal
                        font.family: Theme.font
                        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                    }
                    Text {
                        text: knownRow.modelData.ssid
                        color: (knownRow.modelData.active || knownRow.lit) ? Appearance.fgStrong : Appearance.fg
                        font.bold: knownRow.modelData.active
                        font.pixelSize: Theme.fontNormal
                        font.family: Theme.font
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                    }
                    Text {
                        text: knownRow.modelData.active ? "Connected"
                            : knownRow.modelData.signal + "%"
                        color: knownRow.modelData.active ? Appearance.green
                            : knownRow.lit ? Appearance.fgSoft : Appearance.fgFaint
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.font
                        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                    }
                }

                HoverHandler { id: knownHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: knownRow.joinable
                    onClicked: Network.connectTo(knownRow.modelData.ssid)
                }
            }
        }

        ListScrollBar {
            view: knownList
            Layout.fillHeight: true
            trackColor: Appearance.scrollTrack
            thumbColor: Appearance.scrollThumb
        }
    }

    // As above — the rule is gone, its 1px stays. Still
    // bound to knownCount, so with no known networks the gap
    // collapses along with the list and its header rather
    // than leaving a hole above "Other networks".
    Item {
        Layout.fillWidth: true
        implicitHeight: 1
        visible: Network.knownCount > 0
    }

    // ── Other networks ───────────────────────────
    // "Other" and not "Available" (user request 2026-09-17):
    // everything in this list is available, but so is every
    // row of the known list above it, and the only thing that
    // tells the two apart is which side of that line a
    // network falls on.
    Text {
        // Capitals and tracking as the known-networks
        // header above — the two are a pair, and one of
        // them in caps would read as a different kind of
        // heading rather than the same one twice.
        text: "Other networks"
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

    // The list is what the rail's height is FOR — everything
    // else in this tab is fixed or capped, so a taller screen
    // turns straight into more APs on screen rather than more
    // empty card. Which is also why halving the card
    // (2026-09-18) came almost entirely out of here: this is
    // the only part of the tab with height to give up.
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 4

        // The ListView is wrapped rather than placed in the
        // RowLayout directly so the empty-state line below has
        // somewhere to hang. A Flickable re-parents its visual
        // children into `contentItem`, so a placeholder declared
        // inside the view would centre itself on the scrolling
        // content — which is zero-height in exactly the case the
        // placeholder exists for.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: apList

                anchors.fill: parent
                clip: true
                // The scan minus what the known list above
                // is already showing — see
                // Network.unsavedNetworks. What is left is
                // the networks this machine has never been on,
                // which is the only thing this half of the tab
                // can tell you that the other half can't.
                model: Network.unsavedNetworks
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: apRow
                    required property var modelData

                    // Lit exactly as a known row is — see
                    // the delegate above for why the tint
                    // alone wasn't carrying it. Nothing here
                    // is the connected network (that one is
                    // known by definition, so it is in the
                    // list above), so there is no unclickable
                    // row to hold the hover back from.
                    readonly property bool lit: apHover.hovered

                    width: apList.width
                    height: 36
                    radius: Theme.radius
                    color: apRow.lit ? Appearance.hoverStrong : Appearance.clear(Appearance.hoverStrong)

                    Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: "\uf1eb"
                            color: apRow.modelData.active ? Appearance.green
                                : apRow.lit ? Appearance.fg : Appearance.fgFaint
                            font.pixelSize: Theme.fontNormal
                            font.family: Theme.font
                            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                        }
                        Text {
                            text: apRow.modelData.ssid
                            color: (apRow.modelData.active || apRow.lit) ? Appearance.fgStrong : Appearance.fg
                            font.bold: apRow.modelData.active
                            font.pixelSize: Theme.fontNormal
                            font.family: Theme.font
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                        }
                        Text {
                            text: apRow.modelData.signal + "%"
                            color: apRow.lit ? Appearance.fgSoft : Appearance.fgFaint
                            font.pixelSize: Theme.fontSmall
                            font.family: Theme.font
                            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                        }
                    }

                    HoverHandler { id: apHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: !apRow.modelData.active
                        onClicked: Network.connectTo(apRow.modelData.ssid)
                    }
                }

            }

            // Wi-Fi off, no adapter, or nothing heard yet — an empty
            // rail with no explanation reads as a broken panel.
            //
            // "Nothing else in range" is the fourth case and
            // the new one: the scan heard something, the known
            // list above took all of it, and this half is
            // empty because everything around you is already
            // yours. Saying "No networks found" there would be
            // a working adapter calling itself broken.
            Text {
                anchors.centerIn: parent
                width: parent.width - 16
                visible: apList.count === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: AirplaneMode.enabled ? "Radios are off"
                    : Network.scanning ? "Scanning…"
                    : Network.availableCount > 0 ? "Nothing else in range"
                    : "No networks found"
                color: Appearance.fgFaint
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
            }
        }

        ListScrollBar {
            view: apList
            Layout.fillHeight: true
            trackColor: Appearance.scrollTrack
            thumbColor: Appearance.scrollThumb
        }
    }
}
