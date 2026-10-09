pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The slice of main/config/Theme.qml the launcher draws with: the same
// values, copied rather than shared, because that file reads
// main/services/Settings.qml, which owns IPC targets and writes
// settings.json, and a second process doing either would fight the bar.
// The one value that follows a setting, the corner radius, is read from
// the bar's own settings.json and never written.
Singleton {
    id: root

    // The bar's data folder. Quickshell names one per config after the md5
    // of the path it was started with (`qs list` calls it the Shell ID), so
    // main's sits beside this config's own under the same parent.
    readonly property string mainDataDir: {
        const own = Quickshell.dataDir
        const parent = own.slice(0, own.lastIndexOf("/"))
        return parent + "/" + Qt.md5(Quickshell.env("HOME") + "/.config/quickshell/main/shell.qml")
    }

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSmall: 11
    readonly property int fontNormal: 12
    readonly property int fontBig: 14
    readonly property int iconSize: 16

    readonly property int hyprBorderWidth: 2

    readonly property int space2: 8

    // Settings.cornerRadius in the bar, 2 until its file says otherwise.
    property int radius: 2

    readonly property int animFast: 120
    readonly property int animPanel: 220
    readonly property int easingDecel: Easing.OutCubic
    readonly property int easingStandard: Easing.InOutQuad

    readonly property real shadowBlurPopup: 0.7
    readonly property real shadowVerticalOffsetPopup: 4

    FileView {
        path: root.mainDataDir + "/settings.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text())
                if (typeof data.cornerRadius === "number") root.radius = data.cornerRadius
            } catch (e) {}
        }
    }
}
