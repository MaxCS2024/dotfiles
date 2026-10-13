pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The system problems that need the user (AGENTS.md, Notifications):
// regular notifications through dunst, critical, so they stay until
// dismissed, and taken back once the problem is gone.
// - "Battery critical – 4%" when Controls fires its "critical" battery
//   notice (below 5% on battery), which the pill flashes too, the one
//   event shown in both places. Plugging in closes it.
// - "Disk almost full – 2.1 GB left on /" when a filesystem has less
//   than 5 GB and less than 10% free, checked a minute after start and
//   then every 10 minutes. Once per crossing: it warns again only after
//   the space has come back (6 GB or 12% free), which also closes it.
Singleton {
    id: root

    // Notification ids by what they are about ("battery", or a mount
    // point), so a newer reading replaces the open one and recovery
    // closes it.
    property var ids: ({})

    function notify(key, args) {
        const id = ids[key]
        const proc = sender.createObject(root, {
            key: key,
            command: ["notify-send", "-p", "-u", "critical"]
                .concat(id ? ["-r", String(id)] : [])
                .concat(args)
        })
        proc.running = true
    }

    function close(key) {
        const id = ids[key]
        if (!id)
            return
        const next = Object.assign({}, ids)
        delete next[key]
        ids = next
        Quickshell.execDetached(["busctl", "--user", "call", "org.freedesktop.Notifications",
            "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
            "CloseNotification", "u", String(id)])
    }

    // One notify-send per notification, kept until it prints the id.
    Component {
        id: sender
        Process {
            id: proc
            property string key
            stdout: StdioCollector {
                onStreamFinished: {
                    const id = parseInt(text.trim())
                    if (id > 0)
                        root.ids = Object.assign({}, root.ids, { [proc.key]: id })
                }
            }
            // Once the id is read, which can come just after the exit.
            onExited: Qt.callLater(() => proc.destroy())
        }
    }

    // ── Battery ──
    Connections {
        target: Controls
        function onBatteryNotice(kind) {
            if (kind === "critical")
                root.notify("battery", ["-a", "Battery", "-i", "battery-caution",
                    "Battery critical – " + Math.round(Controls.batteryPercent) + "%", "Plug in now"])
            else if (kind === "charging")
                root.close("battery")
        }
    }

    // ── Disks ──
    readonly property real gb: 1e9
    // Mount points warned about and not recovered yet.
    property var diskWarned: ({})

    function amount(bytes) {
        return bytes >= gb ? (bytes / gb).toFixed(1) + " GB" : Math.round(bytes / 1e6) + " MB"
    }

    // One reading of one filesystem.
    function diskReading(mount, size, avail) {
        const warned = diskWarned[mount] === true
        if (!warned && avail < 5 * gb && avail < 0.1 * size) {
            diskWarned = Object.assign({}, diskWarned, { [mount]: true })
            notify(mount, ["-a", "Disk", "-i", "drive-harddisk",
                "Disk almost full", amount(avail) + " left on " + mount])
        } else if (warned && (avail >= 6 * gb || avail >= 0.12 * size)) {
            const next = Object.assign({}, diskWarned)
            delete next[mount]
            diskWarned = next
            close(mount)
        }
    }

    // Real filesystems only; the btrfs subvolumes (/, /home, …) share a
    // device and so their space, so each device is read once, at its
    // shortest mount point.
    Process {
        id: df
        command: ["df", "-B1", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs",
            "-x", "overlay", "-x", "squashfs", "--output=source,size,avail,target"]
        stdout: StdioCollector {
            onStreamFinished: {
                const byDevice = {}
                for (const line of text.trim().split("\n").slice(1)) {
                    const [source, size, avail, ...rest] = line.trim().split(/\s+/)
                    const mount = rest.join(" ")
                    if (!byDevice[source] || mount.length < byDevice[source].mount.length)
                        byDevice[source] = { mount: mount, size: Number(size), avail: Number(avail) }
                }
                for (const d of Object.values(byDevice))
                    root.diskReading(d.mount, d.size, d.avail)
            }
        }
    }

    Timer {
        interval: 60 * 1000
        running: true
        onTriggered: {
            df.running = true
            interval = 10 * 60 * 1000
            repeat = true
            restart()
        }
    }
}
