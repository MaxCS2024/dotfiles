#!/usr/bin/env python3
"""BlueZ pairing agent whose questions the shell answers.

Run through `relay bluetooth agent` (bluetooth.sh next door); the shell's
services/BtAgent.qml runs it for as long as it is up and shows each question
in network/BluetoothPrompt.qml. Without an agent BlueZ pairs as
NoInputNoOutput, so only "Just Works" devices pair at all: a keyboard that
wants a passkey typed, or a phone that wants six digits compared, is refused.

Registered as the default agent with KeyboardDisplay, the capability that
lets BlueZ pick whichever method the other side can do.

One JSON line out per event:

    {"event": "ready"}
    {"event": "prompt", "id": 3, "kind": "confirm", "address": "…",
     "name": "Pixel 8", "code": "048213"}
    {"event": "close", "id": 3}

kind is one of
    confirm          do these six digits match the device's?  yes / no
    authorize        the device asks to pair, no code          yes / no
    pin              type the PIN the device shows (or 0000)   text
    passkey          type the number the device shows          text
    display-passkey  type `code` on the device                 no answer
    display-pin      type `code` on the device                 no answer

A display prompt is sent again with "entered" (keys typed so far) as the
keyboard reports them, under the same id. "close" follows every prompt: the
answer went back, BlueZ cancelled it, or the device finished pairing.

One JSON line in per answer:

    {"id": 3, "accept": true, "value": "0000"}

value only for pin and passkey. An answer to an id that has closed is
ignored.

Services a device asks to use later (AuthorizeService) are allowed for
paired devices and refused for anyone else, without asking: by then the
question worth asking was the pairing.

Exit status: 0 on SIGTERM/SIGINT, 1 when BlueZ goes away or refuses the
agent (the shell starts this again).
"""

import json
import os
import signal
import sys

AGENT_PATH = "/org/dotfiles/relay/agent"
AGENT_IFACE = "org.bluez.Agent1"
CAPABILITY = "KeyboardDisplay"


def emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def agent():
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
    status = [0]

    def quit(code):
        status[0] = code
        loop.quit()

    class Rejected(dbus.DBusException):
        _dbus_error_name = "org.bluez.Error.Rejected"

    class Canceled(dbus.DBusException):
        _dbus_error_name = "org.bluez.Error.Canceled"

    # id -> {"device": path, "reply": fn or None, "error": fn or None,
    #        "kind": str}. Display prompts have no reply; they stay open
    # until the device pairs or BlueZ cancels.
    open_prompts = {}
    next_id = [1]

    def device_props(path):
        try:
            obj = bus.get_object("org.bluez", path)
            return obj.GetAll("org.bluez.Device1",
                              dbus_interface="org.freedesktop.DBus.Properties")
        except dbus.DBusException:
            return {}

    def describe(path):
        props = device_props(path)
        address = str(props.get("Address", ""))
        return address, str(props.get("Alias", address))

    def prompt(kind, device, code=None, reply=None, error=None, entered=None):
        device = str(device)
        # A keyboard reports each key typed as another DisplayPasskey for
        # the same device; that is the same prompt, not a new one.
        pid = None
        if kind.startswith("display-"):
            pid = next((i for i, p in open_prompts.items()
                        if p["device"] == device and p["kind"] == kind), None)
        if pid is None:
            pid = next_id[0]
            next_id[0] += 1
            open_prompts[pid] = {"device": device, "kind": kind,
                                 "reply": reply, "error": error}
        address, name = describe(device)
        line = {"event": "prompt", "id": pid, "kind": kind,
                "address": address, "name": name}
        if code is not None:
            line["code"] = code
        if entered is not None:
            line["entered"] = int(entered)
        emit(line)

    def close(pid):
        if open_prompts.pop(pid, None) is not None:
            emit({"event": "close", "id": pid})

    def close_device(device):
        for pid in [i for i, p in open_prompts.items() if p["device"] == device]:
            close(pid)

    def answer(line):
        try:
            msg = json.loads(line)
            pid = int(msg["id"])
        except (ValueError, KeyError, TypeError):
            print(f"bluetooth-agent: unreadable answer: {line!r}", file=sys.stderr, flush=True)
            return
        p = open_prompts.get(pid)
        if p is None:
            return
        if p["reply"] is None:
            # A display prompt dismissed from the shell: nothing to tell
            # BlueZ, the device side decides.
            close(pid)
            return
        if not msg.get("accept"):
            p["error"](Rejected("Rejected by user"))
        elif p["kind"] == "pin":
            p["reply"](dbus.String(str(msg.get("value", ""))))
        elif p["kind"] == "passkey":
            try:
                p["reply"](dbus.UInt32(int(str(msg.get("value", "")).strip())))
            except ValueError:
                p["error"](Rejected("Not a number"))
        else:
            p["reply"]()
        close(pid)

    class Agent(dbus.service.Object):
        @dbus.service.method(AGENT_IFACE)
        def Release(self):
            quit(1)

        @dbus.service.method(AGENT_IFACE, in_signature="os")
        def AuthorizeService(self, device, uuid):
            if not device_props(device).get("Paired", False):
                raise Rejected("Not paired")

        @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="s",
                             async_callbacks=("reply", "error"))
        def RequestPinCode(self, device, reply, error):
            prompt("pin", device, reply=reply, error=error)

        @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="u",
                             async_callbacks=("reply", "error"))
        def RequestPasskey(self, device, reply, error):
            prompt("passkey", device, reply=reply, error=error)

        @dbus.service.method(AGENT_IFACE, in_signature="ouq")
        def DisplayPasskey(self, device, passkey, entered):
            prompt("display-passkey", device, code=f"{int(passkey):06d}", entered=entered)

        @dbus.service.method(AGENT_IFACE, in_signature="os")
        def DisplayPinCode(self, device, pincode):
            prompt("display-pin", device, code=str(pincode))

        @dbus.service.method(AGENT_IFACE, in_signature="ou",
                             async_callbacks=("reply", "error"))
        def RequestConfirmation(self, device, passkey, reply, error):
            prompt("confirm", device, code=f"{int(passkey):06d}", reply=reply, error=error)

        @dbus.service.method(AGENT_IFACE, in_signature="o",
                             async_callbacks=("reply", "error"))
        def RequestAuthorization(self, device, reply, error):
            prompt("authorize", device, reply=reply, error=error)

        # BlueZ gave up on whatever it last asked: timed out, or the other
        # side walked away. It doesn't say which request, so all of them.
        @dbus.service.method(AGENT_IFACE)
        def Cancel(self):
            for pid in list(open_prompts):
                p = open_prompts[pid]
                if p["error"] is not None:
                    p["error"](Canceled("Canceled"))
                close(pid)

    # A display prompt has no reply to close it; the device pairing (or
    # vanishing) is what ends it.
    def on_props(interface, changed, _invalidated, path=None):
        if interface == "org.bluez.Device1" and changed.get("Paired", False):
            close_device(str(path))

    def on_removed(path, interfaces):
        if "org.bluez.Device1" in interfaces:
            close_device(str(path))

    def on_owner(name, _old, new):
        if name == "org.bluez" and not new:
            print("bluetooth-agent: bluetoothd went away", file=sys.stderr, flush=True)
            quit(1)

    # Read from the fd directly: sys.stdin buffers, and a second answer
    # sitting in its buffer would never wake the watch again.
    pending = [b""]

    def on_stdin(fd, cond):
        chunk = os.read(fd, 4096) if cond & GLib.IO_IN else b""
        if not chunk:
            # The shell is gone; nobody is left to answer.
            quit(0)
            return False
        pending[0] += chunk
        *lines, pending[0] = pending[0].split(b"\n")
        for line in lines:
            if line.strip():
                answer(line.decode("utf-8", "replace"))
        return True

    Agent(bus, AGENT_PATH)
    manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.AgentManager1")
    try:
        manager.RegisterAgent(AGENT_PATH, CAPABILITY)
        manager.RequestDefaultAgent(AGENT_PATH)
    except dbus.DBusException as err:
        print(f"bluetooth-agent: registering with BlueZ failed: {err}", file=sys.stderr, flush=True)
        return 1

    bus.add_signal_receiver(on_props, dbus_interface="org.freedesktop.DBus.Properties",
                            signal_name="PropertiesChanged", bus_name="org.bluez", path_keyword="path")
    bus.add_signal_receiver(on_removed, dbus_interface="org.freedesktop.DBus.ObjectManager",
                            signal_name="InterfacesRemoved", bus_name="org.bluez")
    bus.add_signal_receiver(on_owner, dbus_interface="org.freedesktop.DBus",
                            signal_name="NameOwnerChanged", arg0="org.bluez")
    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: quit(0) or False)

    emit({"event": "ready"})
    loop.run()

    for pid in list(open_prompts):
        p = open_prompts[pid]
        if p["error"] is not None:
            p["error"](Canceled("Agent stopped"))
        close(pid)
    try:
        manager.UnregisterAgent(AGENT_PATH)
    except dbus.DBusException:
        pass
    return status[0]


if __name__ == "__main__":
    try:
        import dbus  # noqa: F401
        import gi  # noqa: F401
    except ImportError as err:
        print(f"bluetooth-agent: {err} (needs python-dbus and python-gobject)",
              file=sys.stderr, flush=True)
        sys.exit(127)
    try:
        sys.exit(agent())
    except KeyboardInterrupt:
        sys.exit(0)
