#!/usr/bin/env python3
"""Real nmcli/readline/SecretAgent on a private bus. No host NM or radio changes."""
import json
import os
from pathlib import Path
import subprocess
import time
import unittest

import dbus
import dbusmock

ROOT = Path(__file__).resolve().parents[1]
MANAGER = 'org.freedesktop.NetworkManager'
OBJ = '/org/freedesktop/NetworkManager'
AGENTS = OBJ + '/AgentManager'


class NmcliPipeTests(dbusmock.DBusTestCase):
    @classmethod
    def setUpClass(cls):
        cls.start_system_bus()
        cls.bus = cls.get_dbus(True)
        print(subprocess.check_output(['nmcli', '--version'], text=True).strip(), flush=True)

    def setUp(self):
        self.server, self.obj = self.spawn_server_template('networkmanager', {}, stdout=subprocess.DEVNULL)
        self.addCleanup(self.server.wait)
        self.addCleanup(self.server.terminate)
        self.mock = dbus.Interface(self.obj, dbusmock.MOCK_IFACE)
        self.manager_mock = dbus.Interface(self.bus.get_object(MANAGER, OBJ), dbusmock.MOCK_IFACE)
        # Il template dichiara NM 0.9.6: libnm recente imbocca il ramo legacy
        # e attende indefinitamente. La fixture espone la versione del client.
        version = subprocess.check_output(['nmcli', '--version'], env=dict(os.environ, LC_ALL='C'), text=True).split('version', 1)[1].strip().split('-')[0]
        self.manager_mock.UpdateProperties(MANAGER, {'Version': dbus.String(version)})
        dev = self.mock.AddWiFiDevice('mock_WiFi', 'wlan_test', 30)
        self.mock.AddAccessPoint(dev, 'Test_AP', 'Audit_Test_AP', '02:00:00:00:00:01',
                                 2, 2425, 5400, 80, 0x100)
        # Registration and GetSecrets must use the mock's own NM bus owner.
        # Find the unique nmcli connection by its real PID, only on this private bus.
        register = '''
import os
bus = dbus.SystemBus()
daemon = dbus.Interface(bus.get_object('org.freedesktop.DBus', '/org/freedesktop/DBus'), 'org.freedesktop.DBus')
for name in daemon.ListNames():
    if str(name).startswith(':'):
        pid = daemon.GetConnectionUnixProcessID(name)
        try:
            with open('/proc/%d/cmdline' % pid, 'rb') as f:
                command = f.read().split(b'\\0')[0]
            if command.endswith(b'/nmcli') or command == b'nmcli':
                try:
                    xml = dbus.Interface(bus.get_object(name, '/org/freedesktop/NetworkManager/SecretAgent'),
                                         'org.freedesktop.DBus.Introspectable').Introspect(timeout=1)
                    if 'org.freedesktop.NetworkManager.SecretAgent' in str(xml):
                        self.agent_owner = str(name)
                except dbus.DBusException:
                    pass
        except OSError:
            pass
'''
        self.mock.AddObject(AGENTS, MANAGER + '.AgentManager', {}, [
            ('Register', 's', '', register), ('RegisterWithCapabilities', 'su', '', register),
            ('Unregister', '', '', '')])
        self.mock.AddMethod(dbusmock.MOCK_IFACE, 'AgentOwner', '', 's',
                            "ret = getattr(objects['" + AGENTS + "'], 'agent_owner', '')")
        request = '''
owner = getattr(objects['/org/freedesktop/NetworkManager/AgentManager'], 'agent_owner', '')
agent = dbus.Interface(dbus.SystemBus().get_object(owner, '/org/freedesktop/NetworkManager/SecretAgent'),
                       'org.freedesktop.NetworkManager.SecretAgent')
settings = dbus.Dictionary({
 'connection': dbus.Dictionary({'id': dbus.String('Audit_Test_AP'), 'type': dbus.String('802-11-wireless'),
                               'uuid': dbus.String('14a90ad6-4611-4c14-a570-5590469f3193')}, signature='sv'),
 '802-11-wireless': dbus.Dictionary({'ssid': dbus.ByteArray(b'Audit_Test_AP')}, signature='sv'),
 '802-11-wireless-security': dbus.Dictionary({'key-mgmt': dbus.String('wpa-psk'),
                                            'psk': dbus.String('old-prefill')}, signature='sv')
}, signature='sa{sv}')
agent.GetSecrets(settings, dbus.ObjectPath(getattr(self, 'test_connection_path', '/org/freedesktop/NetworkManager/Settings/1')),
                 '802-11-wireless-security', dbus.Array([], signature='s'), dbus.UInt32(1),
                 reply_handler=lambda secrets, target=self: setattr(target, 'captured_secret', str(secrets['802-11-wireless-security']['psk'])),
                 error_handler=lambda error, target=self: setattr(target, 'captured_error', str(error)))
'''
        self.mock.AddMethod(dbusmock.MOCK_IFACE, 'RequestSecret', '', '', request)
        self.mock.AddMethod(dbusmock.MOCK_IFACE, 'CapturedSecret', '', 'ss',
                            "ret = (getattr(self, 'captured_secret', ''), getattr(self, 'captured_error', ''))")
        # Il template di default accetta WPA senza chiedere segreti: qui si
        # riproduce il passo SecretAgent che compie NetworkManager reale.
        activate_with_secret = """
from gi.repository import GLib
owner = getattr(objects['/org/freedesktop/NetworkManager/AgentManager'], 'agent_owner', '')
settings = args[0]
settings['802-11-wireless-security'] = dbus.Dictionary({'key-mgmt': dbus.String('wpa-psk')}, signature='sv')
ret = self.add_and_activate_connection(self, settings, args[1], args[2])
settings = objects[str(ret[0])].settings
settings['802-11-wireless-security'] = dbus.Dictionary({'key-mgmt': dbus.String('wpa-psk')}, signature='sv')
active = objects[str(ret[1])]
active.UpdateProperties('org.freedesktop.NetworkManager.Connection.Active', {'State': dbus.UInt32(1)})
def request(target=self, settings=settings, owner=owner, connection=str(ret[0]), active=active):
    agent = dbus.Interface(dbus.SystemBus().get_object(owner, '/org/freedesktop/NetworkManager/SecretAgent'),
                           'org.freedesktop.NetworkManager.SecretAgent')
    def done(secrets, target=target, active=active):
        target.captured_new_secret = str(secrets['802-11-wireless-security']['psk'])
        active.UpdateProperties('org.freedesktop.NetworkManager.Connection.Active', {'State': dbus.UInt32(2)})
    agent.GetSecrets(settings, dbus.ObjectPath(connection), '802-11-wireless-security',
                     dbus.Array([], signature='s'), dbus.UInt32(1), reply_handler=done,
                     error_handler=lambda error, target=target: setattr(target, 'captured_new_error', str(error)))
    return False
GLib.timeout_add(150, request)
"""
        self.manager_mock.AddMethod(MANAGER, 'AddAndActivateConnection', 'a{sa{sv}}oo', 'oo', activate_with_secret)
        self.manager_mock.AddMethod(dbusmock.MOCK_IFACE, 'CapturedNewSecret', '', 's',
                                    "ret = getattr(self, 'captured_new_secret', '')")
        self.manager_mock.AddMethod(dbusmock.MOCK_IFACE, 'CapturedNewError', '', 's',
                                    "ret = getattr(self, 'captured_new_error', '')")


    def env(self, secret):
        # The secret is fictitious and placed in the test driver's environment only.
        # Production does not use an environment variable to transfer credentials.
        return dict(os.environ, TEST_WIFI_SECRET=secret, LC_ALL='C', WIFI_PROBE_DEBUG='1', LIBNM_USE_SESSION_BUS='1', DBUS_SESSION_BUS_ADDRESS=os.environ['DBUS_SYSTEM_BUS_ADDRESS'])

    def assert_probe(self, text):
        result = json.loads(text)
        self.assertEqual(result['writes'], 1, str(result))
        self.assertTrue(result['secretCleared'])
        for name in ['argvHasSecret', 'cmdlineHasSecret', 'envHasSecret', 'outputHasSecret']:
            self.assertFalse(result[name], name)
        return result

    def test_wifi_connect_actual_nmcli_receives_exact_secret_without_argv_or_echo(self):
        secret = '  quote"$`\\test  '
        r = subprocess.run(['node', str(ROOT / 'tests/wifi-nmcli-probe.mjs')],
                           env=self.env(secret), capture_output=True, text=True, timeout=15, check=True)
        if json.loads(r.stdout)['writes'] != 1:
            print('Errore SecretAgent nuovo profilo:', self.manager_mock.CapturedNewError(), flush=True)
        self.assertEqual(self.assert_probe(r.stdout)['code'], 0)
        calls = self.manager_mock.GetMethodCalls('AddAndActivateConnection')
        self.assertEqual(len(calls), 1)
        self.assertEqual(str(self.manager_mock.CapturedNewSecret()), secret)

    def test_secret_agent_actual_nmcli_replaces_prefill_and_returns_exact_secret(self):
        secret = '  replacement"$`\\test  '
        dev = '/org/freedesktop/NetworkManager/Devices/mock_WiFi'
        conn = self.mock.AddWiFiConnection(dev, 'Existing', 'Audit_Test_AP', 'wpa-psk')
        profile = dbus.Interface(self.bus.get_object(MANAGER, conn), MANAGER + '.Settings.Connection')
        settings = profile.GetSettings()
        settings['802-11-wireless'] = dbus.Dictionary({
            'ssid': dbus.ByteArray(b'Audit_Test_AP'), 'mode': dbus.String('infrastructure')}, signature='sv')
        settings['802-11-wireless-security'] = dbus.Dictionary({
            'key-mgmt': dbus.String('wpa-psk'), 'psk': dbus.String('old-prefill')}, signature='sv')
        profile.Update(settings)
        connection_mock = dbus.Interface(self.bus.get_object(MANAGER, conn), dbusmock.MOCK_IFACE)
        connection_mock.AddMethod(MANAGER + '.Settings.Connection', 'Update2', 'a{sa{sv}}ua{sv}', 'a{sv}',
                                  "self.ConnectionUpdate(self, args[0]); ret = dbus.Dictionary({}, signature='sv')")
        # Hold activation in progress. The test server, as the real NM owner,
        # asks the client's production SecretAgent after its enable callback.
        self.manager_mock.AddMethod(MANAGER, 'ActivateConnection', 'ooo', 'o', """
connection = '/org/freedesktop/NetworkManager/Settings/Existing'
ret = self.activate_connection(self, connection, args[1], args[2])
objects[ret].Set('org.freedesktop.NetworkManager.Connection.Active', 'State', dbus.UInt32(1))
objects['/org/freedesktop'].test_connection_path = connection
""")
        p = subprocess.Popen(['node', str(ROOT / 'tests/wifi-nmcli-probe.mjs'), '--agent'],
                             env=self.env(secret), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: p.kill() if p.poll() is None else None)
        until = time.monotonic() + 5
        while not self.mock.AgentOwner() or not self.manager_mock.GetMethodCalls('ActivateConnection'):
            if time.monotonic() >= until:
                p.kill(); out, err = p.communicate(timeout=5)
                agents = dbus.Interface(self.bus.get_object(MANAGER, AGENTS), dbusmock.MOCK_IFACE)
                self.fail('SecretAgent registration timed out: ' + str(agents.GetCalls()) + ' / manager calls: ' + str([call[1] for call in self.manager_mock.GetCalls()]) + ' / ' + out + ' / ' + err)
            time.sleep(.02)
        self.mock.RequestSecret()
        out, err = p.communicate(timeout=15)
        self.assertEqual(p.returncode, 0, err)
        captured, error = self.mock.CapturedSecret()
        self.assertEqual(str(error), '', out)
        self.assert_probe(out)
        self.assertEqual(str(captured), secret)


if __name__ == '__main__':
    unittest.main(verbosity=2)
