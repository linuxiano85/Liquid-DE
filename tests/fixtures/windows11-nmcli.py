#!/usr/bin/env python3
"""nmcli sintetico per il solo bus/compositore privato delle prove QML."""
import fcntl
import json
import os
import sys
from pathlib import Path

assert os.environ.get('LIQUID_TEST_BUS') == '1'
assert os.environ.get('MINERVA_PROVA') == '1'
state_file = Path(os.environ['MINERVA_WIFI_FIXTURE_STATE'])
assert str(state_file).startswith('/tmp/minerva-tiling-windows11-')
args = sys.argv[1:]
secret_marker = b'audit-test-password'
log = state_file.with_name('wifi-actions.json')
def record(extra=None):
    with open(str(log) + '.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        entries = json.loads(log.read_text()) if log.exists() else []
        row = {'argv': args,
               'secret_in_argv': secret_marker in Path('/proc/self/cmdline').read_bytes(),
               'secret_in_environment': secret_marker in Path('/proc/self/environ').read_bytes()}
        if extra:
            row.update(extra)
        entries.append(row)
        log.write_text(json.dumps(entries))

def escape(text):
    return text.replace('\\', '\\\\').replace(':', '\\:')

state = json.loads(state_file.read_text())
record()
if args == ['radio', 'wifi']:
    print('enabled' if state['radio'] else 'disabled')
elif 'device' in args and 'status' in args:
    if 'DEVICE,TYPE' in args:
        print('wlan_test:wifi')
    else:
        print('wifi:' + ('connected:' + escape(state['selected']) if state['selected'] else 'disconnected:'))
elif 'device' in args and 'wifi' in args and 'list' in args:
    if state['radio']:
        for ssid, strength, protected in state['networks']:
            print(':'.join([escape(ssid), str(strength), 'WPA2' if protected else '--', '*' if state['selected'] == ssid else '']))
elif 'device' in args and 'wifi' in args and 'rescan' in args:
    pass
elif 'device' in args and 'disconnect' in args:
    state['selected'] = ''
    state_file.write_text(json.dumps(state))
elif 'connection' in args and 'show' in args:
    if '802-11-wireless.ssid' in args:
        print('Rete salvata')
    else:
        print('12345678-abcd-1234-abcd-123456789012:wifi')
elif ('wifi' in args and 'connect' in args) or ('connection' in args and 'up' in args):
    ssid = 'Rete salvata' if 'uuid' in args else args[args.index('connect') + 1]
    protected = any(row[0] == ssid and row[2] for row in state['networks'])
    if ssid not in [row[0] for row in state['networks']]:
        print('No network with SSID', file=sys.stderr)
        sys.exit(10)
    if protected and ssid != 'Rete salvata':
        if '--ask' not in args:
            print('Secrets were required, but not provided', file=sys.stderr)
            sys.exit(4)
        print('Password: ', end='', flush=True)
        secret = sys.stdin.readline().rstrip('\r\n').removeprefix('\x15')
        record({'stdin_received': True, 'secret_matches': secret == 'audit-test-password'})
        if secret != 'audit-test-password':
            print('Password was not accepted', file=sys.stderr)
            sys.exit(4)
    state['selected'] = ssid
    state_file.write_text(json.dumps(state))
else:
    print('Comando della fixture non supportato', file=sys.stderr)
    sys.exit(7)
