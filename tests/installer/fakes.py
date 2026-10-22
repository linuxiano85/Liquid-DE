# Command doubles for the installer regression suite; never run real sudo.
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent


def put(path, text='', executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o755 if executable else 0o644)


def dispatch(command, args):
    case = Path(os.environ['AUDIT_CASE'])
    config = json.loads((case / 'config.json').read_text())
    root = case / 'source'
    prefix = Path(os.environ['LIQUID_PREFISSO'])
    fault = config.get('fault', '')
    with (case / 'trace.jsonl').open('a') as f:
        f.write(json.dumps({'command': command, 'args': args, 'cwd': os.getcwd()}) + '\n')

    def fail(label):
        print('SIMULATED_FAILURE: ' + label, file=sys.stderr)
        return 42

    def binary(path, name=''):
        if name == 'minerva-polkit' and fault == 'agent_registration':
            content = '#!/bin/sh\necho "SIMULATED: agent already registered" >&2\nexit 1\n'
        else:
            content = '#!/bin/sh\nexit 0\n'
        put(path, content, True)

    if command == 'sudo':
        if args and args[0] == '-A':
            args = args[1:]
        if not args:
            return fail('empty sudo')
        cmd, *tail = args
        name = Path(cmd).name
        if name in ('pacman', 'systemctl', 'udevadm'):
            return dispatch(name, tail)
        if name == 'minerva-greetd':
            return fail('greetd configuration') if fault == 'greetd' else 0
        if name in ('install', 'mv'):
            if fault == 'pam_install' and any(x == '/etc/pam.d/liquid-de' for x in tail):
                return fail('PAM install')
            mapped = [str(case / 'system' / x.lstrip('/'))
                      if x.startswith(('/usr/', '/etc/')) else x for x in tail]
            for item in mapped:
                if item.startswith(str(case / 'system')):
                    Path(item).parent.mkdir(parents=True, exist_ok=True)
            return subprocess.run(['/usr/bin/' + name, *mapped], check=False).returncode
        return fail('refused sudo command: ' + name)

    if command == 'pacman':
        if '-T' in args:
            if fault == 'package_db':
                return 1
            if fault == 'package_db_inconsistent':
                print('polkit')
                return 0
            missing = config.get('missing', [])
            if missing:
                print('\n'.join(missing))
                return 127
            return 0
        if '-S' in args and fault == 'package_install':
            return fail('package installation')
        if '-Q' in args:
            return 0
        if '-Si' in args:
            return 1
        return 0

    if command == 'meson':
        if args[0] == 'setup':
            paths = [x for x in args[1:] if not x.startswith('-')]
            build = Path(paths[0])
            source = Path(paths[1])
            if fault == 'compositor' and source.name == 'compositore':
                return fail('compositor configuration')
            put(build / 'meson-private/coredata.dat', 'fixture')
            put(build / 'build.ninja', str(source) + '/')
            return 0
        if '-C' in args:
            build = Path(args[args.index('-C') + 1])
            if args[0] == 'test':
                return fail('compositor tests') if fault == 'compositor_tests' else 0
            for name in ('minerva-wayland', 'minerva-cattura', 'minerva-pty', 'minerva-pam'):
                binary(build / name, name)
            return 0

    if command == 'ninja':
        build = Path(args[args.index('-C') + 1])
        if fault == 'polkit_build':
            return fail('polkit build')
        binary(build / 'minerva-polkit', 'minerva-polkit')
        return 0

    if command == 'pkg-config':
        if fault == 'polkit_headers' and 'polkit-agent-1' in args:
            return 1
        return 0
    if command == 'ldd':
        print('libc.so.6 => /lib/libc.so.6')
        return 0
    if command == 'pgrep':
        return 1

    if command == 'cmake':
        module = next((x for x in ('window-identity', 'tiled-headers', 'mpv')
                       if any('/native/' + x in a for a in args)), '')
        if fault == module:
            return fail(module + ' cmake')
        if '--install' in args:
            target = {
                'window-identity': 'minerva-shell/native/Minerva/WindowIdentity/libminervawindowidentity.so',
                'tiled-headers': 'lib/minerva/libminervatiledheaders.so',
                'mpv': 'minerva-shell/native/Liquid/Media/libliquidmedia.so',
            }[module]
            put(root / target, 'new simulated module')
        return 0

    if command == 'python3':
        script = Path(args[0]).name
        if script == 'costruisci-quickshell.py':
            if fault == 'quickshell':
                return fail('local Quickshell runtime')
            binary(root / 'libexec/quickshell/qs')
            return 0
        if script == 'liquid-update-version.py':
            put(Path(args[2]), '{"simulation":true}\n')
            return 0
        if script == 'liquid-session-bridge.py':
            return subprocess.run(['/usr/bin/python3', *args], check=False).returncode
        if script == 'minerva-migra-impostazioni.py':
            return 0
        return fail('refused python helper: ' + script)

    if command == 'dart':
        if args[:2] == ['pub', 'get']:
            return fail('dart pub get') if fault == 'dart_pub' else 0
        if args[:2] == ['compile', 'exe']:
            label = 'terminal' if 'terminale.dart' in args[2] else 'daemon'
            if fault == label:
                return fail(label + ' compilation')
            binary(Path(args[args.index('-o') + 1]))
            return 0
        if args[:2] == ['build', 'cli']:
            if fault == 'mail':
                return fail('mail compilation')
            output = Path(args[args.index('-o') + 1])
            binary(output / 'bundle/bin/liquid_maild')
            if fault != 'mail_sqlite':
                put(output / 'bundle/lib/libsqlite3.so', 'simulated sqlite')
            return 0
        return fail('unknown dart command')

    if command == 'fc-list':
        if fault != 'fonts':
            print('Adwaita Sans\nNoto Sans Mono')
        return 0
    if command == 'systemctl':
        if fault == 'inputplumber_missing' and args[:2] == ['cat', 'inputplumber.service']:
            return 1
        if fault == 'printing' and any(x in args for x in ('cups.socket', 'avahi-daemon.service')):
            return fail('printing/discovery service')
        return 0
    return 0

