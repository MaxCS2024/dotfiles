.pragma library
.import "../services/packages.js" as Pkg

// The App manager's search, as text in and ranked entries out: how well
// a name answers the query, and what `pacman -Ss`, `yay -Ss` and
// `flatpak search` print, read into packages.js entries. Nothing here
// runs a process or knows about the window, which is what lets
// tests/packages check it; apps/AppManager.qml runs the searches and
// keeps the list. They lived in that window until 2026-09-27.

// How well a package name answers the query. Name only, on purpose:
// descriptions match far too eagerly ("firefox" appears in the
// description of every extension and theme for it), and a list sorted by
// anything that generous puts the actual package below a dozen of its
// accessories.
function rank(name, q) {
    const h = name.toLowerCase()
    const n = q.toLowerCase()
    if (h === n) return 1000
    // firefox-developer-edition ranks above firefoxpwa: a separator means
    // the query is a whole word here, not a prefix of a longer one.
    if (h.startsWith(n + "-") || h.startsWith(n + "_")) return 900 - h.length
    if (h.startsWith(n)) return 800 - h.length
    const idx = h.indexOf(n)
    if (idx !== -1) return 600 - idx * 4 - h.length
    // Matched the description rather than the name — the backend thought
    // it was relevant and we have no better opinion.
    return 200 - h.length
}

// pacman and yay share a two-line format:
//   repo/name version [installed]
//       Description text
function parsePacmanish(text, source, q) {
    const lines = text.split("\n")
    const out = []
    let i = 0
    while (i < lines.length) {
        const header = lines[i]
        if (header.trim() === "" || header.startsWith(" ") || header.startsWith("\t")) {
            i++
            continue
        }
        const m = header.match(/^(\S+)\/(\S+)\s+(\S+)/)
        if (!m) { i++; continue }

        const name = m[2]
        let description = ""
        const next = i + 1 < lines.length ? lines[i + 1] : ""
        if (next.startsWith(" ") || next.startsWith("\t")) {
            description = lines[i + 1].trim()
            i += 2
        } else {
            i += 1
        }

        out.push(Pkg.entry(source, name, {
            repo: m[1],
            version: m[3],
            description: description,
            installed: header.includes("[installed"),
            rank: rank(name, q)
        }))
    }
    return out
}

// `flatpak search --columns=name,description,application`: tab-separated,
// with a header row. It does not say what is installed, so `isInstalled`
// (an application id in, a bool out) is asked for each row.
function parseFlatpak(text, q, isInstalled) {
    const out = []
    for (const line of text.split("\n")) {
        if (line.trim() === "") continue
        const parts = line.split("\t")
        if (parts.length < 3) continue
        if (parts[0] === "Name") continue   // header row
        const appId = parts[2]
        out.push(Pkg.entry(Pkg.FLATHUB, appId, {
            name: parts[0],
            repo: "flathub",
            description: parts[1],
            installed: isInstalled(appId),
            // Flathub names are titles ("Visual Studio Code"), not package
            // names, so rank the id too and keep whichever answers better.
            rank: Math.max(rank(parts[0], q), rank(appId, q))
        }))
    }
    return out
}
