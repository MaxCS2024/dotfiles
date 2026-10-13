import QtQuick

// Draws an activity with the face it names (`face`): "osd" for the OSD's
// level, "media" for the player, "workspace" for the workspace flash,
// "dictation" for voxtype's recording,
// "notification" for a notification,
// "hold" for the hold mode's count, "" for the generic icon and label.
Loader {
    id: face

    property var activity: null
    // "compact", "transient", "expanded" or "minimal" (the split's
    // circle).
    property string mode: "compact"

    sourceComponent: activity?.face === "osd" ? osdFace
        : activity?.face === "media" ? mediaFace
        : activity?.face === "workspace" ? workspaceFace
        : activity?.face === "dictation" ? dictationFace
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
        id: dictationFace
        DictationFace { activity: face.activity; mode: face.mode }
    }

    Component {
        id: workspaceFace
        WorkspaceFace { activity: face.activity; mode: face.mode }
    }

    Component {
        id: osdFace
        OsdFace { activity: face.activity; mode: face.mode }
    }
}
