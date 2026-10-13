import QtQuick

// Draws an activity with the face it names (`face`): "osd" for the OSD's
// level, "media" for the player, "" for the generic icon and label.
Loader {
    id: face

    property var activity: null
    // "compact", "transient" or "expanded".
    property string mode: "compact"

    sourceComponent: activity?.face === "osd" ? osdFace
        : activity?.face === "media" ? mediaFace
        : genericFace

    Component {
        id: genericFace
        ActivityFace { activity: face.activity; mode: face.mode }
    }

    Component {
        id: mediaFace
        MediaFace { activity: face.activity; mode: face.mode }
    }

    Component {
        id: osdFace
        OsdFace { activity: face.activity; mode: face.mode }
    }
}
