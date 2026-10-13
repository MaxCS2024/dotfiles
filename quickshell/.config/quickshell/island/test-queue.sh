#!/usr/bin/env bash
# Walks the island through every state and queue rule, with made-up
# activities (AGENTS.md, Testing). Nothing on the system changes. Ctrl+C
# clears the queue.
set -euo pipefail

q() { qs -c island ipc call queue "$@" >/dev/null; }
view() { qs -c island ipc call view "$@"; }
step() { printf '\n── %s\n' "$1"; }
trap 'q clear; view collapse >/dev/null' EXIT

q clear

step "idle: the clock (or the notch)"
sleep 2

step "compact: a persistent activity"
q persist media 󰝚 "Song title – Artist" -1 20 0
sleep 3

step "transient over compact, then back"
q flash osd 󰕾 "Volume" 0.4 50 2000
sleep 0.8
step "same key again: updates in place, timer restarts"
q flash osd 󰕾 "Volume" 0.6 50 2000
sleep 3

step "two transients: the higher priority first, then the other"
q flash charger 󰂄 "Charger connected" -1 40 1500
q flash note 󰍡 "Anna – are we still on for tonight?" -1 60 1500
sleep 3.5

step "a higher persistent takes compact; dropping it falls back"
q persist timer 󱎫 "Timer 4:59" -1 30 0
sleep 2
q drop timer
sleep 2

step "expanded: holds transients until it closes"
view expand >/dev/null
q persist media 󰝚 "Song title – Artist" 0.35 20 0
sleep 1
q flash held 󰂄 "Waited for the island to close" -1 40 1500
sleep 2
view collapse >/dev/null
sleep 2.5

step "a persistent with a lifetime: expires after 2 seconds"
q drop media
q persist build 󰔟 "Building… 70%" 0.7 30 2000
sleep 3

step "empty again: idle"
sleep 1
