# rig

Shell primitives for the scripts that hold a desktop together. Runs as a
command, or source it as a library:

```bash
rig log info "starting"
rig lock run wallpaper -- swww img next.png

source "$(command -v rig)"
rig::trap::strict
rig::tmp::file shot .png
```

It knows nothing about the compositor or the dotfiles repo, and would run
unchanged on a headless server. That is the whole point: it is the bottom of
three tools.

```
rack  →  relay  →  rig
```

- **rig** — primitives. This repo.
- **relay** — desktop actions: volume, brightness, screenshots, wallpaper,
  compositor IPC, bar output. What the keybinds call.
- **rack** — configuration: deploy, theme, validate, diff.

Dependencies run one way only. Nothing here may ever read rack's config or know
relay exists, or every keybind starts paying for a config parse.

## Install

```bash
./install.sh              # symlinks into ~/.local, editable in place
./install.sh --copy       # copies, for a machine without the repo
./install.sh --dry-run
./install.sh --uninstall
```

Needs bash 4.2+ and `flock` (util-linux). Everything lands under `$HOME`; the
installer never wants root, and never edits your shell rc — if `~/.local/bin`
is not on PATH it prints the line and stops.

There is another `rig` in the wild (the R Installation Manager, which installs
to `/usr/local/bin`). The installer warns if it finds one, because whichever
directory comes first in PATH wins silently.

## Modules

Ten are built. The rest are declared so `rig help` and completion tell the
truth about what exists.

| module   | what it does |
| -------- | ------------ |
| `log`    | leveled messages to stderr; also to the journal when there is no tty |
| `check`  | `has` / `require`, naming the pacman package that provides what is missing |
| `path`   | XDG directories, created on demand |
| `trap`   | a cleanup **stack**, plus strict mode with a useful ERR trap |
| `tmp`    | temp files and directories that remove themselves |
| `lock`   | single-instance guards via flock |
| `notify` | desktop notifications, falling back to the log |
| `proc`   | process checks, and the `RIG_DRY_RUN` choke point |
| `link`   | idempotent symlinks and their status |
| `config` | read values that rack writes |

Planned: `prompt` `cache` `retry` `fmt` `args` `doctor`.
`rig list` shows the current state.

## Why trap is the important one

bash's `trap` overwrites. The moment two pieces of code both want cleanup, one
silently loses and you never find out. `rig::trap::add` stacks handlers and
fires them in reverse, exactly once, on `EXIT INT TERM HUP` — preserving the
exit status, and continuing if one handler fails.

Traps are not installed at load time. A library has no business putting an EXIT
trap into an interactive shell that merely sourced it; the first `add` arms it.

## The one API that looks odd

`tmp` takes the **name of a variable**, not a path to print:

```bash
rig::tmp::file shot .png      # assigns $shot
shot=$(rig::tmp::file .png)   # wrong, and it used to be the API
```

`$(...)` runs in a subshell. A function that both printed a path and registered
its cleanup would register that cleanup in the subshell, fire it when the
subshell exited, and hand back a path to a file it had just deleted. Assigning
to the caller's variable keeps both halves in one process. The cleanup stack
also refuses to fire in any process that does not own it, so a stray command
substitution cannot delete files that are still in use.

## Conventions

- **stdout is data, stderr is for humans.** Logs, prompts and errors all go to
  stderr, so `count=$(rig pkg updates)` stays clean.
- **`set -euo pipefail` only when executed**, never when sourced — it would
  hijack the caller's shell.
- **Exit codes:** 0 ok, 1 failure, 2 usage, 127 missing dependency.
- **Lazy loading.** Executed mode sources only the module named; sourcing loads
  the core tier, and `rig::load <mod>` gets the rest.
- **Modules declare their own dependencies** by calling `rig::load` at the top
  of the file, so the graph is visible in the files rather than in a table.
- `RIG_LIB_DIR` overrides the module path, so you can test a working copy
  without touching the installed symlinks.

Environment: `RIG_LOG_LEVEL`, `RIG_LOG_JOURNAL`, `RIG_TAG`, `RIG_COLOR`, and
the standard `NO_COLOR`.

## Tests

```bash
tests/run          # everything
tests/run lock     # one file
```

No dependencies — a config repo's tests should run on a fresh machine. They
cover the cleanup stack, temp-file lifetime, locking, and the log level gate,
which are the parts that fail silently rather than loudly.

## Next

`doctor` first — PATH order, missing optional dependencies, stale symlinks, a
shadowing binary. Then `proc`, because `RIG_DRY_RUN` is impossible to retrofit
once forty scripts call things directly.
