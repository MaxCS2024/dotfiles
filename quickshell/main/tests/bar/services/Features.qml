pragma Singleton
import Quickshell
import QtQuick

// Stands in for services/Features.qml: the lookup Bar.qml makes, with
// the features that are off set by the test instead of read from
// ~/.config/rack/features.conf.
Singleton {
    id: root

    property var off: []

    function on(name) { return !root.off.includes(name) }

    // The widget belongs to a feature, so the test can turn it off.
    readonly property var _owners: ({ "widget": "fakefeature" })

    function allows(name) { return root.on(root._owners[name] || "") }
}
