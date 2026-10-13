import QtQuick
import QtTest
import "../../apps/search.js" as Search

// Tests the App manager's search, through its interface: what a search
// printed and the query in, ranked entries out. Runs under qmltestrunner
// (tests/run packages), and nothing is ever searched for.
TestCase {
    name: "Search"

    // ── Ranking ──────────────────────────────────────────

    function test_rank_order() {
        const q = "firefox"
        const exact = Search.rank("firefox", q)
        const word = Search.rank("firefox-developer-edition", q)
        const prefix = Search.rank("firefoxpwa", q)
        const inside = Search.rank("tor-firefox", q)
        const elsewhere = Search.rank("librewolf", q)
        verify(exact > word, "exact above a whole-word prefix")
        verify(word > prefix, "whole-word prefix above a bare prefix")
        verify(prefix > inside, "prefix above a match inside the name")
        verify(inside > elsewhere, "a name match above a description-only one")
    }

    function test_rank_ignores_case() {
        compare(Search.rank("Firefox", "fireFOX"), 1000)
    }

    // ── pacman and yay ───────────────────────────────────

    readonly property string pacmanOut: [
        "extra/firefox 131.0-1 [installed]",
        "    Fast, Private & Safe Web Browser",
        "extra/firefox-developer-edition 132.0b1-1",
        "    Developer Edition of the popular Firefox web browser",
        "aur/firefoxpwa 2.12.1-1",
        ""
    ].join("\n")

    function test_pacman_entries() {
        const out = Search.parsePacmanish(pacmanOut, "pacman", "firefox")
        compare(out.length, 3)
        compare(out[0].source, "pacman")
        compare(out[0].id, "firefox")
        compare(out[0].name, "firefox")
        compare(out[0].repo, "extra")
        compare(out[0].version, "131.0-1")
        compare(out[0].description, "Fast, Private & Safe Web Browser")
        compare(out[0].installed, true)
        compare(out[1].installed, false)
        compare(out[0].rank, 1000)
    }

    function test_pacman_entry_without_description() {
        const out = Search.parsePacmanish(pacmanOut, "aur", "firefox")
        compare(out[2].id, "firefoxpwa")
        compare(out[2].description, "")
    }

    function test_pacman_nothing_found() {
        compare(Search.parsePacmanish("", "pacman", "x").length, 0)
        compare(Search.parsePacmanish("error: no targets\n", "pacman", "x").length, 0)
    }

    // ── flatpak ──────────────────────────────────────────

    readonly property string flatpakOut: [
        "Name\tDescription\tApplication ID",
        "Firefox\tFast, Private & Safe Web Browser\torg.mozilla.firefox",
        "Visual Studio Code\tCode editing. Redefined.\tcom.visualstudio.code",
        "broken line",
        ""
    ].join("\n")

    function test_flatpak_entries() {
        const out = Search.parseFlatpak(flatpakOut, "firefox", id => id === "org.mozilla.firefox")
        compare(out.length, 2, "header and short lines skipped")
        compare(out[0].source, "flathub")
        compare(out[0].id, "org.mozilla.firefox")
        compare(out[0].name, "Firefox")
        compare(out[0].repo, "flathub")
        compare(out[0].installed, true)
        compare(out[1].installed, false)
    }

    // A title that doesn't match can still rank on its application id.
    function test_flatpak_ranks_the_id_too() {
        const out = Search.parseFlatpak(flatpakOut, "code", id => false)
        const vscode = out.find(e => e.id === "com.visualstudio.code")
        compare(vscode.rank, Math.max(Search.rank("Visual Studio Code", "code"),
                                      Search.rank("com.visualstudio.code", "code")))
    }
}
