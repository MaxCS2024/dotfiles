import QtQuick
import QtQuick.Layouts
import "../config"
import "../theme"

Rectangle {
    id: root

    required property var entry   // plain history object from Notifications.history

    signal removeRequested()

    // Every row is the same height: one title line, one body line, one
    // app line. It used to be whatever the body came to — three lines for
    // a Spotify track, four for a disk warning that wrapped, two for a
    // notification with no body at all — and a list of one repeated shape
    // is read by scanning where a ragged one has to be parsed row by row
    // (user request 2026-09-18). The body is the only part that ever
    // varied; see the Text itself.
    implicitHeight: content.implicitHeight + 16

    // The body's line box, stated in metrics rather than left to whatever
    // an empty Text happens to measure — the point is that the row keeps
    // its third line whether the body is absent, one word, or a paragraph
    // elided down to fit.
    FontMetrics {
        id: bodyMetrics
        font.pixelSize: Theme.fontSmall
        font.family: Theme.font
    }
    radius: Theme.radius
    // A row is a surface of its own now, not text laid on the card behind
    // it (user request 2026-09-18). Transparent rows left nothing to say
    // where one notification ended and the next began except the gap
    // between them, and a gap does that only while the two either side of
    // it are short; a filled row says it whatever is in them.
    //
    // surfaceAlt is one elevation step over the `surface` every container
    // that draws these rows is painted in — the rail's card, the quick
    // settings panel, the dashboard's tiles — so the row lifts off its
    // background by the same amount everywhere without knowing which of
    // them it is in. Hover keeps its own step above that, so pointing at a
    // row still answers.
    //
    // Appearance rather than Theme for both, like every surface written
    // since the bento dashboard: it falls through to these same Theme
    // tokens by default and follows a pinned custom palette when there is
    // one, which is what the containers above do.
    color: rowHover.hovered ? Appearance.hover : Appearance.surfaceAlt

    // Worth having now that both ends of the hover are a visible fill; it
    // used to cross-fade out of "transparent", where a step read as fine
    // as a fade. Same duration and curve as every other row in this shell.
    Behavior on color {
        ColorAnimation { duration: Theme.animFast; easing.type: Theme.easingStandard }
    }

    function _timeAgo(ms) {
        const diff = Math.max(0, Date.now() - ms)
        const mins = Math.floor(diff / 60000)
        if (mins < 1) return "now"
        if (mins < 60) return mins + "m ago"
        const hours = Math.floor(mins / 60)
        if (hours < 24) return hours + "h ago"
        return Math.floor(hours / 24) + "d ago"
    }

    HoverHandler { id: rowHover }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 8
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 1

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: root.entry.summary || root.entry.appName
                    color: Theme.fg
                    font.bold: true
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.font
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }

                Text {
                    text: root._timeAgo(root.entry.time)
                    color: Theme.fgDim
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.font
                }
            }

            Text {
                // Whitespace collapsed rather than merely clamped: a body
                // that arrives with newlines in it (borg and pacman both
                // send them) would otherwise be cut at the first one, and
                // a single line of "18,432 files copied to /mnt/archive"
                // says more than the first half of one. maximumLineCount
                // still stands behind it, so nothing can push the row
                // taller than the metric above reserves.
                text: (root.entry.body || "").replace(/\s+/g, " ").trim()
                textFormat: Text.PlainText
                color: Theme.fgFaint
                font.pixelSize: Theme.fontSmall
                font.family: Theme.font
                elide: Text.ElideRight
                maximumLineCount: 1
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredHeight: bodyMetrics.height
            }

            Text {
                text: root.entry.appName
                color: Theme.fgDim
                font.pixelSize: Theme.fontTiny
                font.family: Theme.font
            }
        }

        Text {
            text: "\uf00d"
            color: Theme.fgDim
            font.pixelSize: Theme.fontSmall
            font.family: Theme.font
            visible: rowHover.hovered
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: root.removeRequested()
            }
        }
    }
}
