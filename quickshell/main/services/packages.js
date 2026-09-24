.pragma library

// How to change what is installed: for one package from one source, the
// command that installs or removes it, whether that needs root, whether it
// runs behind the window or in a terminal, and how to tell it landed.
//
// Plans only. Nothing here runs a process, which is what lets
// tests/packages check every rule without a session; services/Packages.qml
// is the one caller, and runs what this decides.
//
// An entry is { source, id, name, scope }:
//   source  "Pacman" (the official repositories), "AUR" or "Flatpak"
//   id      the package name, or the flatpak's application id
//   name    what to call it in a title, when that is not the id
//   scope   "user" or "system", for a flatpak already installed
//
// The rules, in the order they decide:
//
//   * An AUR install always goes to a terminal: yay shows the PKGBUILD and
//     asks about it, and none of that belongs behind a spinner. Removing
//     an AUR package is a plain `pacman -Rns`, like any other.
//   * Anything else that needs root runs behind the window, with a
//     password the window collects (`withPrompt`), through `sudo -S`. There
//     is no polkit agent in this session; services/PrivilegedExec.qml's
//     header has the rest.
//   * With no window to ask a password in -- the Conf menu, which runs a
//     row after it has closed -- root means a terminal and sudo in it.
//   * What needs no root runs behind the window either way.
//
// Flatpaks install to the system: flathub is registered system-wide here,
// and a --user install fails before it reaches the network. Removal
// follows the scope the flatpak is installed in, and a user one needs no
// root.

var SOURCES = ["Pacman", "AUR", "Flatpak"]

// What a package name or application id can look like. Checked because
// the id ends up in an argv and, on the terminal path, in a command line:
// a name that starts with a dash would be read as an option, and one with
// a quote or a space would be a second word. pacman's own rule for names
// is narrower than this; a flatpak id is reverse-DNS.
var ID = /^[A-Za-z0-9@_+][A-Za-z0-9@._+-]*$/

function quote(word) {
    return "'" + String(word).split("'").join("'\\''") + "'"
}

function line(argv) {
    return argv.map(quote).join(" ")
}

function label(entry) {
    return entry.name && entry.name !== "" ? entry.name : entry.id
}

// The command, without sudo in front: whoever runs it decides how root is
// had. `privileged` says whether it needs it.
function command(action, entry) {
    var id = entry.id
    var system = entry.scope !== "user"

    if (entry.source === "Flatpak") {
        if (action === "install")
            return { argv: ["flatpak", "install", "-y", "--system", "flathub", id], privileged: true }
        return { argv: ["flatpak", "uninstall", "-y", system ? "--system" : "--user", id],
                 privileged: system }
    }

    if (action === "install") {
        if (entry.source === "AUR")
            return { argv: ["yay", "-S", "--needed", id], privileged: false }
        return { argv: ["pacman", "-S", "--needed", "--noconfirm", id], privileged: true }
    }

    return { argv: ["pacman", "-Rns", "--noconfirm", id], privileged: true }
}

// Exits 0 while the package is installed, and non-zero once it is not.
// Asked of a terminal action, which reports nothing back, until it says
// what the action was for.
function check(action, entry) {
    if (entry.source === "Flatpak") {
        var scope = action === "install" || entry.scope !== "user" ? "--system" : "--user"
        return ["flatpak", "info", scope, entry.id]
    }
    return ["pacman", "-Q", entry.id]
}

// plan(action, entry, withPrompt) -> null for something that can't be
// planned (an unknown action or source, an id that isn't one), otherwise:
//
//   argv        the command to run behind the window (terminal: false)
//   privileged  whether that needs a password collected first
//   terminal    run `commandLine` in a terminal instead
//   commandLine argv as one sh line, sudo included where it needs root
//   check       argv that exits 0 while the package is installed
//   title       e.g. "Install Steam", for the window and the prompt
//   prompt      what the password prompt says it is for
function plan(action, entry, withPrompt) {
    if (action !== "install" && action !== "remove") return null
    if (!entry || SOURCES.indexOf(entry.source) === -1) return null
    if (!ID.test(entry.id || "")) return null

    var cmd = command(action, entry)
    var terminal = (entry.source === "AUR" && action === "install")
        || (cmd.privileged && !withPrompt)
    var title = (action === "install" ? "Install " : "Remove ") + label(entry)

    // yay builds as you and asks for sudo itself, at the step that needs
    // it; the rest get sudo in front when a terminal is where they run.
    var argv = terminal && cmd.privileged ? ["sudo"].concat(cmd.argv) : cmd.argv

    return {
        argv: terminal ? [] : cmd.argv,
        privileged: !terminal && cmd.privileged,
        terminal: terminal,
        commandLine: terminal ? line(argv) : "",
        check: check(action, entry),
        title: title,
        prompt: line(cmd.argv)
    }
}

// The key a package is tracked by while something is being done to it.
function key(entry) {
    return entry.source + ":" + entry.id
}
