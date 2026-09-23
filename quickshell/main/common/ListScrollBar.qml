import QtQuick
import "../config"
import "../theme"

// The scrollbar every scrolling list in this shell draws beside itself: a
// track that only appears once there is something to scroll, and a thumb
// whose position and length are the view's own contentY/contentHeight
// ratios. The launcher and the Conf menu had a copy each and had already
// drifted apart on width and corner radius, which is exactly the drift
// common/FocusRing.qml exists to prevent for focus rings.
//
// Geometry stays per-site (the menu's rail is thinner and square, the
// launcher's is wider and takes Theme.radius); it's the thumb arithmetic
// that is shared, because that is the part worth getting right once.
Rectangle {
    id: root

    // The ListView (or any Flickable) this bar scrolls.
    required property var view
    property int barWidth: 4
    property real barRadius: Theme.radius
    // Per-site for the same reason the geometry above is, plus one of
    // its own: theme/Appearance.qml isn't importable from here (this
    // file is symlinked into the old config, which has no theme/), so a
    // caller that follows a pinned palette passes its own two tones in
    // and everyone else keeps Theme's.
    property color trackColor: Appearance.scrollTrack
    property color thumbColor: Appearance.scrollThumb

    implicitWidth: root.barWidth
    radius: root.barRadius
    color: root.trackColor
    visible: root.view.contentHeight > root.view.height

    Rectangle {
        width: parent.width
        radius: root.barRadius
        color: root.thumbColor
        y: root.view.contentHeight > 0
            ? (root.view.contentY / root.view.contentHeight) * parent.height
            : 0
        height: root.view.contentHeight > 0
            ? Math.max(20, (root.view.height / root.view.contentHeight) * parent.height)
            : parent.height
    }
}
