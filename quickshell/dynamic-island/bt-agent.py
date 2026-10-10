#!/usr/bin/env python3
# A BlueZ pairing agent for the settings window's Bluetooth section
# (AGENTS.md, Settings window › Bluetooth). Quickshell can't be one, so
# the window runs this while the section is open and talks to it in JSON
# lines:
#
#   out  {"type": "ready"}
#        {"type": "confirm", "device": name, "passkey": "123456"}  answer yes/no
#        {"type": "authorize", "device": name}                     answer yes/no
#        {"type": "pin", "device": name}                           answer the PIN
#        {"type": "passkey", "device": name}                       answer digits
#        {"type": "display", "device": name, "passkey": "123456"}  type it there
#        {"type": "cancel"}                                        drop the prompt
#        {"type": "error", "message": text}
#   in   one line per question, in order: "yes", "no", or the code; an
#        empty line refuses.
#
# KeyboardDisplay, so BlueZ picks whichever exchange the device needs.
# Services of an already paired device are allowed without asking.

import json
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

AGENT_PATH = "/org/quickshell/island/agent"


def say(**message):
    print(json.dumps(message), flush=True)


class Rejected(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Rejected"


class Canceled(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Canceled"


class Agent(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, AGENT_PATH)
        self.bus = bus
        # The question waiting for its answer: (kind, reply, error).
        self.waiting = None

    def name(self, path):
        try:
            props = dbus.Interface(self.bus.get_object("org.bluez", path), "org.freedesktop.DBus.Properties")
            return str(props.Get("org.bluez.Device1", "Alias"))
        except dbus.DBusException:
            return str(path).rsplit("/", 1)[-1]

    def ask(self, kind, reply, error, **fields):
        if self.waiting:
            self.waiting[2](Canceled("Another request is waiting"))
        self.waiting = (kind, reply, error)
        say(type=kind, **fields)

    def answer(self, line):
        if not self.waiting:
            return
        kind, reply, error = self.waiting
        self.waiting = None
        line = line.strip()
        if kind in ("confirm", "authorize"):
            reply() if line == "yes" else error(Rejected("Refused"))
        elif kind == "pin":
            reply(line) if line else error(Rejected("No PIN"))
        elif kind == "passkey":
            reply(dbus.UInt32(int(line))) if line.isdigit() else error(Rejected("No passkey"))

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Release(self):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="s",
                         async_callbacks=("reply", "error"))
    def RequestPinCode(self, device, reply, error):
        self.ask("pin", reply, error, device=self.name(device))

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="u",
                         async_callbacks=("reply", "error"))
    def RequestPasskey(self, device, reply, error):
        self.ask("passkey", reply, error, device=self.name(device))

    @dbus.service.method("org.bluez.Agent1", in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        say(type="display", device=self.name(device), passkey="%06d" % passkey)

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        say(type="display", device=self.name(device), passkey=str(pincode))

    @dbus.service.method("org.bluez.Agent1", in_signature="ou", out_signature="",
                         async_callbacks=("reply", "error"))
    def RequestConfirmation(self, device, passkey, reply, error):
        self.ask("confirm", reply, error, device=self.name(device), passkey="%06d" % passkey)

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="",
                         async_callbacks=("reply", "error"))
    def RequestAuthorization(self, device, reply, error):
        self.ask("authorize", reply, error, device=self.name(device))

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Cancel(self):
        self.waiting = None
        say(type="cancel")


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    agent = Agent(bus)
    manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.AgentManager1")
    try:
        manager.RegisterAgent(AGENT_PATH, "KeyboardDisplay")
        manager.RequestDefaultAgent(AGENT_PATH)
    except dbus.DBusException as e:
        say(type="error", message=e.get_dbus_message() or str(e))
        return 1

    loop = GLib.MainLoop()

    def on_input(source, condition):
        line = sys.stdin.readline()
        if not line:  # the window closed the pipe: done
            loop.quit()
            return False
        agent.answer(line)
        return True

    GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP, on_input)
    say(type="ready")
    try:
        loop.run()
    finally:
        try:
            manager.UnregisterAgent(AGENT_PATH)
        except dbus.DBusException:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
