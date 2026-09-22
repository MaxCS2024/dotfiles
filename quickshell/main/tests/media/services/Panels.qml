pragma Singleton
import Quickshell
import QtQuick

// The two flags services/Media.qml reads to decide whether its position
// tick is worth running; the real Panels brings GlobalShortcuts that
// would fight main's.
Singleton {
    property bool barVisible: true
    property bool mediaShown: false
}
