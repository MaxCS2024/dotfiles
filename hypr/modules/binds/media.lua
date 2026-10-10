-- Screenshots: Hyprland runs grim, slurp and wl-copy itself, so Print
-- works whichever shell is up, or none (it used to go through main's
-- screenshot service and relay's notification; since 2026-10-10 login
-- starts only the island). Each capture is saved in ~/Pictures/Screenshots
-- and copied to the clipboard, and Hyprland's own notification says so:
-- it needs no notification daemon, and none runs without main.
--   Print        a region, picked with slurp
--   SHIFT+Print  the whole focused screen
--
-- Handed to `sh -c` as one line. Cancelling slurp (Esc) exits before grim
-- runs, so nothing is claimed; a press while a selection is open cancels
-- it rather than stacking a second overlay. Not `repeating`: holding the
-- key would start a capture per repeat tick.
local shotFile = 'dir="$HOME/Pictures/Screenshots"; mkdir -p "$dir"; f="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"; '
local shotDone = ' && wl-copy --type image/png < "$f"'
	.. " && hyprctl eval 'hl.notification.create({ text = \"Screenshot copied, saved in Pictures/Screenshots\", timeout = 3000, icon = \"ok\" })'"
hl.bind("Print", hl.dsp.exec_cmd(
	'pkill -x slurp && exit 0; sel="$(slurp </dev/null)" || exit 0; [ -n "$sel" ] || exit 0; '
		.. shotFile .. 'grim -g "$sel" "$f"' .. shotDone
), { locked = true })
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(
	shotFile .. 'grim -o "$(hyprctl monitors -j | jq -r \'.[] | select(.focused) | .name\')" "$f"' .. shotDone
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

-- Media: playerctl, so the keys work whichever shell is running (the
-- island at login, main by hand, or none). They went through main's own
-- MPRIS client until 2026-10-10, when login stopped starting main and they
-- went dead with it. playerctl's playerctld, started on demand over
-- D-Bus, keeps the player last used first, which is the one these reach.
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

