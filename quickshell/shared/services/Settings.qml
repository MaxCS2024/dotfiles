pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The bar's settings, read-only, for the configs that run beside it
// (../launcher, ../clipboard). main/config/Theme.qml is symlinked into
// each of them as it is and finds this in place of
// main/services/Settings.qml, which owns IPC targets and writes
// settings.json: a second process doing either would fight the bar.
// Only what Theme reads is here.
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

    // main/services/Settings.qml's defaults, until the file says otherwise.
    property real barOpacity: 0.65
    property int cornerRadius: 2

    FileView {
        path: root.mainDataDir + "/settings.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text())
                if (typeof data.barOpacity === "number") root.barOpacity = data.barOpacity
                if (typeof data.cornerRadius === "number") root.cornerRadius = data.cornerRadius
            } catch (e) {}
        }
    }
}
