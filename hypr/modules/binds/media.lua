-- Screenshot: routed through Quickshell's screenshot capture, which runs
-- grim + slurp + wl-copy itself and posts a notification —
-- see notifications/Screenshot.qml in the quickshell dotfiles.
--
-- Not `repeating`: holding the key would start a capture per repeat tick,
-- each with its own slurp overlay stacked on the last.
hl.bind("Print", hl.dsp.exec_cmd("qs -c main ipc call screenshot capture"), { locked = true })

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
-- notifies nothing rather than claiming an empty clipboard. A press while a
-- selection is already open (from either Print bind) cancels it instead of
-- opening another overlay over it, the same as the popup does.
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(
	'pkill -x slurp && exit 0; ' ..
		'dir="$HOME/Pictures/Screenshots"; mkdir -p "$dir"; ' ..
		'sel="$(slurp </dev/null)" || exit 0; [ -n "$sel" ] || exit 0; ' ..
		'f="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"; ' ..
		'grim -g "$sel" "$f" && wl-copy --type image/png < "$f" && ' ..
		'relay notif send "Screenshot copied" ' ..
		'"The image is in the clipboard" -a Screenshot --image "$f"'
), { locked = true })

-- Volume: wpctl (WirePlumber CLI — matches the Pipewire backend your Volume tab already uses)
-- Each press also pokes the dynamic island (~/.config/quickshell/dynamic-island,
-- Controls.qml), so its volume face answers even at 100% or 0%, where
-- wpctl changes nothing and the island would otherwise never hear of it.
local function volumeStep(step, limit)
	return function()
		hl.exec_cmd("wpctl set-volume " .. limit .. "@DEFAULT_AUDIO_SINK@ " .. step)
		hl.dispatch(hl.dsp.global("quickshell:island-osd-volume"))
	end
end
hl.bind("XF86AudioRaiseVolume", volumeStep("5%+", "-l 1.0 "), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", volumeStep("5%-", ""), { locked = true, repeating = true })

hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })

-- Wifi toggle: nmcli (already used throughout your Network tab)
hl.bind("XF86RFKill", hl.dsp.exec_cmd("nmcli radio wifi $(test $(nmcli -t -f WIFI radio) = enabled && echo off || echo on)"), { locked = true, repeating = true })

-- Brightness: brightnessctl, ramped on our own timer instead of riding
-- Hyprland's raw key-repeat. A repeating bind fires a brand-new
-- brightnessctl process on every OS repeat tick with no back-pressure —
-- fine at a few big steps, but subprocess spawn + sysfs/udev round-trip
-- can't reliably keep up with a fast repeat rate, so a bare "N%+ per
-- tick" bind either has to use big steps (feels steppy) or drops/queues
-- ticks under a fast one (feels janky). Instead: press fires one step
-- immediately, then starts a fixed-cadence timer that keeps firing the
-- same small step until release — one process per tick at a pace we
-- control, giving an evenly-paced fade closer to how a modern laptop's
-- brightness keys ramp on a long hold, decoupled entirely from
-- input.repeat_rate/repeat_delay.
-- Every step also pokes the dynamic island's brightness face (as the
-- volume keys do above), so a press or hold at 100% or 1% still answers.
local function brightnessStep(step)
	hl.exec_cmd("brightnessctl -n2 set " .. step)
	hl.dispatch(hl.dsp.global("quickshell:island-osd-brightness"))
end

local function brightnessRamp(step)
	local timer = hl.timer(function()
		brightnessStep(step)
	end, { timeout = 35, type = "repeat" })
	timer:set_enabled(false)
	return timer
end

local brightnessUpTimer = brightnessRamp("2%+")
local brightnessDownTimer = brightnessRamp("2%-")

hl.bind("XF86MonBrightnessUp", function()
	brightnessStep("10%+")
	brightnessUpTimer:set_enabled(true)
end, { locked = true })
hl.bind("XF86MonBrightnessUp", function()
	brightnessUpTimer:set_enabled(false)
end, { locked = true, release = true })

hl.bind("XF86MonBrightnessDown", function()
	brightnessStep("10%-")
	brightnessDownTimer:set_enabled(true)
end, { locked = true })
hl.bind("XF86MonBrightnessDown", function()
	brightnessDownTimer:set_enabled(false)
end, { locked = true, release = true })

-- Media: services/Media.qml, on the same player the bar's media module and
-- card show (Quickshell's own MPRIS client, so no playerctl). Scripts can
-- reach the same three with `qs -c main ipc call player playPause|next|previous`.
hl.bind("XF86AudioNext", hl.dsp.global("quickshell:media-next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.global("quickshell:media-play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.global("quickshell:media-play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.global("quickshell:media-previous"), { locked = true })

