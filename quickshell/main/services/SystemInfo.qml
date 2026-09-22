pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// One answer to "what machine is this", for every view in this shell that
// asks the question.
//
// There were three live copies of the same `whoami; hostname; . /etc/
// os-release; uname -r; uptime -p; free -h | awk …; df -h / | awk …`
// block — quicksettings/DashboardTab.qml, systemsettings/
// SettingsSystemTab.qml (a port of the first) and menu/MenuInfoView.qml
// (the same facts again, gathered differently and formatted for a
// label/value list) — plus a fourth partial one reading procfs in
// dashboard/DashboardVitals.qml. Four places to edit to fix one wrong
// field, and they had already diverged on which facts they carried.
// Three of those four have since been deleted with the panels that held
// them; MenuInfoView.qml is the reader this is written for.
//
// Split by how often an answer can actually change:
//
//   * kernel and host come from procfs through FileView — no process at
//     all, the same way DashboardVitals.qml already read them.
//   * the rest of the fixed facts (user, distro, CPU, session, and the
//     Hyprland and Quickshell versions) are one shell call, run once per
//     shell run, because none of them can change under a running shell.
//   * uptime, memory, disk and the package count do move, so they are
//     their own call and re-run on refresh() — which is what a view calls
//     when it becomes visible, exactly as the two tabs did before.
//
// Nothing here runs at startup: this is a Singleton, so it isn't built
// until the first view that reads it exists, and every window that does
// is behind a LazyLoader.
Singleton {
    id: root

    // ── Fixed for the life of this shell ─────────────────
    property string username: ""
    property string osName: ""
    property string cpu: ""
    property string session: ""
    property string hyprland: ""
    property string quickshell: ""
    // False until the one-shot call above has answered, so a view can
    // hold off drawing a screenful of em-dashes for its first frame.
    property bool ready: false

    property string kernel: ""
    property string hostname: ""

    // ── Moves while the shell runs ───────────────────────
    property string uptime: ""       // "up 1 hour, 5 minutes", as `uptime -p` gives it
    property string memUsed: ""
    property string memTotal: ""
    property string diskUsed: ""
    property string diskTotal: ""
    property string diskPercent: ""
    property string packages: ""

    // Every line is wrapped in its own printf so a command that prints
    // nothing still costs exactly one line — otherwise a missing answer
    // (no jq, no hyprctl) would shift every field after it.
    readonly property string _fixedScript: [
        'printf "%s\\n" "$(whoami)"',
        'printf "%s\\n" "$(. /etc/os-release 2>/dev/null; printf "%s" "${PRETTY_NAME:-unknown}")"',
        'printf "%s\\n" "$(sed -n "s/^model name[[:space:]]*: //p" /proc/cpuinfo | head -1 | sed "s/(R)//g; s/(TM)//g; s/ CPU//; s/  */ /g")"',
        'printf "%s · %s\\n" "${XDG_SESSION_TYPE:-?}" "${XDG_CURRENT_DESKTOP:-?}"',
        'printf "%s\\n" "$(hyprctl version -j 2>/dev/null | jq -r ".tag // empty" 2>/dev/null)"',
        'printf "%s\\n" "$(qs --version 2>&1 | head -1 | sed "s/^Quickshell //; s/ (.*//")"'
    ].join("\n")

    readonly property string _liveScript: [
        'printf "%s\\n" "$(uptime -p 2>/dev/null || uptime)"',
        'printf "%s\\n" "$(free -h | awk \'/^Mem:/ {print $3"|"$2}\')"',
        'printf "%s\\n" "$(df -h / | awk \'NR==2 {print $3"|"$2"|"$5}\')"',
        'printf "%s\\n" "$(pacman -Qq 2>/dev/null | wc -l)"'
    ].join("\n")

    readonly property Process fixedProc: Process {
        command: ["sh", "-c", root._fixedScript]
        stdout: StdioCollector {
            id: fixedOut
            onStreamFinished: {
                const l = fixedOut.text.split("\n")
                root.username = l[0] || ""
                root.osName = l[1] || ""
                root.cpu = l[2] || ""
                root.session = l[3] || ""
                root.hyprland = l[4] || ""
                root.quickshell = l[5] || ""
                root.ready = true
            }
        }
    }

    readonly property Process liveProc: Process {
        command: ["sh", "-c", root._liveScript]
        stdout: StdioCollector {
            id: liveOut
            onStreamFinished: {
                const l = liveOut.text.split("\n")
                root.uptime = l[0] || ""

                const mem = (l[1] || "").split("|")
                root.memUsed = mem[0] || ""
                root.memTotal = mem[1] || ""

                const disk = (l[2] || "").split("|")
                root.diskUsed = disk[0] || ""
                root.diskTotal = disk[1] || ""
                root.diskPercent = disk[2] || ""

                root.packages = l[3] || ""
            }
        }
    }

    readonly property FileView kernelFile: FileView {
        // /proc/sys/kernel/osrelease rather than shelling out to
        // `uname -r`: same string, no process spawn.
        path: "/proc/sys/kernel/osrelease"
        printErrors: false
        onLoaded: root.kernel = kernelFile.text().trim()
    }

    readonly property FileView hostnameFile: FileView {
        path: "/etc/hostname"
        printErrors: false
        onLoaded: root.hostname = hostnameFile.text().trim().split("\n")[0]
    }

    // What a view calls when it becomes visible. The fixed half is only
    // ever fetched once, however often this is called.
    function refresh() {
        if (!root.ready) {
            root.fixedProc.running = false
            root.fixedProc.running = true
        }
        root.liveProc.running = false
        root.liveProc.running = true
    }

    // Convenience for the two tabs that print these as one string each.
    readonly property string memory: root.memUsed !== "" && root.memTotal !== ""
        ? root.memUsed + " / " + root.memTotal : ""
    readonly property string disk: root.diskUsed !== "" && root.diskTotal !== ""
        ? root.diskUsed + " / " + root.diskTotal + " (" + root.diskPercent + ")" : ""
}
