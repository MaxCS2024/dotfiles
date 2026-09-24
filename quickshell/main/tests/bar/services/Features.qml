pragma Singleton
import Quickshell
import QtQuick

// Stands in for services/Features.qml: the one lookup Bar.qml makes, with
// the features that are off set by the test instead of read from
// ~/.config/rack/features.conf.
Singleton {
    id: root

    property var off: []

    function on(name) { return !root.off.includes(name) }
}
