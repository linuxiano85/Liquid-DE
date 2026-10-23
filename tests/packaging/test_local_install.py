"""Local installer orchestration and resumable runtime builds without root actions."""
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packaging'))
import local_install
import native
import runtime


class LocalInstallTests(unittest.TestCase):
    def test_verification_rejects_unconfigured_packages_and_audit_warnings(self):
        good = 'liquid-de\tinstall ok installed\nliquid-de-runtime\tinstall ok installed\n'
        scenarios = [
            [subprocess.CompletedProcess([], 0, good.replace('installed', 'unpacked'), '')],
            [subprocess.CompletedProcess([], 0, good, ''),
             subprocess.CompletedProcess([], 0, 'package requires configuration\n', '')],
        ]
        for results in scenarios:
            with self.subTest(results=results), mock.patch.object(local_install.subprocess, 'run', side_effect=results):
                with self.assertRaises(ValueError):
                    local_install.verify_packages(False)
        with mock.patch.object(local_install.subprocess, 'run', side_effect=[
                subprocess.CompletedProcess([], 0, good, ''),
                subprocess.CompletedProcess([], 0, '', '')]):
            local_install.verify_packages(False)

    def test_plan_runs_builds_as_user_and_never_installs_missing_liquid_packages_from_apt(self):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            commands = local_install.build_plan(ROOT, work, native.target('ubuntu-24.04'), 2)
        sudo = [command for command in commands if command[0] == 'sudo']
        self.assertEqual(len(sudo), 3)
        self.assertEqual(sudo[0], ['sudo', 'apt-get', 'update'])
        self.assertIn('meson', sudo[1])
        self.assertNotIn('liquid-de-runtime', sudo[1])
        self.assertTrue(all(command[1] == 'apt-get' for command in sudo))
        self.assertTrue(all(path.endswith('.deb') for path in sudo[-1][5:]))
        runtime_command = next(command for command in commands if 'runtime.py' in command[1])
        self.assertIn('--resume', runtime_command)

    def test_privilege_sandbox_stops_before_apt_downloads_or_work_directory_creation(self):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp) / 'work'
            target = native.target('ubuntu-24.04')
            with mock.patch.object(local_install.os, 'geteuid', return_value=1000), \
                 mock.patch.object(local_install.Path, 'read_text', return_value='NoNewPrivs:\t1\n'), \
                 mock.patch.object(local_install.subprocess, 'run') as run:
                with self.assertRaisesRegex(ValueError, 'terminale normale'):
                    local_install.install(ROOT, work, target, 2, False, mock.Mock())
            self.assertFalse(work.exists())
            run.assert_not_called()

    def test_source_fingerprint_ignores_products_but_tracks_code_and_permissions(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp)
            for folder in native.SOURCE_DIRECTORIES:
                (source / folder).mkdir()
            native.write(source / 'LICENSE', 'license')
            native.write(source / 'scripts/program', 'first', True)
            first = native.source_fingerprint(source)
            native.write(source / 'compositore/build-native/binary', 'generated')
            self.assertEqual(first, native.source_fingerprint(source))
            native.write(source / 'scripts/program', 'second', True)
            self.assertNotEqual(first, native.source_fingerprint(source))
            before = native.source_fingerprint(source)
            (source / 'scripts/program').chmod(0o644)
            self.assertNotEqual(before, native.source_fingerprint(source))

    def test_existing_compatible_dart_is_used_without_download(self):
        with tempfile.TemporaryDirectory() as temp, \
             mock.patch.object(local_install.shutil, 'which', return_value='/usr/bin/dart'), \
             mock.patch.object(local_install, 'dart_version', return_value=(3, 12, 1)), \
             mock.patch.object(local_install, 'read_https') as download:
            self.assertEqual(local_install.ensure_dart(Path(temp)), Path('/usr/bin'))
            download.assert_not_called()

    def test_interrupted_build_never_installs_partial_packages(self):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp) / 'work'
            installer = mock.Mock()
            def fail(command, **kwargs):
                if command[:2] == ['sudo', 'apt-get']:
                    raise subprocess.CalledProcessError(42, command)
                return mock.Mock(returncode=0)
            with mock.patch.object(local_install, 'preflight'), \
                 mock.patch.object(local_install.subprocess, 'run', return_value=mock.Mock(returncode=0)), \
                 mock.patch.object(local_install.subprocess, 'Popen', side_effect=fail):
                with self.assertRaises(subprocess.CalledProcessError):
                    local_install.install(ROOT, work, native.target('ubuntu-24.04'), 2, False, installer)
            installer.assert_not_called()
            self.assertEqual(json.loads((work / 'install-state.json').read_text())['phase'], 'interrotto')


class RuntimeResumeTests(unittest.TestCase):
    def test_resume_reuses_completed_components_and_retries_the_failed_one(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            recipes = root / 'recipes'
            recipes.mkdir()
            manifest = recipes / 'runtime-sources.json'
            manifest.write_text(json.dumps({'schema': 1, 'qtVersion': 'test', 'sources': [
                {'name': name, 'version': '1', 'options': []} for name in ('first', 'second')]}))
            archives = {}
            for name in ('first', 'second'):
                archive = root / (name + '.tar')
                with tarfile.open(archive, 'w') as output:
                    for file in ('COPYING', 'meson.build'):
                        info = tarfile.TarInfo(name + '-1/' + file)
                        info.size = 7
                        output.addfile(info, io.BytesIO(b'fixture'))
                archives[name] = archive
            commands = []
            failed = False
            def run(command, **kwargs):
                nonlocal failed
                commands.append(command)
                if command[:2] == ['meson', 'setup']:
                    native.write(Path(command[2]) / 'meson-private/coredata.dat', 'fixture')
                if command[:2] == ['meson', 'compile'] and 'second-build' in command[3] and not failed:
                    failed = True
                    raise subprocess.CalledProcessError(42, command)
                return subprocess.CompletedProcess(command, 0)
            work, prefix = root / 'work', root / 'prefix'
            with mock.patch.object(runtime, 'HERE', recipes), \
                 mock.patch.object(runtime, 'fetch', side_effect=lambda item, cache: archives[item['name']]), \
                 mock.patch.object(runtime.subprocess, 'run', side_effect=run):
                with self.assertRaises(subprocess.CalledProcessError):
                    runtime.build(work, prefix, 2)
                self.assertEqual(json.loads((work / 'progress.json').read_text())['completed'], ['first'])
                runtime.build(work, prefix, 2, resume=True)
                self.assertEqual(json.loads((work / 'progress.json').read_text())['completed'], ['first', 'second'])
                self.assertEqual(json.loads((prefix / 'runtime.json').read_text())['qtVersion'], 'test')
                before = len(commands)
                runtime.build(work, prefix, 2, resume=True)
                self.assertEqual(len(commands), before)
                manifest.write_text(manifest.read_text() + '\n')
                with self.assertRaisesRegex(ValueError, 'Ricetta runtime modificata'):
                    runtime.build(work, prefix, 2, resume=True)
            first_compiles = [command for command in commands if command[:2] == ['meson', 'compile'] and 'first-build' in command[3]]
            self.assertEqual(len(first_compiles), 1)


if __name__ == '__main__':
    unittest.main()
