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
                self.agent_owner = str(name)
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
agent.GetSecrets(settings, dbus.ObjectPath('/org/freedesktop/NetworkManager/Settings/1'),
                 '802-11-wireless-security', dbus.Array([], signature='s'), dbus.UInt32(1),
                 reply_handler=lambda secrets: setattr(self, 'captured_secret', str(secrets['802-11-wireless-security']['psk'])),
                 error_handler=lambda error: setattr(self, 'captured_error', str(error)))
'''
        self.mock.AddMethod(dbusmock.MOCK_IFACE, 'RequestSecret', '', '', request)
        self.mock.AddMethod(dbusmock.MOCK_IFACE, 'CapturedSecret', '', 'ss',
                            "ret = (getattr(self, 'captured_secret', ''), getattr(self, 'captured_error', ''))")

    def env(self, secret):
        # The secret is fictitious and placed in the test driver's environment only.
        # Production does not use an environment variable to transfer credentials.
        return dict(os.environ, TEST_WIFI_SECRET=secret, LC_ALL='C', WIFI_PROBE_DEBUG='1')

    def assert_probe(self, text):
        result = json.loads(text)
        self.assertEqual(result['writes'], 1)
        self.assertTrue(result['secretCleared'])
        for name in ['argvHasSecret', 'cmdlineHasSecret', 'outputHasSecret']:
            self.assertFalse(result[name], name)
        return result

    def test_wifi_connect_actual_nmcli_receives_exact_secret_without_argv_or_echo(self):
        secret = '  quote"$`\\test  '
        r = subprocess.run(['node', str(ROOT / 'tests/wifi-nmcli-probe.mjs')],
                           env=self.env(secret), capture_output=True, text=True, timeout=15, check=True)
        self.assertEqual(self.assert_probe(r.stdout)['code'], 0)
        calls = self.manager_mock.GetMethodCalls('AddAndActivateConnection')
        self.assertEqual(len(calls), 1)
        self.assertEqual(str(calls[0][1][0]['802-11-wireless-security']['psk']), secret)

    def test_secret_agent_actual_nmcli_replaces_prefill_and_returns_exact_secret(self):
        secret = '  replacement"$`\\test  '
        p = subprocess.Popen(['node', str(ROOT / 'tests/wifi-nmcli-probe.mjs'), '--agent'],
                             env=self.env(secret), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: p.kill() if p.poll() is None else None)
        until = time.monotonic() + 5
        while not self.mock.AgentOwner():
            if time.monotonic() >= until:
                p.kill(); out, err = p.communicate(timeout=5)
                agents = dbus.Interface(self.bus.get_object(MANAGER, AGENTS), dbusmock.MOCK_IFACE)
                self.fail('SecretAgent registration timed out: ' + str(agents.GetCalls()) + ' / ' + out + ' / ' + err)
            time.sleep(.02)
        self.mock.RequestSecret()
        out, err = p.communicate(timeout=15)
        self.assertEqual(p.returncode, 0, err)
        self.assert_probe(out)
        captured, error = self.mock.CapturedSecret()
        self.assertEqual(str(error), '')
        self.assertEqual(str(captured), secret)


if __name__ == '__main__':
    unittest.main(verbosity=2)
