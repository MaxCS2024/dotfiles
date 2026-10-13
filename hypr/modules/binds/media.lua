local shotFile = 'dir="$HOME/Pictures/Screenshots"; mkdir -p "$dir"; f="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"; '
local shotDone = ' && wl-copy --type image/png < "$f"'
	.. ' && notify-send -a Screenshot -u low -t 3000 -i "$f" "Screenshot copied" "Saved in Pictures/Screenshots as ${f##*/}"'
hl.bind("Print", hl.dsp.exec_cmd(
	'pkill -x slurp && exit 0; sel="$(slurp </dev/null)" || exit 0; [ -n "$sel" ] || exit 0; '
		.. shotFile .. 'grim -g "$sel" "$f"' .. shotDone
), { locked = true })
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(
	shotFile .. 'grim -o "$(hyprctl monitors -j | jq -r \'.[] | select(.focused) | .name\')" "$f"' .. shotDone
), { locked = true })

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

hl.bind("XF86RFKill", hl.dsp.exec_cmd("nmcli radio wifi $(test $(nmcli -t -f WIFI radio) = enabled && echo off || echo on)"), { locked = true, repeating = true })

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

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

hl.bind("Caps_Lock", hl.dsp.global("quickshell:island-capslock"), { locked = true, release = true, non_consuming = true })
