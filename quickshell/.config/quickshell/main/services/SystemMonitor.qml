pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// CPU/GPU stats for SystemMonitorButton's dropdown. Polling is gated by a
// ref-counted viewer count (addViewer()/removeViewer()) rather than a
// plain bool, so it stays correct with more than one bar (multi-monitor)
// each carrying their own SystemMonitorButton dropdown.
Singleton {
    id: root

    property int _viewers: 0
    readonly property bool running: root._viewers > 0

    function addViewer() { root._viewers++ }
    function removeViewer() { root._viewers = Math.max(0, root._viewers - 1) }

    // ── CPU ──────────────────────────────────────────────
    property real cpuUsage: 0
    property real _prevIdle: -1
    property real _prevTotal: -1

    property string load1: "-"
    property string load5: "-"
    property string load15: "-"

    property string _cpuHwmonPath: ""
    property string cpuTemp: "-"

    // ── GPU: Intel discrete (Arc) via i915/xe hwmon sysfs ──
    property string _gpuHwmonPath: ""
    readonly property bool gpuAvailable: root._gpuHwmonPath !== ""
    property string gpuTemp: "-"
    property real gpuPower: -1
    property real _prevGpuEnergyUj: -1
    property real _prevGpuEnergyTime: -1

    Component.onCompleted: detectHwmonProc.running = true

    function refreshAll() {
        statFile.reload()
        loadFile.reload()
        if (root._cpuHwmonPath !== "") cpuTempFile.reload()
        if (root._gpuHwmonPath !== "") {
            gpuTempFile.reload()
            gpuEnergyFile.reload()
        }
    }

    Timer {
        interval: 2000
        running: root.running
        repeat: true
        onTriggered: root.refreshAll()
    }

    // Poll once immediately when a viewer appears, rather than waiting
    // up to 2s for the first update after opening the dropdown.
    onRunningChanged: if (root.running) root.refreshAll()

    // Resolves the CPU sensor chip and the discrete-GPU hwmon chip in one
    // pass at startup, so neither has to be rediscovered on every tick.
    // For the GPU, prefers the card that is NOT boot_vga — the discrete
    // one on most hybrid-graphics laptops — falling back to the last chip
    // found if boot_vga can't be read.
    Process {
        id: detectHwmonProc
        command: ["sh", "-c",
            "for hw in /sys/class/hwmon/hwmon*; do " +
            "  n=$(cat \"$hw/name\" 2>/dev/null); " +
            "  case \"$n\" in k10temp|coretemp|zenpower) echo \"cpu $hw\"; break;; esac; " +
            "done; " +
            "for hw in /sys/class/drm/card*/device/hwmon/hwmon*; do " +
            "  n=$(cat \"$hw/name\" 2>/dev/null); " +
            "  case \"$n\" in i915|xe) " +
            "    c=$(echo \"$hw\" | sed -n 's#.*/card\\([0-9]*\\)/.*#\\1#p'); " +
            "    b=$(cat \"/sys/class/drm/card$c/device/boot_vga\" 2>/dev/null); " +
            "    echo \"gpu $hw $b\"; " +
            "  ;; esac; " +
            "done"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.length > 0)
                let gpuCandidates = []

                for (const line of lines) {
                    const parts = line.trim().split(" ")
                    if (parts[0] === "cpu") root._cpuHwmonPath = parts[1]
                    else if (parts[0] === "gpu") gpuCandidates.push(parts)
                }

                let chosen = ""
                for (const g of gpuCandidates) {
                    if (g.length >= 3 && g[2] === "0") { chosen = g[1]; break }
                }
                if (chosen === "" && gpuCandidates.length > 0)
                    chosen = gpuCandidates[gpuCandidates.length - 1][1]

                root._gpuHwmonPath = chosen
                if (root.running) root.refreshAll()
            }
        }
    }

    FileView {
        id: statFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            const firstLine = text().split("\n")[0]
            const parts = firstLine.trim().split(/\s+/)
            if (parts.length < 8) return
            const vals = parts.slice(1).map(Number)
            const idle = vals[3] + vals[4]
            const total = vals.reduce((a, b) => a + b, 0)

            if (root._prevTotal >= 0) {
                const totalDelta = total - root._prevTotal
                const idleDelta = idle - root._prevIdle
                if (totalDelta > 0)
                    root.cpuUsage = Math.max(0, Math.min(100, 100 * (1 - idleDelta / totalDelta)))
            }
            root._prevIdle = idle
            root._prevTotal = total
        }
    }

    FileView {
        id: loadFile
        path: "/proc/loadavg"
        printErrors: false
        onLoaded: {
            const parts = text().trim().split(" ")
            if (parts.length < 3) return
            root.load1 = parts[0]
            root.load5 = parts[1]
            root.load15 = parts[2]
        }
    }

    FileView {
        id: cpuTempFile
        printErrors: false
        path: root._cpuHwmonPath !== "" ? root._cpuHwmonPath + "/temp1_input" : ""
        onLoaded: {
            const v = parseFloat(text().trim())
            root.cpuTemp = isNaN(v) ? "-" : (v / 1000).toFixed(1)
        }
    }

    FileView {
        id: gpuTempFile
        printErrors: false
        path: root._gpuHwmonPath !== "" ? root._gpuHwmonPath + "/temp1_input" : ""
        onLoaded: {
            const v = parseFloat(text().trim())
            root.gpuTemp = isNaN(v) ? "-" : (v / 1000).toFixed(1)
        }
    }

    FileView {
        id: gpuEnergyFile
        printErrors: false
        path: root._gpuHwmonPath !== "" ? root._gpuHwmonPath + "/energy1_input" : ""
        onLoaded: {
            const v = parseFloat(text().trim())
            if (isNaN(v)) { root.gpuPower = -1; return }
            const now = Date.now()
            if (root._prevGpuEnergyUj >= 0) {
                const dEnergy = v - root._prevGpuEnergyUj
                const dTime = (now - root._prevGpuEnergyTime) / 1000
                if (dTime > 0 && dEnergy >= 0)
                    root.gpuPower = dEnergy / dTime / 1000000
            }
            root._prevGpuEnergyUj = v
            root._prevGpuEnergyTime = now
        }
    }
}
