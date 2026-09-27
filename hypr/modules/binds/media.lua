-- Screenshot: routed through Quickshell's screenshot popup, which runs
-- grim + slurp + wl-copy itself and shows a thumbnail/notification —
-- see notifications/ScreenshotPopup.qml in the quickshell dotfiles.
hl.bind("Print", hl.dsp.exec_cmd("qs -c main ipc call screenshot capture"), { locked = true, repeating = true })

-- Screenshot to file: same region select, saved to disk and copied to the
-- clipboard, then a notification confirming the copy. The copy is what the
-- notification is about — without the wl-copy step the message would be a
-- lie, since this bind used to write the file and nothing else.
--
-- `relay` needs no PATH fixup here any more: modules/env.lua puts
-- ~/.local/bin on the PATH Hyprland hands to `sh -c`, which is where its
-- installer links it. That line is load-bearing for this bind — without it
-- the notification silently never arrives, because a bind's stderr goes
-- nowhere the user ever sees.
--
-- One line, not a multi-line string: this is handed straight to `sh -c`, and
-- keeping it flat avoids depending on how the dispatcher treats newlines.
-- Cancelling slurp (Esc) exits before grim runs, so a cancelled capture
-- notifies nothing rather than claiming an empty clipboard.
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(
	'dir="$HOME/Pictures/Screenshots"; mkdir -p "$dir"; ' ..
		'sel="$(slurp)" || exit 0; [ -n "$sel" ] || exit 0; ' ..
		'f="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"; ' ..
		'grim -g "$sel" "$f" && wl-copy --type image/png < "$f" && ' ..
		'relay notif send "Screenshot copied" ' ..
		'"The image is in the clipboard" -a Screenshot --image "$f"'
), { locked = true, repeating = true })

-- Volume: wpctl (WirePlumber CLI — matches the Pipewire backend your Volume tab already uses)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })

hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })

-- Wifi toggle: nmcli (already used throughout your Network tab)
hl.bind("XF86RFKill", hl.dsp.exec_cmd("nmcli radio wifi $(test $(nmcli -t -f WIFI radio) = enabled && echo off || echo on)"), { locked = true, repeating = true })

-- Brightness: services/Brightness.qml in the shell. Hyprland sends a
-- `global` shortcut both its press and its release, so the shell steps 10%
-- on the press and ramps 2% every 35ms while the key is held, stopping on
-- release — the ramp these binds used to run on an hl.timer, spawning
-- brightnessctl per tick. Writes go to systemd-logind, so there is no
-- brightnessctl to install. `relay brightness` is the same thing for scripts.
hl.bind("XF86MonBrightnessUp", hl.dsp.global("quickshell:brightness-up"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.global("quickshell:brightness-down"), { locked = true })

-- Media: services/Media.qml, on the same player the bar's media module and
-- card show (Quickshell's own MPRIS client, so no playerctl). Scripts can
-- reach the same three with `qs -c main ipc call player playPause|next|previous`.
hl.bind("XF86AudioNext", hl.dsp.global("quickshell:media-next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.global("quickshell:media-play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.global("quickshell:media-play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.global("quickshell:media-previous"), { locked = true })

