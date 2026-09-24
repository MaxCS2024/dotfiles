#!/usr/bin/env python3
"""Battery of Nothing earbuds: left, right and case, one JSON line per change.

Run through `relay earbuds watch` (earbuds.sh next door); the shell's
services/Earbuds.qml is what reads it. Every line is a whole state:

    {"connected": false}
    {"connected": true, "name": "Nothing Ear (3)", "address": "2C:BE:EE:…",
     "left":  {"level": 95, "charging": false, "stale": false},
     "right": {"level": 95, "charging": false, "stale": false},
     "case":  null}

A part is null until the earbuds have reported it once. The case reports
only while a bud is in it with the lid open; once it drops out of a report,
its last reading is kept with "stale": true rather than thrown away, and a
disconnect forgets everything.

The protocol is Nothing's own, spoken over RFCOMM on the service
aeac4a03-dff5-498f-843a-34487cf133eb (the one the Nothing X app uses; the
same one Gadgetbridge and ear-web reverse-engineered). Checked against an
Ear (3) on 2026-09-24: request 0xC007 is answered with 0x4007, and the
earbuds push 0xE001 on their own when a level changes. Both carry

    count, then per battery: id (2 left, 3 right, 4 case), level | 0x80 charging

BlueZ's profile API does the SDP lookup and the connecting, and hands the
socket over in NewConnection, so no channel number is hard-coded here.

Exit status: 0 on SIGTERM/SIGINT, 1 when BlueZ goes away or cannot be
reached (the shell starts this again), 3 when another watcher already has
the profile.

`earbuds.py decode <hex>` prints what one captured frame decodes to; the
tests use it (relay/tests/relay-earbuds.test.sh).
"""

import json
import os
import signal
import socket
import sys

SERVICE = "aeac4a03-dff5-498f-843a-34487cf133eb"
PROFILE_PATH = "/org/dotfiles/relay/earbuds"

CMD_BATTERY = 0xC007
REPLY_BATTERY = 0x4007
PUSH_BATTERY = 0xE001

PARTS = {0x02: "left", 0x03: "right", 0x04: "case"}

# Once a minute, in case a push is missed. The earbuds push changes
# themselves, so this is a backstop, not the source.
POLL_SECONDS = 60
# How long after the audio connects before asking for the data channel, and
# the ceiling for retrying it. Asking the moment Connected flips races the
# earbuds' own profile setup and comes back busy.
CONNECT_DELAY_MS = 1500
RETRY_MAX_SECONDS = 60


# ------------------------------------------------------------------ frames


def crc16(data):
    """CRC-16/MODBUS, which the earbuds append little-endian to each frame."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def encode(command, payload=b"", seq=0):
    """55 | 60 01 | command LE | length LE | seq | payload | crc LE."""
    head = bytes([0x55, 0x60, 0x01, command & 0xFF, command >> 8,
                  len(payload) & 0xFF, len(payload) >> 8, seq & 0xFF]) + payload
    crc = crc16(head)
    return head + bytes([crc & 0xFF, crc >> 8])


def frames(buf):
    """Splits complete frames off the front of buf.

    Returns ([(command, payload)], rest). Bytes before a start-of-frame, and
    frames whose CRC does not match, are dropped: RFCOMM delivers a stream,
    and one bad byte should cost one frame, not the connection.
    """
    out = []
    while True:
        start = buf.find(b"\x55")
        if start < 0:
            return out, b""
        buf = buf[start:]
        if len(buf) < 8:
            return out, buf
        length = buf[5] | buf[6] << 8
        # Bit 5 of the first control byte says a CRC follows.
        has_crc = bool(buf[1] & 0x20)
        total = 8 + length + (2 if has_crc else 0)
        if len(buf) < total:
            return out, buf
        frame, buf = buf[:total], buf[total:]
        if has_crc and crc16(frame[:-2]) != (frame[-2] | frame[-1] << 8):
            # Not a frame after all; look for the next start byte.
            buf = frame[1:] + buf
            continue
        out.append((frame[3] | frame[4] << 8, frame[8:8 + length]))


def batteries(payload):
    """{"left": {"level", "charging"}, ...} for the parts this report has."""
    found = {}
    if not payload:
        return found
    count = payload[0]
    for i in range(count):
        at = 1 + i * 2
        if at + 1 >= len(payload):
            break
        part = PARTS.get(payload[at])
        if part:
            value = payload[at + 1]
            found[part] = {"level": value & 0x7F, "charging": bool(value & 0x80)}
    return found


# ------------------------------------------------------------------ state


class State:
    def __init__(self):
        self.name = None
        self.address = None
        self.parts = {}

    def connect(self, name, address):
        self.name = name
        self.address = address
        self.parts = {}

    def disconnect(self):
        self.name = None
        self.address = None
        self.parts = {}

    def report(self, found):
        for part in PARTS.values():
            if part in found:
                self.parts[part] = dict(found[part], stale=False)
            elif part in self.parts:
                self.parts[part]["stale"] = True

    def line(self):
        if self.name is None:
            return {"connected": False}
        out = {"connected": True, "name": self.name, "address": self.address}
        for part in PARTS.values():
            out[part] = self.parts.get(part)
        return out


def emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


# ------------------------------------------------------------------ watcher


def watch():
    import dbus
    import dbus.mainloop.glib
    import dbus.service
    from gi.repository import GLib
    try:
        from gi.repository import GLibUnix
        signal_add = GLibUnix.signal_add
    except ImportError:  # PyGObject before 3.50
        signal_add = GLib.unix_signal_add

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    loop = GLib.MainLoop()
    state = State()
    last = [None]
    status = [0]

    def publish():
        line = state.line()
        if line != last[0]:
            last[0] = line
            emit(line)

    def quit(code):
        status[0] = code
        loop.quit()

    # One Nothing device at a time: the first connected one that offers the
    # service. `current` is its object path, `link` the socket to it.
    current = {"path": None, "sock": None, "watch": None, "buf": b"",
               "retry": None, "delay": 1, "seq": 0}

    def device_props(path):
        obj = bus.get_object("org.bluez", path)
        return obj.GetAll("org.bluez.Device1", dbus_interface="org.freedesktop.DBus.Properties")

    def offers_service(props):
        return SERVICE in [str(u).lower() for u in props.get("UUIDs", [])]

    def send_request():
        sock = current["sock"]
        if sock is None:
            return False
        current["seq"] = (current["seq"] + 1) & 0xFF
        try:
            sock.send(encode(CMD_BATTERY, seq=current["seq"]))
        except OSError:
            close_link()
            schedule_connect()
        return True

    def close_link():
        if current["watch"] is not None:
            GLib.source_remove(current["watch"])
            current["watch"] = None
        if current["sock"] is not None:
            try:
                current["sock"].close()
            except OSError:
                pass
            current["sock"] = None
        current["buf"] = b""

    def forget_device():
        close_link()
        cancel_retry()
        current["path"] = None
        state.disconnect()
        publish()

    def cancel_retry():
        if current["retry"] is not None:
            GLib.source_remove(current["retry"])
            current["retry"] = None

    def schedule_connect(delay_ms=None):
        cancel_retry()
        if current["path"] is None:
            return
        if delay_ms is None:
            delay_ms = current["delay"] * 1000
            current["delay"] = min(current["delay"] * 2, RETRY_MAX_SECONDS)
        current["retry"] = GLib.timeout_add(delay_ms, connect_profile)

    def connect_profile():
        current["retry"] = None
        path = current["path"]
        if path is None or current["sock"] is not None:
            return False
        dev = dbus.Interface(bus.get_object("org.bluez", path), "org.bluez.Device1")

        def failed(err):
            name = err.get_dbus_name() if hasattr(err, "get_dbus_name") else ""
            # The link came up some other way (AutoConnect, a second call
            # racing this one); NewConnection has it or will.
            if name == "org.bluez.Error.AlreadyConnected":
                return
            print(f"earbuds: connecting {SERVICE} failed: {err}", file=sys.stderr, flush=True)
            schedule_connect()

        dev.ConnectProfile(SERVICE, reply_handler=lambda: None, error_handler=failed)
        return False

    def adopt(path, props):
        """A device connected (or was already); take it if it is ours."""
        if current["path"] is not None or not props.get("Connected") or not offers_service(props):
            return
        current["path"] = path
        current["delay"] = 1
        state.connect(str(props.get("Alias") or props.get("Name") or "Earbuds"),
                      str(props.get("Address", "")))
        publish()
        schedule_connect(CONNECT_DELAY_MS)

    def on_readable(fd, cond):
        sock = current["sock"]
        if sock is None:
            return False
        data = b""
        if cond & GLib.IO_IN:
            try:
                data = sock.recv(1024)
            except BlockingIOError:
                return True
            except OSError:
                data = b""
        if not data:
            # The earbuds closed the channel. If they are still connected
            # for audio, ask for it again; if not, the Connected change
            # below forgets them.
            current["watch"] = None
            close_link()
            schedule_connect()
            return False
        got, current["buf"] = frames(current["buf"] + data)
        for command, payload in got:
            if command in (REPLY_BATTERY, PUSH_BATTERY):
                state.report(batteries(payload))
                publish()
        return True

    class Profile(dbus.service.Object):
        @dbus.service.method("org.bluez.Profile1", in_signature="oha{sv}")
        def NewConnection(self, device, fd, props):
            fd = fd.take()
            if str(device) != current["path"] or current["sock"] is not None:
                os.close(fd)
                return
            sock = socket.socket(fileno=fd)
            sock.setblocking(False)
            current["sock"] = sock
            current["delay"] = 1
            current["watch"] = GLib.io_add_watch(
                sock.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_readable)
            send_request()

        @dbus.service.method("org.bluez.Profile1", in_signature="o")
        def RequestDisconnection(self, device):
            if str(device) == current["path"]:
                close_link()

        @dbus.service.method("org.bluez.Profile1")
        def Release(self):
            quit(1)

    def on_props(interface, changed, _invalidated, path=None):
        if interface != "org.bluez.Device1" or "Connected" not in changed:
            return
        if changed["Connected"]:
            try:
                adopt(path, device_props(path))
            except dbus.DBusException:
                pass
        elif path == current["path"]:
            forget_device()
            rescan()

    def on_removed(path, interfaces):
        if path == current["path"] and "org.bluez.Device1" in interfaces:
            forget_device()
            rescan()

    def rescan():
        manager = dbus.Interface(bus.get_object("org.bluez", "/"), "org.freedesktop.DBus.ObjectManager")
        for path, interfaces in manager.GetManagedObjects().items():
            if "org.bluez.Device1" in interfaces:
                adopt(str(path), interfaces["org.bluez.Device1"])

    def on_owner(name, _old, new):
        if name == "org.bluez" and not new:
            print("earbuds: bluetoothd went away", file=sys.stderr, flush=True)
            quit(1)

    def poll():
        send_request()
        return True

    Profile(bus, PROFILE_PATH)
    manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.ProfileManager1")
    try:
        manager.RegisterProfile(PROFILE_PATH, SERVICE, {
            "Name": "relay earbuds",
            "Role": "client",
            # Connected on purpose, by connect_profile, once audio is up.
            "AutoConnect": dbus.Boolean(False),
        })
    except dbus.DBusException as err:
        # BlueZ lets one process at a time register a UUID
        # (NotPermitted, "UUID already registered").
        if "already registered" in str(err):
            print("earbuds: another watcher already has the earbuds (is the shell running one?)",
                  file=sys.stderr, flush=True)
            return 3
        raise

    bus.add_signal_receiver(on_props, dbus_interface="org.freedesktop.DBus.Properties",
                            signal_name="PropertiesChanged", bus_name="org.bluez", path_keyword="path")
    bus.add_signal_receiver(on_removed, dbus_interface="org.freedesktop.DBus.ObjectManager",
                            signal_name="InterfacesRemoved", bus_name="org.bluez")
    bus.add_signal_receiver(on_owner, dbus_interface="org.freedesktop.DBus",
                            signal_name="NameOwnerChanged", arg0="org.bluez")
    GLib.timeout_add_seconds(POLL_SECONDS, poll)
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: quit(0) or False)

    rescan()
    publish()
    loop.run()

    close_link()
    try:
        manager.UnregisterProfile(PROFILE_PATH)
    except dbus.DBusException:
        pass
    return status[0]


def decode(hexstr):
    state = State()
    state.connect("test", "")
    got, rest = frames(bytes.fromhex(hexstr))
    for command, payload in got:
        if command in (REPLY_BATTERY, PUSH_BATTERY):
            state.report(batteries(payload))
    line = state.line()
    del line["connected"], line["name"], line["address"]
    line["frames"] = len(got)
    line["rest"] = rest.hex()
    emit(line)
    return 0


def main(argv):
    if argv[1:2] == ["decode"] and len(argv) == 3:
        return decode(argv[2])
    if argv[1:] == ["encode"]:
        print(encode(CMD_BATTERY, seq=1).hex())
        return 0
    if len(argv) == 1:
        try:
            return watch()
        except ImportError as err:
            print(f"earbuds: {err.name or err} is missing (pacman -S python-dbus python-gobject)",
                  file=sys.stderr)
            return 127
        except Exception as err:  # the D-Bus ones mostly: no system bus, no bluetoothd
            print(f"earbuds: {err}", file=sys.stderr)
            return 1
    print("usage: earbuds.py [decode <hex> | encode]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
