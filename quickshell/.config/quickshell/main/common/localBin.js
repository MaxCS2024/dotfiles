.pragma library

// Running this config's own tools (rack, relay) from ~/.local/bin.
// ~/.local/bin is exported from .zshrc, which only interactive shells
// read, so whether quickshell inherits it depends on how the session was
// started. Prepending it costs nothing and removes that dependency, as
// hypr/modules/env.lua does for keybinds. Menu actions, Defaults and
// Terminal each spelled this prefix out until 2026-09-27.

// The prefix, for a caller building an sh command line of its own.
var PATH = 'PATH="$HOME/.local/bin:$PATH"'

// An argv that runs `tool` with these arguments, each passed as its own
// word. `tool` is a fixed name, never user input.
function argv(tool, args) {
    return ["sh", "-c", PATH + " exec " + tool + ' "$@"', "sh"].concat(args || [])
}
