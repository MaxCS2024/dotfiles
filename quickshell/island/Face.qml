import QtQuick

// Draws an activity with the face it names (`face`): "osd" for the OSD's
// level, "media" for the player, "notification" for a notification,
// "hold" for the hold mode's count, "" for the generic icon and label.
Loader {
    id: face

    property var activity: null
    // "compact", "transient" or "expanded".
    property string mode: "compact"

    sourceComponent: activity?.face === "osd" ? osdFace
        : activity?.face === "media" ? mediaFace
        : activity?.face === "notification" ? notificationFace
        : activity?.face === "hold" ? holdFace
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
        id: notificationFace
        NotificationFace { activity: face.activity; mode: face.mode }
    }

    Component {
        id: holdFace
        HoldFace { activity: face.activity; mode: face.mode }
    }

    Component {
        id: osdFace
        OsdFace { activity: face.activity; mode: face.mode }
    }
}
