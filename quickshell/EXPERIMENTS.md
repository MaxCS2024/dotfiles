# Experimenting with bar/layout styling

Quickshell configs are discovered as named directories:
`~/.config/quickshell/<name>/shell.qml`, run with `qs -c <name>`. This repo
uses that directly — `quickshell/main/` is the stable, daily-driver config
(what autostart launches). Anything else under `quickshell/` is a config you
can run side-by-side with `main` to try a different bar/layout without
touching what already works.

## Start a new experiment

```
cd ~/.dotfiles
./quickshell/new-config.sh my-experiment
stow -R -t ~/.config/quickshell quickshell
qs -c my-experiment
```

That launches `my-experiment` as its own window/bar, running alongside your
real `main` instance — it doesn't replace anything, doesn't touch autostart,
and closing it (`Ctrl+C` in the terminal you ran it from) leaves `main`
untouched.

## What's shared vs. what's yours to break

`new-config.sh` splits the config in two:

- **Symlinked from `main/`** — `common/`, `config/`, `services/`. This is
  theme (`Theme.qml`) and backend services (battery, network, mpris,
  bluetooth, etc.) that both configs point at the *same files*. Editing one
  of these edits it for `main` too — don't touch these unless you actually
  want to change the shared theme/services for everything.
- **Copied from `main/`** — `shell.qml` and every other top-level directory
  of `main`'s. `new-config.sh`'s `layout_entries` is the actual list; it is
  not repeated here, because the copy that lived in this file spent months
  naming `dashboard/` and two settings panels that no longer exist. This is a
  real, independent copy. Rewrite
  `bar/Bar.qml`, add new bar modules, restructure `bar/Modules.qml`,
  whatever — none of it can affect `main`.

If a bar styling idea needs to read from a service that doesn't exist yet,
add it under `services/` — since that directory is shared, it'll show up in
both configs immediately (useful for iterating on the service itself, but
remember it's live in `main` too).

## Iterating

Quickshell watches the config and reloads it, so edits to files under
`quickshell/my-experiment/` are live in the running instance within a
second or two — its log says `Reloading configuration...` each time. Keep
`qs -c my-experiment` running in a terminal and watch that log: a QML
error prints there and the old version stays up.

Relaunching is only needed for changes the watcher can't see through —
a new top-level directory, or a file the shell never imported.

(No need to re-run `stow` again unless you add/remove whole files or
directories — `stow -R` only needs re-running when the *set* of paths
changes, not their contents, since edits happen through the existing
symlinks.)

## Promoting an experiment to be the daily driver

There's no automated "swap" — do it deliberately:

1. Decide what you're keeping. You can also cherry-pick pieces back into
   `main/` by hand instead of swapping the whole config.
2. To fully promote `my-experiment` in place of `main`:
   ```
   cd ~/.dotfiles/quickshell
   mv main main.old
   mv my-experiment main
   ```
   Fix up `main`'s now-broken `common`/`config`/`services` symlinks (they
   pointed at `../main/...`, which is now itself) — either replace them
   with the real directories from `main.old`, or just delete `main.old`
   once you're sure the shared files didn't need anything from the old copy.
3. `stow -R -t ~/.config/quickshell quickshell`, then restart quickshell
   (however you normally do — e.g. kill the running `qs` process and let
   autostart or a manual `qs -c main` bring it back).

`hypr/modules/autostart.lua` and the screenshot IPC keybind
(`hypr/modules/binds/media.lua`) both hardcode `-c main`, so as long as the
promoted config ends up at `quickshell/main/`, neither needs edits.

## What's here now

Nothing but `main/`. `installer/` lived here for a day — one window
searching pacman, the AUR and Flathub at once — and was promoted into
`quickshell/main/installer/` once it worked, which is what this whole
arrangement is for. Its history is in the log if the demo version is
ever wanted back.

`old/` — the previous config, which `main` was built alongside — sat here
until 2026-09-20 and is gone. `main/common`, `main/config` and
`main/services` were symlinks *into* it; they are real directories in
`main/` now, with the same contents, which is why `new-config.sh` points
an experiment's shared symlinks at `../main/` rather than anywhere else.
The whole config is in the log if any of it is ever wanted back.

## Cleaning up an abandoned experiment

```
rm -rf quickshell/my-experiment
stow -R -t ~/.config/quickshell quickshell
```
