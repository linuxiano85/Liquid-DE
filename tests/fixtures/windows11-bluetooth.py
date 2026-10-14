#!/usr/bin/env python3
"""BlueZ privato: il modulo nativo QML usa D-Bus, senza radio fisiche."""
import json
import os
import sys
from pathlib import Path
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

assert os.environ.get('LIQUID_TEST_BUS') == '1'
assert os.environ['DBUS_SYSTEM_BUS_ADDRESS'] == os.environ['DBUS_SESSION_BUS_ADDRESS']
DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
if sys.argv[1] == 'control':
    control = dbus.Interface(bus.get_object('org.bluez', '/test'), 'org.liquid.TestBluetooth')
    control.Command(sys.argv[2])
    sys.exit(0)

output = Path(sys.argv[1])
actions = []
objects = {}
fail_next = False

def record(action):
    actions.append(action)
    output.write_text(json.dumps(actions))

class Properties(dbus.service.Object):
    def __init__(self, path, interfaces):
        self.path = path
        self.interfaces = interfaces
        super().__init__(bus, path)
        objects[path] = self

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        return self.interfaces.get(interface, {})

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
    def Get(self, interface, key):
        return self.interfaces[interface][key]

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ssv')
    def Set(self, interface, key, value):
        self.interfaces[interface][key] = value
        self.PropertiesChanged(interface, {key: value}, [])
        record({'action': 'set', 'path': self.path, 'key': str(key), 'value': bool(value)})

    @dbus.service.signal('org.freedesktop.DBus.Properties', signature='sa{sv}as')
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

class Adapter(Properties):
    def __init__(self, number):
        super().__init__('/org/bluez/hci' + str(number), {'org.bluez.Adapter1': {
            'Address': '00:11:22:33:44:' + str(number) * 2,
            'Name': 'Radio demo ' + str(number), 'Alias': 'Radio demo ' + str(number),
            'Powered': dbus.Boolean(True), 'Discovering': dbus.Boolean(False),
            'Discoverable': dbus.Boolean(False), 'DiscoverableTimeout': dbus.UInt32(180),
            'Pairable': dbus.Boolean(True), 'PairableTimeout': dbus.UInt32(0),
            'Class': dbus.UInt32(0), 'UUIDs': dbus.Array([], signature='s'),
        }})

class Device(Properties):
    def __init__(self, number, label, paired=True, connected=False, adapter=0, battery=-1):
        path = '/org/bluez/hci' + str(adapter) + '/dev_00_00_00_00_00_' + str(number).zfill(2)
        properties = {'Address': '00:00:00:00:00:' + str(number).zfill(2),
            'Name': label, 'Alias': label, 'Paired': dbus.Boolean(paired),
            'Bonded': dbus.Boolean(paired), 'Connected': dbus.Boolean(connected),
            'Trusted': dbus.Boolean(paired), 'Blocked': dbus.Boolean(False),
            'WakeAllowed': dbus.Boolean(False), 'Icon': 'audio-headset',
            'Adapter': dbus.ObjectPath('/org/bluez/hci' + str(adapter)),
            'UUIDs': dbus.Array([], signature='s'), 'ServicesResolved': dbus.Boolean(connected)}
        interfaces = {'org.bluez.Device1': properties}
        if battery >= 0:
            interfaces['org.bluez.Battery1'] = {'Percentage': dbus.Byte(battery)}
        super().__init__(path, interfaces)

    @dbus.service.method('org.bluez.Device1', async_callbacks=('reply', 'error'))
    def Connect(self, reply, error):
        global fail_next
        record({'action': 'connect', 'path': self.path})
        fail = fail_next
        fail_next = False
        def finish():
            if fail:
                error(dbus.exceptions.DBusException('Connessione simulata fallita', name='org.bluez.Error.Failed'))
            else:
                self.interfaces['org.bluez.Device1']['Connected'] = dbus.Boolean(True)
                self.PropertiesChanged('org.bluez.Device1', {'Connected': dbus.Boolean(True)}, [])
                reply()
            return False
        GLib.timeout_add(250, finish)

    @dbus.service.method('org.bluez.Device1')
    def Disconnect(self):
        record({'action': 'disconnect', 'path': self.path})
        self.interfaces['org.bluez.Device1']['Connected'] = dbus.Boolean(False)
        self.PropertiesChanged('org.bluez.Device1', {'Connected': dbus.Boolean(False)}, [])

class Manager(dbus.service.Object):
    def __init__(self):
        super().__init__(bus, '/')
    @dbus.service.method('org.freedesktop.DBus.ObjectManager', out_signature='a{oa{sa{sv}}}')
    def GetManagedObjects(self):
        return {path: obj.interfaces for path, obj in objects.items()}
    @dbus.service.signal('org.freedesktop.DBus.ObjectManager', signature='oa{sa{sv}}')
    def InterfacesAdded(self, path, interfaces):
        pass
    @dbus.service.signal('org.freedesktop.DBus.ObjectManager', signature='oas')
    def InterfacesRemoved(self, path, interfaces):
        pass

class Control(dbus.service.Object):
    def __init__(self):
        super().__init__(bus, '/test')
    @dbus.service.method('org.liquid.TestBluetooth', in_signature='s')
    def Command(self, message):
        global fail_next
        values = json.loads(message)
        if values['action'] == 'fail':
            fail_next = True
        elif values['action'] == 'mutate':
            obj = objects[values['path']]
            interface = values.get('interface', 'org.bluez.Device1')
            changed = values['values']
            if interface == 'org.bluez.Battery1' and 'Percentage' in changed:
                changed['Percentage'] = dbus.Byte(changed['Percentage'])
            obj.interfaces[interface].update(changed)
            obj.PropertiesChanged(interface, changed, [])
        elif values['action'] == 'remove':
            obj = objects.pop(values['path'])
            manager.InterfacesRemoved(obj.path, list(obj.interfaces))
            obj.remove_from_connection()
        elif values['action'] == 'many':
            for number in range(10, 30):
                obj = Device(number, 'Accessorio ' + str(number))
                manager.InterfacesAdded(obj.path, obj.interfaces)

name = dbus.service.BusName('org.bluez', bus)
manager = Manager()
control = Control()
Adapter(0)
Adapter(1)
Device(1, 'Cuffie demo', battery=80)
Device(2, 'Controller demo', connected=True, battery=65)
Device(3, 'Dispositivo non associato', paired=False)
Device(1, 'Cuffie seconda radio', adapter=1)
record({'action': 'ready'})
print('READY', flush=True)
GLib.MainLoop().run()
