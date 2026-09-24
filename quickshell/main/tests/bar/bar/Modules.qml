pragma Singleton
import QtQuick

// One of each kind of module Bar.qml and BarModuleLoader tell apart:
// one that opts into keyboard nav (declares keyboardFocused, like
// BarButton), one that doesn't (like Workspaces or SystemTray), and one
// that gives up its slot when it has nothing to show (like MediaPlayer).
QtObject {
    // What the self-hiding module has to show; the test flips it.
    property bool selfHidingHasContent: false

    readonly property var registry: ({
        "button": buttonComponent,
        "widget": widgetComponent,
        "selfhiding": selfHidingComponent
    })

    // The widget belongs to a feature, so the test can turn it off.
    readonly property var feature: ({
        "widget": "fakefeature"
    })

    readonly property Component buttonComponent: Component { FakeButton {} }
    readonly property Component widgetComponent: Component { FakeWidget {} }
    readonly property Component selfHidingComponent: Component { FakeSelfHiding {} }
}
