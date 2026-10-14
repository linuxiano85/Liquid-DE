#!/usr/bin/env python3
"""Trasferimento HTTP selettivo vero, senza modificare il desktop installato."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('packages', ROOT/'scripts/liquid-update-packages.py')
packages = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packages)


class SelectiveUpdate(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix='liquid-packages-')
        self.addCleanup(self.folder.cleanup)
        self.tmp = Path(self.folder.name)
        self.root = self.tmp/'runtime'
        self.root.mkdir()
        self.inventory = ['minerva-shell/menu.qml', 'assets/wallpaper.bin', 'minervad/build/minervad', 'scripts/run']
        for name in self.inventory:
            path = self.root/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'original' if not name.endswith('.bin') else os.urandom(8*1024*1024))
        (self.root/'scripts/run').chmod(0o755)
        self.old = self.build('old')
        (self.root/'minerva-shell/menu.qml').write_bytes(b'nuovo menu, piccolo aggiornamento')
        self.new = self.build('new')

    def build(self, name):
        return packages.build(self.root, self.inventory, self.tmp/name, name, '1'*40,
                              'linux-x86_64-test', 'Correzione del menu')

    def server(self, mutate=None):
        folder = self.tmp/'new/objects'
        calls = []
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_GET(self):
                calls.append(self.path)
                content = (folder/self.path.lstrip('/')).read_bytes()
                if mutate:
                    content = mutate(content)
                self.send_response(200)
                self.send_header('Content-Length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        def stop():
            server.shutdown()
            server.server_close()
            thread.join()
        self.addCleanup(stop)
        return f'http://127.0.0.1:{server.server_port}', calls

    def test_small_change_real_http(self):
        plan = packages.plan(self.old, self.new)
        self.assertEqual(plan['components'], ['shell'])
        self.assertEqual(len(plan['changes']), 1)
        self.assertEqual(len(plan['objects']), 1)
        base, calls = self.server()
        transferred = packages.fetch(self.new, plan, base, self.tmp/'cache', test=True)
        self.assertEqual(transferred, plan['downloadBytes'])
        self.assertLess(transferred, 100)
        self.assertGreater(plan['releaseBytes'], 8*1024*1024)
        self.assertEqual(len(calls), 1)
        self.assertEqual(packages.plan(self.old, self.new, self.tmp/'cache')['downloadBytes'], 0)
        print(json.dumps({'releaseBytes':plan['releaseBytes'], 'downloadBytes':transferred,
                          'httpRequests':len(calls), 'components':plan['components']}), flush=True)

    def test_reproducible_and_deduplicated(self):
        again = self.build('again')
        self.assertEqual(again['files'], self.new['files'])
        self.assertEqual(again['objects'], self.new['objects'])
        self.inventory.append('minerva-shell/copy.qml')
        (self.root/'minerva-shell/copy.qml').write_bytes((self.root/'minerva-shell/menu.qml').read_bytes())
        duplicate = self.build('duplicate')
        self.assertEqual(len(duplicate['objects']), len(self.new['objects']))
        self.assertEqual(len(packages.plan(self.old, duplicate)['objects']), 1)

    def test_permission_change_no_download(self):
        (self.root/'scripts/run').chmod(0o644)
        updated = self.build('mode')
        plan = packages.plan(self.new, updated)
        self.assertEqual(plan['downloadBytes'], 0)
        self.assertEqual(plan['changes'][0]['path'], 'scripts/run')
        self.assertTrue(plan['reuseInstalled'])

    def test_rename_and_delete_no_payload(self):
        self.inventory.remove('assets/wallpaper.bin')
        (self.root/'minerva-shell/menu.qml').rename(self.root/'minerva-shell/renamed.qml')
        self.inventory.remove('minerva-shell/menu.qml')
        self.inventory.append('minerva-shell/renamed.qml')
        updated = self.build('rename')
        plan = packages.plan(self.new, updated)
        self.assertEqual(plan['downloadBytes'], 0)
        self.assertEqual(len(plan['changes']), 3)
        self.assertEqual(len(plan['reuseInstalled']), 1)

    def test_no_personal_files_without_inventory(self):
        (self.root/'personal.txt').write_text('private')
        self.assertNotIn('personal.txt', self.build('private')['files'])
        self.inventory.append('personal.txt')
        with self.assertRaises(ValueError):
            self.build('not-allowed')

    def test_platform_mismatch(self):
        incompatible = copy.deepcopy(self.new)
        incompatible['platform'] = 'linux-aarch64'
        with self.assertRaises(ValueError):
            packages.plan(self.old, incompatible)

    def test_corrupt_download_not_cached(self):
        base, calls = self.server(lambda content: b'x'+content[1:])
        with self.assertRaises(ValueError):
            packages.fetch(self.new, packages.plan(self.old, self.new), base, self.tmp/'cache', test=True)
        self.assertFalse(list((self.tmp/'cache').glob('*.gz')))
        self.assertEqual(len(calls), 1)

    def test_corrupt_cache_redownload(self):
        base, calls = self.server()
        cache = self.tmp/'cache'
        first = packages.plan(self.old, self.new)
        packages.fetch(self.new, first, base, cache, test=True)
        next(cache.glob('*.gz')).write_bytes(b'broken')
        second = packages.plan(self.old, self.new, cache)
        self.assertEqual(second['objects'], first['objects'])
        packages.fetch(self.new, second, base, cache, test=True)
        self.assertEqual(len(calls), 2)

    def test_manifest_tampering(self):
        changed = copy.deepcopy(self.new)
        changed['files']['minerva-shell/menu.qml']['component'] = 'daemon'
        with self.assertRaises(ValueError):
            packages.validate(changed)
        changed = copy.deepcopy(self.new)
        changed['components']['shell'] = '0'*64
        with self.assertRaises(ValueError):
            packages.validate(changed)
        changed = copy.deepcopy(self.new)
        changed['objects']['0'*64] = {'bytes':1, 'sha256':'0'*64}
        with self.assertRaises(ValueError):
            packages.validate(changed)

    def test_symlinks_and_external_parent(self):
        (self.root/'fucina2').mkdir()
        (self.root/'fucina2/core').symlink_to('../minerva-shell')
        self.inventory.append('fucina2/core')
        linked = self.build('linked')
        self.assertEqual(linked['files']['fucina2/core']['kind'], 'symlink')
        self.assertEqual(packages.plan(self.new, linked)['downloadBytes'], 0)
        (self.root/'fucina2/core').unlink()
        (self.root/'fucina2/core').symlink_to('/tmp')
        with self.assertRaises(ValueError):
            self.build('external')
        self.inventory.remove('fucina2/core')
        outside = self.tmp/'outside'
        outside.mkdir()
        (outside/'file').write_text('secret')
        (self.root/'assets/link').symlink_to(outside)
        self.inventory.append('assets/link/file')
        with self.assertRaises(ValueError):
            self.build('parent')

    def test_large_release_manifest_small_update(self):
        # Simulazione del catalogo >1 GiB, distinta dal trasferimento HTTP
        # reale di 8 MiB della prova precedente: non crea file da un gigabyte.
        old = copy.deepcopy(self.old)
        new = copy.deepcopy(self.new)
        for number in range(12):
            digest = packages.sha(f'large-resource-{number}'.encode())
            path = f'assets/large-{number}.bin'
            entry = {'component':'integration', 'kind':'file', 'mode':0o644,
                     'size':100*1024*1024, 'sha256':digest}
            obj = {'bytes':100*1024*1024, 'sha256':packages.sha(f'compressed-{number}'.encode())}
            for manifest in (old, new):
                manifest['files'][path] = entry
                manifest['objects'][digest] = obj
        for manifest in (old, new):
            manifest['components']['integration'] = packages.sha(packages.canonical({p:e for p,e in manifest['files'].items() if e['component']=='integration'}))
        plan = packages.plan(old, new)
        self.assertGreater(plan['releaseBytes'], 1024**3)
        self.assertLess(plan['downloadBytes'], 100)
        self.assertEqual(plan['components'], ['shell'])

    def test_decompressed_size_mismatch(self):
        invalid = copy.deepcopy(self.new)
        invalid['files']['minerva-shell/menu.qml']['size'] = 1
        invalid['components']['shell'] = packages.sha(packages.canonical({p:e for p,e in invalid['files'].items() if e['component']=='shell'}))
        base, calls = self.server()
        with self.assertRaises(ValueError):
            packages.fetch(invalid, packages.plan(self.old, invalid), base, self.tmp/'cache', test=True)
        self.assertFalse(list((self.tmp/'cache').glob('*.gz')))

    def test_paths_and_origins(self):
        for path in ('../a', '/a', 'a//b', 'a/../b', 'a\\b', 'a\0b'):
            with self.assertRaises(ValueError):
                packages.safe_path(path)
        with self.assertRaises(ValueError):
            packages.fetch(self.new, packages.plan(self.old, self.new), 'http://example.com', self.tmp/'cache')


if __name__ == '__main__':
    unittest.main(verbosity=2)
