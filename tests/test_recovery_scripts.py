"""Production launcher and orphan-removal branch, with isolated command fakes.

No installed package, desktop session or system path is modified.
"""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Recovery(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='liquid-recovery-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'minerva-shell').mkdir()
        (self.root / 'minerva-shell/filemanager.qml').touch()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        XDG_RUNTIME_DIR=str(self.root), CASE_ROOT=str(self.root))
        for name in ('minerva-files', 'minerva-ambiente-app'):
            shutil.copyfile(ROOT / 'scripts' / name, self.root / 'scripts' / name)
        self.command('qs', '''#!/usr/bin/env python3
import json, os, pathlib, sys, time
r = pathlib.Path(os.environ['CASE_ROOT']); args = sys.argv[1:]
try: os.fstat(9); inherited = True
except OSError: inherited = False
with (r / 'calls').open('a') as f: f.write(json.dumps([args, inherited]) + '\\n')
if args[0] == 'ipc':
    if os.environ.get('HUNG') == '1': time.sleep(60)
    if not (r / 'ready').exists(): sys.exit(1)
    if time.time() < float((r / 'ready').read_text()): sys.exit(1)
    print('Target not found.' if os.environ.get('MISSING_TARGET') == '1' else 'ok')
    sys.exit(0)
(r / 'ready').write_text(str(time.time() + .3))
''')

    def command(self, name, text):
        p = self.bin / name
        p.write_text(text)
        p.chmod(0o755)

    def launch(self, *args, **env):
        return subprocess.run(['sh', str(self.root / 'scripts/minerva-files'), *args],
                              env=dict(self.env, **env), capture_output=True, text=True, timeout=30)

    def calls(self):
        return [json.loads(s) for s in (self.root / 'calls').read_text().splitlines()]

    def test_cold_start_waits_and_delivers_path_without_inheriting_lock(self):
        p = self.launch('/a directory/with spaces')
        self.assertEqual(p.returncode, 0, p.stderr)
        calls = self.calls()
        self.assertTrue(any(c[0][-2:] == ['avvia', '/a directory/with spaces'] for c in calls))
        self.assertFalse(any(c[1] for c in calls))
        self.assertEqual(sum(c[0][0] != 'ipc' for c in calls), 1)

    def test_preload_then_click_opens_existing_process(self):
        self.assertEqual(self.launch(MINERVA_FILES_DORMIENTE='1').returncode, 0)
        self.assertFalse(any('avvia' in c[0] or 'open' in c[0] for c in self.calls()))
        self.assertEqual(self.launch('/requested').returncode, 0)
        self.assertTrue(any(c[0][-2:] == ['open', '/requested'] for c in self.calls()))
        self.assertEqual(sum(c[0][0] != 'ipc' for c in self.calls()), 1)

    def test_concurrent_requests_start_one_process_and_deliver_both(self):
        cmd = ['sh', str(self.root / 'scripts/minerva-files')]
        a = subprocess.Popen(cmd + ['/one'], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        b = subprocess.Popen(cmd + ['/two'], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: a.kill() if a.poll() is None else None)
        self.addCleanup(lambda: b.kill() if b.poll() is None else None)
        self.assertEqual(a.communicate(timeout=20)[1], b'')
        self.assertEqual(b.communicate(timeout=20)[1], b'')
        self.assertEqual((a.returncode, b.returncode), (0, 0))
        self.assertEqual(sum(c[0][0] != 'ipc' for c in self.calls()), 1)
        paths = [c[0][-1] for c in self.calls() if c[0][-2] in ('avvia', 'open')]
        self.assertCountEqual(paths, ['/one', '/two'])

    def test_hung_ipc_returns_error_in_bounded_time(self):
        p = self.launch(HUNG='1')
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('non risponde', p.stderr)

    def test_missing_target_with_zero_exit_is_not_success(self):
        result = self.launch(MISSING_TARGET='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('non risponde', result.stderr)

    def test_failed_systemd_scope_falls_back_to_direct_launch(self):
        (self.root / 'systemd').mkdir()
        with socket.socket(socket.AF_UNIX) as sock:
            sock.bind(str(self.root / 'systemd/private'))
            self.command('systemd-run', '#!/bin/sh\nexit 1\n')
            result = self.launch('/fallback')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum(c[0][0] != 'ipc' for c in self.calls()), 1)
        self.assertTrue(any(c[0][-2:] == ['avvia', '/fallback'] for c in self.calls()))

    def orphan(self, *packages, manifest=True, boot=False, missing_files=False):
        protection = self.root / 'required-packages.txt'
        if manifest: protection.write_text('quickshell\nwayland\n')
        source = (ROOT / 'scripts/minerva-radice').read_text()
        body = source.split('    togli-orfani)\n', 1)[1].split('\n        ;;', 1)[0]
        body = body.replace('/usr/local/share/liquid-de/required-packages.txt', str(protection))
        script = self.root / 'orphan.sh'
        script.write_text('set -eu\nmuori() { echo "$*" >&2; exit 1; }\nannota() { :; }\n' + body)
        self.command('stat', '#!/bin/sh\nprintf "0:644\\n"\n')
        self.command('pacman', '''#!/bin/sh
case "$1" in
  -Qtdq) printf 'quickshell\nunused\nlinux-test\n';;
  -Qql) [ "${MISSING_FILES:-0}" = 0 ] || exit 1
         if [ "${BOOT_FILES:-0}" = 1 ]; then printf '/usr/lib/modules/test/kernel.ko\n';
         else printf '/usr/share/example\n'; fi;;
  -R) printf '%s\n' "$@" > "$CASE_ROOT/removed";;
  *) exit 90;;
esac
''')
        return subprocess.run(['sh', str(script), *packages], capture_output=True, text=True,
                              env=dict(self.env, BOOT_FILES=str(int(boot)), MISSING_FILES=str(int(missing_files))), timeout=5)

    def test_orphan_removal_requires_manifest(self):
        self.assertNotEqual(self.orphan('unused', manifest=False).returncode, 0)
        self.assertFalse((self.root / 'removed').exists())

    def test_protected_dependency_aborts_whole_transaction(self):
        self.assertNotEqual(self.orphan('unused', 'quickshell').returncode, 0)
        self.assertFalse((self.root / 'removed').exists())

    def test_kernel_and_unverifiable_package_are_not_removed(self):
        self.assertNotEqual(self.orphan('linux-test', boot=True).returncode, 0)
        self.assertNotEqual(self.orphan('unused', missing_files=True).returncode, 0)
        self.assertFalse((self.root / 'removed').exists())

    def test_only_selected_orphans_removed_without_recursive_flags(self):
        p = self.orphan('unused', 'not-orphan')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual((self.root / 'removed').read_text().splitlines(), ['-R', '--noconfirm', '--', 'unused'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
