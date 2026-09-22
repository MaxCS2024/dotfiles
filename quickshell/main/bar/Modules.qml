pragma Singleton
import QtQuick

// name -> Component registry driving Bar.qml's Repeaters (see
// Settings.barLayout). Adding a module means one Component property here
// plus one registry entry — Bar.qml itself never changes.
//
// Every bar item takes zero required external context except
// `barWindow` (dropdown anchoring) and, uniquely, Workspaces' `screen`.
// Both are plain (non-required) properties on the item types themselves,
// so Bar.qml's Loader sets them post-load via a `"prop" in item` check
// rather than this registry having to know which modules want what.
QtObject {
    id: root

    readonly property var registry: ({
        "workspaces": workspacesComponent,
        "activeWindow": activeWindowComponent,
        "media": mediaComponent,
        "clock": clockComponent,
        "launcher": launcherComponent,
        "clipboard": clipboardComponent,
        "network": networkComponent,
        "bluetooth": bluetoothComponent,
        "brightness": brightnessComponent,
        "volume": volumeComponent,
        "battery": batteryComponent,
        "tray": trayComponent,
        "sysmon": sysmonComponent,
        "notifications": notificationsComponent
    })

    readonly property Component workspacesComponent: Component { Workspaces {} }
    readonly property Component activeWindowComponent: Component { ActiveWindow {} }
    readonly property Component mediaComponent: Component { MediaPlayer {} }
    readonly property Component clockComponent: Component { Clock {} }
    readonly property Component launcherComponent: Component { LauncherButton {} }
    readonly property Component clipboardComponent: Component { ClipboardButton {} }
    readonly property Component networkComponent: Component { NetworkButton {} }
    readonly property Component bluetoothComponent: Component { BluetoothButton {} }
    readonly property Component brightnessComponent: Component { BrightnessButton {} }
    readonly property Component volumeComponent: Component { VolumeButton {} }
    readonly property Component batteryComponent: Component { BatteryButton {} }
    readonly property Component trayComponent: Component { SystemTray {} }
    readonly property Component sysmonComponent: Component { SystemMonitorButton {} }
    readonly property Component notificationsComponent: Component { NotificationsButton {} }
}
