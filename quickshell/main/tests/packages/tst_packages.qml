import QtQuick
import QtTest
import "../../services/packages.js" as Packages

// Tests how a package change is planned, through the planner's interface:
// an action and an entry in, what to run and how out. Runs under
// qmltestrunner (tests/run packages), so no Wayland or Hyprland session is
// needed, and nothing is ever installed.
TestCase {
    name: "Packages"

    readonly property var steam: ({ source: "pacman", id: "steam", name: "Steam" })
    readonly property var heroic: ({ source: "aur", id: "heroic-games-launcher-bin", name: "Heroic" })
    readonly property var obsidian: ({ source: "flathub", id: "md.obsidian.Obsidian", name: "Obsidian" })

    // ── Where it runs ────────────────────────────────────

    function test_where_it_runs_data() {
        return [
            { tag: "repo install, window", action: "install", entry: steam, prompt: true,
              terminal: false, privileged: true },
            { tag: "repo install, no window", action: "install", entry: steam, prompt: false,
              terminal: true, privileged: false },
            { tag: "AUR install, window", action: "install", entry: heroic, prompt: true,
              terminal: true, privileged: false },
            { tag: "AUR install, no window", action: "install", entry: heroic, prompt: false,
              terminal: true, privileged: false },
            { tag: "AUR remove, window", action: "remove", entry: heroic, prompt: true,
              terminal: false, privileged: true },
            { tag: "flatpak install, window", action: "install", entry: obsidian, prompt: true,
              terminal: false, privileged: true },
            { tag: "flatpak install, no window", action: "install", entry: obsidian, prompt: false,
              terminal: true, privileged: false },
            { tag: "system flatpak remove, window", action: "remove",
              entry: { source: "flathub", id: "md.obsidian.Obsidian", scope: "system" }, prompt: true,
              terminal: false, privileged: true },
            { tag: "user flatpak remove, window", action: "remove",
              entry: { source: "flathub", id: "md.obsidian.Obsidian", scope: "user" }, prompt: true,
              terminal: false, privileged: false },
            { tag: "user flatpak remove, no window", action: "remove",
              entry: { source: "flathub", id: "md.obsidian.Obsidian", scope: "user" }, prompt: false,
              terminal: false, privileged: false }
        ]
    }

    function test_where_it_runs(data) {
        const p = Packages.plan(data.action, data.entry, data.prompt)
        verify(p !== null)
        compare(p.terminal, data.terminal, "terminal")
        compare(p.privileged, data.privileged, "privileged")
    }

    // ── What it runs ─────────────────────────────────────

    function test_repo_install_behind_the_window() {
        const p = Packages.plan("install", steam, true)
        compare(p.argv, ["pacman", "-S", "--needed", "--noconfirm", "steam"])
        compare(p.commandLine, "")
    }

    function test_repo_install_in_a_terminal_has_sudo() {
        const p = Packages.plan("install", steam, false)
        compare(p.argv, [])
        compare(p.commandLine, "'sudo' 'pacman' '-S' '--needed' '--noconfirm' 'steam'")
    }

    function test_aur_install_is_yay_without_sudo() {
        // yay builds as the user and asks for sudo itself; run under sudo
        // it refuses to build at all.
        const p = Packages.plan("install", heroic, true)
        compare(p.commandLine, "'yay' '-S' '--needed' 'heroic-games-launcher-bin'")
    }

    function test_flatpak_installs_to_the_system() {
        const p = Packages.plan("install", obsidian, true)
        compare(p.argv, ["flatpak", "install", "-y", "--system", "flathub", "md.obsidian.Obsidian"])
    }

    function test_flatpak_remove_follows_its_scope() {
        const user = Packages.plan("remove", { source: "flathub", id: "a.b.C", scope: "user" }, true)
        compare(user.argv, ["flatpak", "uninstall", "-y", "--user", "a.b.C"])
        const system = Packages.plan("remove", { source: "flathub", id: "a.b.C", scope: "system" }, true)
        compare(system.argv, ["flatpak", "uninstall", "-y", "--system", "a.b.C"])
    }

    function test_flatpak_without_a_scope_is_the_system_one() {
        const p = Packages.plan("remove", { source: "flathub", id: "a.b.C" }, true)
        compare(p.argv, ["flatpak", "uninstall", "-y", "--system", "a.b.C"])
    }

    function test_remove_is_rns_for_repo_and_aur() {
        compare(Packages.plan("remove", steam, true).argv, ["pacman", "-Rns", "--noconfirm", "steam"])
        compare(Packages.plan("remove", heroic, true).argv,
                ["pacman", "-Rns", "--noconfirm", "heroic-games-launcher-bin"])
    }

    // ── How to tell it landed ────────────────────────────

    function test_check_data() {
        return [
            { tag: "repo", action: "install", entry: steam, check: ["pacman", "-Q", "steam"] },
            { tag: "AUR", action: "install", entry: heroic,
              check: ["pacman", "-Q", "heroic-games-launcher-bin"] },
            { tag: "flatpak install", action: "install", entry: obsidian,
              check: ["flatpak", "info", "--system", "md.obsidian.Obsidian"] },
            { tag: "user flatpak remove", action: "remove",
              entry: { source: "flathub", id: "a.b.C", scope: "user" },
              check: ["flatpak", "info", "--user", "a.b.C"] }
        ]
    }

    function test_check(data) {
        compare(Packages.plan(data.action, data.entry, false).check, data.check)
    }

    // ── What the window says ─────────────────────────────

    function test_title_uses_the_name() {
        compare(Packages.plan("install", steam, true).title, "Install Steam")
        compare(Packages.plan("remove", { source: "pacman", id: "htop" }, true).title, "Remove htop")
    }

    function test_prompt_names_the_command() {
        compare(Packages.plan("install", steam, true).prompt,
                "'pacman' '-S' '--needed' '--noconfirm' 'steam'")
    }

    // ── What can't be planned ────────────────────────────

    function test_unplannable_data() {
        return [
            { tag: "unknown action", action: "upgrade", entry: steam },
            { tag: "unknown source", action: "install", entry: { source: "Snap", id: "x" } },
            { tag: "no entry", action: "install", entry: null },
            { tag: "empty id", action: "install", entry: { source: "pacman", id: "" } },
            { tag: "id that is an option", action: "install", entry: { source: "pacman", id: "-Syu" } },
            { tag: "id with a space", action: "install", entry: { source: "pacman", id: "a b" } },
            { tag: "id with a quote", action: "remove", entry: { source: "aur", id: "x';rm" } }
        ]
    }

    function test_unplannable(data) {
        compare(Packages.plan(data.action, data.entry, true), null)
    }

    function test_names_pacman_allows() {
        // Real names with the characters an over-strict pattern would
        // reject: a plus, an at sign, a dot.
        for (const id of ["gtk+", "libc++", "python-foo@2", "dotnet-runtime-6.0", "0ad"])
            verify(Packages.plan("install", { source: "pacman", id: id }, true) !== null, id)
    }

    function test_key() {
        compare(Packages.key(steam), "pacman:steam")
    }

    // ── Entries ──────────────────────────────────────────

    function test_entry_fills_the_rest() {
        const e = Packages.entry(Packages.FLATHUB, "md.obsidian.Obsidian", { name: "Obsidian", scope: "user" })
        compare(e.source, "flathub")
        compare(e.id, "md.obsidian.Obsidian")
        compare(e.name, "Obsidian")
        compare(e.version, "")
        compare(e.description, "")
        compare(e.installed, false)
        compare(e.scope, "user")
        compare(Packages.entry(Packages.PACMAN, "htop").name, "htop", "name defaults to the id")
    }

    function test_every_source_is_labelled() {
        for (const s of Packages.SOURCES)
            verify((Packages.LABELS[s] || "") !== "", s)
    }

    // A label is what a window shows, not a source: an entry carrying one
    // is refused rather than planned as something else.
    function test_label_is_not_a_source() {
        compare(Packages.plan("install", { source: "Flathub", id: "a.b.C" }, true), null)
    }
}
