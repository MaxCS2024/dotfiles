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
local function brightnessRamp(step)
	local timer = hl.timer(function()
		hl.exec_cmd("brightnessctl -n2 set " .. step)
	end, { timeout = 35, type = "repeat" })
	timer:set_enabled(false)
	return timer
end

local brightnessUpTimer = brightnessRamp("2%+")
local brightnessDownTimer = brightnessRamp("2%-")

hl.bind("XF86MonBrightnessUp", function()
	hl.exec_cmd("brightnessctl -n2 set 10%+")
	brightnessUpTimer:set_enabled(true)
end, { locked = true })
hl.bind("XF86MonBrightnessUp", function()
	brightnessUpTimer:set_enabled(false)
end, { locked = true, release = true })

hl.bind("XF86MonBrightnessDown", function()
	hl.exec_cmd("brightnessctl -n2 set 10%-")
	brightnessDownTimer:set_enabled(true)
end, { locked = true })
hl.bind("XF86MonBrightnessDown", function()
	brightnessDownTimer:set_enabled(false)
end, { locked = true, release = true })

-- Requires playerctl
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

