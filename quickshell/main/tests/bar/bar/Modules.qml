pragma Singleton
import QtQuick

// Two kinds of module, which is all the distinction Bar.qml draws:
// one that opts into keyboard nav (declares keyboardFocused, like
// BarButton) and one that doesn't (like Workspaces or SystemTray).
QtObject {
    readonly property var registry: ({
        "button": buttonComponent,
        "widget": widgetComponent
    })

    readonly property Component buttonComponent: Component { FakeButton {} }
    readonly property Component widgetComponent: Component { FakeWidget {} }
}
