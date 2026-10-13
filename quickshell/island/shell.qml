import Quickshell
import QtQuick

// The island, on the focused monitor only. The design brief is AGENTS.md.
Scope {
    // Features are singletons, which load on first use; naming them here
    // starts them. Each checks its own Config switch.
    readonly property var osd: Osd
    readonly property var media: Media

    Island {}
}
