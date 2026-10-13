pragma Singleton
import Quickshell
import QtQuick

// Stands in for services/Settings.qml: same two lookups Bar.qml calls,
// none of the settings.json persistence, so the test can't write to the
// real saved layout.
Singleton {
    id: root

    property bool stayAwake: false
    property var barConfig: ({ enabled: true, position: "top", floating: false, height: 0 })
    property var barLayout: ({ left: [], center: [], right: [] })

    function barConfigFor(monitorName) { return root.barConfig }
    function barLayoutFor(monitorName) { return root.barLayout }
}
