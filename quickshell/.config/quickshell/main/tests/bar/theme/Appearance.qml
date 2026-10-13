pragma Singleton
import Quickshell
import QtQuick

Singleton {
    // Transparent so a shown test bar paints nothing over the real one.
    readonly property color bar: "transparent"
}
