# Default apps are owned by one Lua module, reached through `relay default`

The candidates for each role, the order they resolve in and what each
app needs to be launched live in one Lua module under `hypr/modules/`.
Hyprland `require`s it at config load; the shell and scripts reach it
only through `relay default`, which makes standalone `lua` a required
dependency. Lua because Hyprland has to evaluate the default in-process
when it loads its binds, before the shell may have ever run: a table
owned by QML would need a second copy for a fresh checkout, and a bash
one would cost Hyprland a process per config load.

## Considered Options

- **The shell owns the table and writes a resolved file for Hyprland.**
  Rejected: there is no file until the shell's first run, so the binds
  would need their own fallback, which is the second copy this removes.
- **`relay` owns it in bash.** Rejected: Hyprland would spawn a process
  at every config load just to name a terminal.
- **Keep `lua` optional with `Theme.terminal` as a silent fallback.**
  Rejected: that fallback is what hid the undeclared dependency.
