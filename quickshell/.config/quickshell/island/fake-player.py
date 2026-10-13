#!/usr/bin/env python3
"""A silent MPRIS player for testing the media activity (AGENTS.md, Testing).

    fake-player.py [--art FILE] [--paused]

Shows up as "Island test player" with a three-track playlist and a fake
clock; play/pause, next and previous work from any MPRIS client (the
island, playerctl). It plays no sound. Ctrl+C or SIGTERM ends it.
"""

import argparse
import signal
import time

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib, GLibUnix

BUS_NAME = "org.mpris.MediaPlayer2.islandtest"
PATH = "/org/mpris/MediaPlayer2"
ROOT = "org.mpris.MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"
PROPS = "org.freedesktop.DBus.Properties"

TRACKS = [
    ("Midnight City", "M83", 243),
    ("A rather long song title that will not fit in the island", "Someone With A Long Name", 187),
    ("Teardrop", "Massive Attack", 330),
]


class Player(dbus.service.Object):
    def __init__(self, bus, art, paused):
        super().__init__(bus, PATH)
        self.art = art
        self.index = 0
        self.playing = not paused
        self.offset = 0.0  # seconds into the track when the clock last started
        self.started = time.monotonic()

    # ── State ──
    def position(self):
        pos = self.offset + (time.monotonic() - self.started if self.playing else 0)
        return min(pos, TRACKS[self.index][2])

    def metadata(self):
        title, artist, length = TRACKS[self.index]
        md = {
            "mpris:trackid": dbus.ObjectPath(f"/islandtest/track/{self.index}"),
            "mpris:length": dbus.Int64(length * 1_000_000),
            "xesam:title": title,
            "xesam:artist": dbus.Array([artist], signature="s"),
        }
        if self.art:
            md["mpris:artUrl"] = "file://" + self.art
        return dbus.Dictionary(md, signature="sv")

    def player_props(self):
        return {
            "PlaybackStatus": "Playing" if self.playing else "Paused",
            "Metadata": self.metadata(),
            "Position": dbus.Int64(int(self.position() * 1_000_000)),
            "Rate": 1.0,
            "MinimumRate": 1.0,
            "MaximumRate": 1.0,
            "Volume": 1.0,
            "CanGoNext": True,
            "CanGoPrevious": True,
            "CanPlay": True,
            "CanPause": True,
            "CanSeek": False,
            "CanControl": True,
            "LoopStatus": "None",
            "Shuffle": False,
        }

    def root_props(self):
        return {
            "Identity": "Island test player",
            "CanQuit": False,
            "CanRaise": False,
            "HasTrackList": False,
            "SupportedUriSchemes": dbus.Array([], signature="s"),
            "SupportedMimeTypes": dbus.Array([], signature="s"),
        }

    def changed(self, *names):
        props = self.player_props()
        self.PropertiesChanged(PLAYER, {n: props[n] for n in names}, [])

    def set_playing(self, playing):
        self.offset = self.position()
        self.started = time.monotonic()
        self.playing = playing
        self.changed("PlaybackStatus")

    def go(self, step):
        self.index = (self.index + step) % len(TRACKS)
        self.offset = 0.0
        self.started = time.monotonic()
        self.changed("Metadata")
        self.Seeked(dbus.Int64(0))

    # ── org.mpris.MediaPlayer2.Player ──
    @dbus.service.method(PLAYER)
    def PlayPause(self):
        self.set_playing(not self.playing)

    @dbus.service.method(PLAYER)
    def Play(self):
        self.set_playing(True)

    @dbus.service.method(PLAYER)
    def Pause(self):
        self.set_playing(False)

    @dbus.service.method(PLAYER)
    def Stop(self):
        self.set_playing(False)

    @dbus.service.method(PLAYER)
    def Next(self):
        self.go(1)

    @dbus.service.method(PLAYER)
    def Previous(self):
        self.go(-1)

    @dbus.service.method(PLAYER, in_signature="x")
    def Seek(self, offset):
        pass

    @dbus.service.method(PLAYER, in_signature="ox")
    def SetPosition(self, track, position):
        pass

    @dbus.service.signal(PLAYER, signature="x")
    def Seeked(self, position):
        pass

    # ── org.mpris.MediaPlayer2 ──
    @dbus.service.method(ROOT)
    def Raise(self):
        pass

    @dbus.service.method(ROOT)
    def Quit(self):
        pass

    # ── org.freedesktop.DBus.Properties ──
    @dbus.service.method(PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self.GetAll(interface)[name]

    @dbus.service.method(PROPS, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface == PLAYER:
            return self.player_props()
        if interface == ROOT:
            return self.root_props()
        return {}

    @dbus.service.method(PROPS, in_signature="ssv")
    def Set(self, interface, name, value):
        pass

    @dbus.service.signal(PROPS, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass


def main():
    parser = argparse.ArgumentParser(description="A silent MPRIS player for testing.")
    parser.add_argument("--art", help="an image file to use as the album art")
    parser.add_argument("--paused", action="store_true", help="start paused")
    args = parser.parse_args()

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName(BUS_NAME, bus)  # noqa: F841 (held for the name)
    Player(bus, args.art, args.paused)

    loop = GLib.MainLoop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, sig, loop.quit)
    loop.run()


if __name__ == "__main__":
    main()
