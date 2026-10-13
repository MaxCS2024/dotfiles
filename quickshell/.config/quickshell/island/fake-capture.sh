#!/usr/bin/env bash
# Makes it look as if an app is using the microphone, the camera or the
# screen, for testing the privacy dots (AGENTS.md, Testing), without
# touching a real device:
#
#   fake-capture.sh mic|camera|screen [app name]
#
# A test source (silence, or a test picture) and a test app reading it,
# both PipeWire nodes, linked by hand. The app never connects on its own,
# so it can't fall back to the real microphone or camera; the link is
# checked before the script settles. Ctrl+C ends both.
#
# Why so careful: `pw-record --target X` quietly records from the default
# microphone when X doesn't exist (2026-10-13).
set -euo pipefail

kind=${1:-}
app=${2:-Island test ($kind)}
case $kind in
    mic)    class=Audio/Source; src=(audiotestsrc wave=silence is-live=true) ;;
    camera) class=Video/Source; src=(videotestsrc is-live=true '!' video/x-raw,width=320,height=240,framerate=15/1) ;;
    screen) class=Video/Source; src=(videotestsrc is-live=true '!' video/x-raw,width=320,height=240,framerate=15/1) ;;
    *) echo "usage: ${0##*/} mic|camera|screen [app name]" >&2; exit 2 ;;
esac

# The screen's source is named like xdg-desktop-portal-hyprland's
# screencast nodes; having no device.api is what makes it a screen.
source_name=island-test-$kind-$$
[[ $kind == screen ]] && source_name=xdph-streaming-island-test-$$
# The process id keeps several at once apart.
reader_name=island-test-reader-$kind-$$

pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null || true; }
trap cleanup EXIT

# Node properties go in through PIPEWIRE_PROPS, which every PipeWire
# stream reads; gst-launch's own parser mangles spaces and brackets.
# A camera is told from a screencast by having a device.api (v4l2,
# libcamera); the test camera claims one.
source_props="node.name = $source_name node.description = $source_name media.class = $class"
[[ $kind == camera ]] && source_props+=" device.api = fake"
PIPEWIRE_PROPS="{ $source_props }" \
    gst-launch-1.0 -q "${src[@]}" '!' pipewiresink mode=provide >/dev/null 2>&1 &
pids+=($!)

reader_props="{ node.name = $reader_name application.name = \"$app\" node.dont-fallback = true node.autoconnect = false }"
if [[ $kind == mic ]]; then
    # pipewiresrc can't take raw audio; pw-record can, and with
    # autoconnect off it links to nothing until linked below.
    pw-record -P "$reader_props" /dev/null >/dev/null 2>&1 &
else
    PIPEWIRE_PROPS="$reader_props" \
        gst-launch-1.0 -q pipewiresrc autoconnect=false '!' fakesink >/dev/null 2>&1 &
fi
pids+=($!)

# Both nodes up, then the one link.
for _ in {1..20}; do
    pw-link -o | grep -q "^$source_name:" && pw-link -i | grep -q "^$reader_name:" && break
    sleep 0.25
done
pw-link "$source_name" "$reader_name"

# The reader must be linked, and only to the test node.
sleep 0.5
links=$(pw-link -l | grep -A1 "^$reader_name:" | grep -- '|<-' || true)
if [[ -z $links ]] || grep -qv "$source_name:" <<<"$links"; then
    echo "the reader isn't linked to the test source alone; stopped" >&2
    exit 1
fi
echo "$app is using the $kind (fake). Ctrl+C to stop."
wait
