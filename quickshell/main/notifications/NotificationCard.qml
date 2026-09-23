// Notification card.
//
// Renders a plain-data row (services/Notifications.qml), never a live
// Notification object. That's what lets the same component draw a toast whose
// sender is still running, a toast restored from disk after a shell restart,
// and a history entry whose notification closed days ago — the row is just
// data in all three cases.
//
// Live libnotify action buttons are the one thing that needs the sender: they
// come from Notifications.actionsFor(row), which returns [] once it's gone.
import Quickshell
import QtQuick
import QtQuick.Layouts
import "../common"
import "../config"
import "../services"
import "../theme"

Item {
    id: root

    // A popup or history row: { summary, body, appName, appIcon, image,
    // glyph, execArgv, urgency, restored, ... }
    required property var row

    // Countdown remaining, 1.0 down to 0.0. Negative hides the bar entirely,
    // which is what a critical toast, a "until dismissed" one, and every
    // history row want.
    property real progress: -1

    readonly property bool hovered: cardHover.hovered

    implicitHeight: box.implicitHeight

    readonly property bool _critical: root.row.urgency === "critical"

    readonly property color _accent: {
        if (root._critical) return Appearance.red
        if (root.row.urgency === "low") return Appearance.fgDim
        return Appearance.icon
    }

    // Accent at an arbitrary alpha. Every tinted surface below is derived
    // from the urgency accent rather than from a fixed token, so a critical
    // card reads red throughout — border, glyph, action hover, wash —
    // instead of being one red sliver bolted onto a neutral card.
    function _tint(a) {
        return Qt.rgba(root._accent.r, root._accent.g, root._accent.b, a)
    }

    readonly property string _iconSource: {
        const image = root.row.image || ""
        if (image !== "") {
            return (image.startsWith("/") || image.includes("://"))
                ? image : Quickshell.iconPath(image, true)
        }
        const appIcon = root.row.appIcon || ""
        if (appIcon !== "") return Quickshell.iconPath(appIcon, true)
        return ""
    }

    // The summary is the headline; the app name is the small line at the
    // foot of the card. When a sender gives no summary the app name is
    // promoted into the headline slot and the footer goes away entirely, so
    // the two never say the same thing twice.
    readonly property string _title: root.row.summary || root.row.appName || ""
    readonly property string _source: (root.row.summary || "") !== ""
        ? (root.row.appName || "") : ""

    readonly property string _glyph: root.row.glyph || ""
    readonly property var _actions: Notifications.actionsFor(root.row)
    readonly property bool _activatable: Notifications.isActivatable(root.row)

    HoverHandler { id: cardHover }

    Rectangle {
        id: box
        width: parent.width
        // The countdown is deliberately NOT in this sum: it's a 2px overlay
        // sitting in the bottom padding. Counting it would make every card
        // change height the moment a hover paused it.
        implicitHeight: content.implicitHeight + 24
        radius: Theme.radius
        color: root.hovered ? Appearance.hover : Appearance.surface
        // 2px to match Hyprland's `border_size` (hypr/modules/decorations.lua):
        // a toast is framed like a window rather than reading as a
        // lighter-weight thing floating over them. The countdown at the foot
        // insets itself by this rather than assuming the number.
        border.width: 2
        // Critical earns a coloured edge; everything else brightens its
        // border on hover only, which is enough to say "this one is live"
        // without turning a stack of toasts into a stack of outlines.
        //
        // The critical edge is the accent softened *against the card's own
        // surface*, not an alpha left on the accent. A translucent border
        // composites against whatever happens to be behind the window, so
        // the Hyprland window border showed straight through it and the
        // edge went muddy wherever it crossed one. Qt.tint bakes the same
        // softening in at author time and leaves an opaque colour, which is
        // what the 0.55 was always meant to look like — the softening
        // belongs against the card's material, not against the desktop.
        //
        // Non-critical cards paint their edge with the Hyprland gradient
        // below instead, which covers this 2px band entirely — the colour
        // here is what shows if that frame is ever hidden.
        border.color: root._critical ? Qt.tint(Appearance.surface, root._tint(0.55))
            : (root.hovered ? Appearance.separator : Appearance.border)
        clip: true

        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
        Behavior on border.color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

        layer.enabled: true
        layer.effect: PopupShadow {}
        // The Hyprland window border, drawn around this card — see
        // common/HyprFrame.qml, which is where this construction now
        // lives; the Conf menu and the settings panel wear the same one.
        // Declared first so every other child still paints on top of it.
        //
        // Critical keeps its own coloured edge: that border is the urgency
        // signal, and a uniform frame across every card would erase it.
        HyprFrame {
            visible: !root._critical
            frameWidth: box.border.width
            targetRadius: box.radius
        }

        // Critical wash. Faint on purpose — it has to survive being drawn
        // over any matugen surface tone, light or dark.
        Rectangle {
            anchors.fill: parent
            color: root._tint(0.07)
            visible: root._critical
        }

        // Clicking the card body runs the row's action — a relay --exec
        // vector, or the sender's "default" action. Sits behind the close
        // button and the action buttons, which have their own MouseAreas.
        MouseArea {
            anchors.fill: parent
            enabled: root._activatable
            cursorShape: root._activatable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: Notifications.activate(root.row)
        }

        RowLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.space3
            anchors.rightMargin: Theme.space3
            spacing: Theme.space3

            // Icon well, centred against the whole message rather than
            // pinned to its first line: the glyph is now the card's mark,
            // and a mark that big hanging off the top of a three-line body
            // reads as a stray character instead of as the card's face.
            //
            // No plate behind it either. The tinted square existed to give
            // a 13px glyph enough presence to hold the slot; at this size
            // the glyph holds it unaided, and the square only boxed in
            // something that reads better free-standing.
            Item {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                Layout.alignment: Qt.AlignVCenter

                Image {
                    id: iconImg
                    // Centred at its own size rather than filling the well:
                    // the well grew for the glyph, and a real app icon
                    // scaled up with it would just render soft.
                    anchors.centerIn: parent
                    width: 36
                    height: 36
                    source: root._iconSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    // Icon themes hand back 128px+ art (or scalable SVG) for
                    // a 36px slot; without these it renders soft.
                    sourceSize.width: 36
                    sourceSize.height: 36
                    mipmap: true
                    visible: status === Image.Ready
                }

                // Icon fallback chain: real icon, then the sender's
                // --glyph, then a bell. The glyph is how
                // `relay notif send -g 󰏘` gets an identity without smuggling
                // the character into the summary text.
                //
                // The bell is fa-bell, the same one the bar's notification
                // button wears, so a card with no icon reads as the same
                // kind of object as the tray it came from. It replaced a
                // monogram of the app's first letter, which had to carry
                // meaning it never had: the app name is already printed an
                // inch to the right, and with themed icon NAMES currently
                // unresolvable most senders land in this branch — a column
                // of lone capitals is noise, where a column of bells is
                // simply the default face of a notification.
                Text {
                    anchors.centerIn: parent
                    visible: iconImg.status !== Image.Ready
                    text: root._glyph !== "" ? root._glyph : "\uf0f3"
                    color: root._accent
                    font.pixelSize: Theme.fontHuge
                    font.family: Theme.font
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: Theme.space1

                // Headline row. The close button rides along with it: the
                // headline is the one line every card is guaranteed to
                // have, so anchoring the button to it keeps the target in
                // the same place whether or not there is a body, an action
                // row, or a source line below.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2

                    Text {
                        visible: root._title !== ""
                        text: root._title
                        color: Appearance.fgStrong
                        font.bold: true
                        // fontMedium -> fontLarge, and the body under it
                        // fontSmall -> fontMedium (user request
                        // 2026-09-18). A toast is read at a glance from
                        // whatever distance you happen to be sitting at,
                        // and the card has the room: the body still
                        // wraps to at most four lines and elides past
                        // that, so a long message cannot push the card
                        // any taller than it could before.
                        //
                        // The source line and the action buttons keep
                        // their sizes: they are the card's furniture
                        // rather than its message, and growing them would
                        // just make the whole card bigger without making
                        // it any easier to read. (The icon glyph grew too,
                        // separately — see the icon well above.)
                        font.pixelSize: Theme.fontLarge
                        font.family: Theme.font
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: closeBtn
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        Layout.alignment: Qt.AlignVCenter
                        radius: height / 2
                        color: closeHover.hovered ? Appearance.hoverStrong : Qt.rgba(Appearance.hoverStrong.r, Appearance.hoverStrong.g, Appearance.hoverStrong.b, 0)
                        // Present but recessive until the pointer is on the
                        // card: always hit-testable (a toast has to be
                        // dismissable on the first try), never competing
                        // with the text for attention when it isn't.
                        opacity: root.hovered ? 1 : 0.35

                        Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                        Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00d"
                            color: closeHover.hovered ? Appearance.fgStrong : Appearance.fgDim
                            font.pixelSize: Theme.fontTiny
                            font.family: Theme.font

                            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                        }

                        HoverHandler { id: closeHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifications.dismiss(root.row)
                        }
                    }
                }

                Text {
                    visible: (root.row.body || "") !== ""
                    text: root.row.body || ""
                    textFormat: Text.PlainText
                    color: Appearance.fgSoft
                    font.pixelSize: Theme.fontMedium
                    font.family: Theme.font
                    lineHeight: 1.25
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.topMargin: 1
                    maximumLineCount: 4
                    elide: Text.ElideRight
                }

                RowLayout {
                    visible: root._actions.length > 0
                    Layout.topMargin: Theme.space2
                    spacing: Theme.space2

                    Repeater {
                        model: root._actions

                        delegate: Rectangle {
                            id: actionBtn
                            required property var modelData

                            implicitWidth: actionLabel.implicitWidth + 20
                            implicitHeight: 28
                            radius: Theme.radius
                            color: actionHover.hovered ? root._tint(0.18) : Appearance.surfaceAlt
                            border.width: 1
                            border.color: actionHover.hovered ? root._tint(0.45) : Appearance.border

                            Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                            Behavior on border.color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }

                            Text {
                                id: actionLabel
                                anchors.centerIn: parent
                                text: actionBtn.modelData.text
                                color: actionHover.hovered ? Appearance.fgStrong : Appearance.fg
                                font.pixelSize: Theme.fontSmall
                                font.family: Theme.font

                                Behavior on color { ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard } }
                            }

                            HoverHandler { id: actionHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Notifications.invokeAction(root.row, actionBtn.modelData)
                            }
                        }
                    }
                }

                // Where it came from, at the foot of the card. Hidden
                // outright when a sender gave no summary: the app name has
                // been promoted into the headline in that case, and a
                // footer would print it a second time.
                Text {
                    visible: root._source !== ""
                    text: root._source
                    color: Appearance.fgDim
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.font
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.topMargin: Theme.space1
                    elide: Text.ElideRight
                }
            }
        }

        // Countdown. Fades rather than vanishes, so pausing on hover reads
        // as a pause instead of a glitch.
        Rectangle {
            id: countdown
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            // Inside the frame, not on it. Children draw over the Rectangle's
            // own border, so a 2px bar lying on a 2px bottom border would read
            // as the frame draining rather than as a timer under the text.
            anchors.leftMargin: box.border.width
            anchors.rightMargin: box.border.width
            anchors.bottomMargin: box.border.width
            height: 2
            color: "transparent"
            opacity: root.progress >= 0 ? 1 : 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Theme.easingStandard } }

            // Latched, not bound straight to `progress`: a hovered card
            // reports -1, and a bar bound to that would race to empty on the
            // way out — animating exactly the drain the pause is meant to
            // stop. Freezing the last real value leaves it where it stood.
            property real shownFraction: 0
            Connections {
                target: root
                function onProgressChanged() {
                    if (root.progress >= 0)
                        countdown.shownFraction = Math.max(0, Math.min(1, root.progress))
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * countdown.shownFraction
                color: root._accent
                // Kept faint: normal urgency's accent is near-white, and a
                // full-strength 2px rule across the foot of every card reads
                // as a divider between toasts rather than as a timer.
                opacity: 0.5

                // Matches the driving Timer's 50ms tick exactly, which turns
                // a 20-step-per-second staircase into a continuous slide.
                Behavior on width { NumberAnimation { duration: 50; easing.type: Easing.Linear } }
            }
        }
    }
}
