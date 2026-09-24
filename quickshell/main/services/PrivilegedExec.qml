pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Runs a single non-interactive privileged command via `sudo -S`, fed a
// password collected from PasswordPrompt.qml rather than depending on
// pkexec's separate polkit authentication agent, which may not be
// installed/themed, or on shelling out to a terminal just to type a
// password once.
//
// Only suited to single-shot, non-interactive commands (pass
// --noconfirm/-y as appropriate to whatever you're running). Anything
// that needs multiple prompts, package-manager confirmation dialogs, or
// other interactivity — e.g. AUR installs via yay, which want to show a
// PKGBUILD diff — should still go through a real terminal instead.
//
// Single in-flight command at a time: starting a new run() while one is
// already active abandons tracking of the previous one's callbacks.
// services/Packages.qml, the one caller, queues its commands for that
// reason — two windows each calling this directly used to lose the first
// one's answer.
Singleton {
    id: root

    property var _onSuccess: null
    property var _onFailure: null   // function(message)
    property string _stderrBuf: ""
    property string _pendingPassword: ""

    function run(commandArgs, password, onSuccess, onFailure) {
        root._onSuccess = onSuccess
        root._onFailure = onFailure || null
        root._stderrBuf = ""
        root._pendingPassword = password

        // -p '' suppresses sudo's own "[sudo] password for user:" prompt
        // text from stderr, keeping the captured output clean.
        proc.command = ["sudo", "-S", "-p", ""].concat(commandArgs)
        proc.running = false
        proc.running = true

        // Writing to stdin in the same tick as setting running=true is
        // not reliable — Process.running becoming true does not
        // guarantee the underlying OS process has actually forked/exec'd
        // and opened its stdin read loop yet. Without this delay, sudo
        // can find stdin already at EOF by the time it gets around to
        // reading it, and reports "sudo: a password is required" even
        // though a correct password was in fact supplied. A short delay
        // before writing gives the process time to actually be ready.
        writeDelay.restart()
    }

    Timer {
        id: writeDelay
        interval: 100
        onTriggered: proc.write(root._pendingPassword + "\n")
    }

    Process {
        id: proc
        stdinEnabled: true

        stderr: SplitParser {
            onRead: (line) => root._stderrBuf += line + "\n"
        }

        // exitCode/exitStatus arrive as parameters on this signal —
        // there is no proc.exitCode property to read afterward.
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                if (root._onSuccess) root._onSuccess()
            } else {
                let message = "Command failed (exit " + exitCode + ")"
                if (root._stderrBuf.includes("ncorrect")) {
                    message = "Incorrect password"
                } else if (root._stderrBuf.includes("a password is required")
                        || root._stderrBuf.includes("no password was provided")) {
                    message = "No password entered"
                } else {
                    // Surface the command's own error text instead of a
                    // bare exit code where possible.
                    const trimmed = root._stderrBuf.trim()
                    if (trimmed.length > 0) {
                        const lastLines = trimmed.split("\n").slice(-3).join(" ")
                        message = lastLines.length > 220 ? lastLines.slice(0, 220) + "…" : lastLines
                    }
                }
                if (root._onFailure) root._onFailure(message)
            }
        }
    }
}
