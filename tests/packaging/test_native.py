"""Debian packaging regressions. No sudo, apt installation or service changes."""
import hashlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packaging'))
import native
import platforms
import repository
import runtime


def script(name):
    loader = importlib.machinery.SourceFileLoader(name.replace('-', '_'), str(ROOT / 'scripts' / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class PlatformTests(unittest.TestCase):
    def test_supported_abis(self):
        for name, version, repository_name in [('debian', '13', 'debian-13'),
                ('ubuntu', '24.04', 'ubuntu-24.04'), ('ubuntu', '26.04', 'ubuntu-26.04'),
                ('linuxmint', '22.3', 'ubuntu-24.04')]:
            with self.subTest(name=name, version=version):
                data = dict(ID=name, VERSION_ID=version, UBUNTU_CODENAME='noble')
                result = platforms.detect(data, 'x86_64', False)
                self.assertEqual(result['repository'], repository_name)
                self.assertFalse(result['certified'])

    def test_unsupported_platforms_are_rejected(self):
        for data, arch, immutable in [
                ({'ID': 'debian', 'VERSION_ID': '12'}, 'x86_64', False),
                ({'ID': 'linuxmint', 'VERSION_ID': '7'}, 'x86_64', False),
                ({'ID': 'fedora', 'VERSION_ID': '44'}, 'x86_64', False),
                ({'ID': 'pop', 'ID_LIKE': 'ubuntu', 'VERSION_ID': '24.04'}, 'x86_64', False),
                ({'ID': 'ubuntu', 'VERSION_ID': '24.04'}, 'aarch64', False),
                ({'ID': 'ubuntu', 'VERSION_ID': '24.04'}, 'x86_64', True)]:
            with self.subTest(data=data, arch=arch):
                with self.assertRaises(ValueError):
                    platforms.detect(data, arch, immutable)

    def test_apt_does_not_upgrade_unrelated_packages(self):
        target = platforms.detect({'ID': 'debian', 'VERSION_ID': '13'}, 'x86_64', False)
        self.assertEqual(platforms.commands(target), [['apt-get', 'update'],
                                                    ['apt-get', '--no-remove', 'install', 'liquid-de']])


class BootstrapTests(unittest.TestCase):
    def test_unpublished_repository_fails_before_privileges(self):
        bootstrap = script('liquid-package-install')
        with mock.patch.object(bootstrap.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'non ancora pubblicato'):
                bootstrap.repository_config({'repository': 'ubuntu-24.04'})
            run.assert_not_called()

    def test_scan_uses_dpkg_without_privileges(self):
        bootstrap = script('liquid-package-install')
        def query(command, **kwargs):
            self.assertEqual(command[:2], ['dpkg-query', '-W'])
            installed = command[-1] not in ('liquid-de', 'liquid-de-runtime')
            return subprocess.CompletedProcess(command, 0 if installed else 1,
                                               'installed' if installed else '')
        with mock.patch.object(bootstrap.subprocess, 'run', side_effect=query):
            all_packages, missing = bootstrap.scan({'family': 'deb'})
        self.assertGreater(len(all_packages), 10)
        self.assertEqual(missing, ['liquid-de', 'liquid-de-runtime'])

    def test_repository_url_injection_is_rejected(self):
        bootstrap = script('liquid-package-install')
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            native.write(root / 'packaging/repositories.json', json.dumps({'channels': {
                'ubuntu-24.04': {'url': 'https://example.invalid/\nTrusted: yes',
                                'keyUrl': 'https://example.invalid/key.asc'}}}))
            with mock.patch.object(bootstrap, 'ROOT', root):
                with self.assertRaises(ValueError):
                    bootstrap.repository_config({'repository': 'ubuntu-24.04'})


class PrivateRuntimeTests(unittest.TestCase):
    def fixture(self, temp):
        root = Path(temp)
        executable = root / 'libexec/quickshell/qs'
        native.write(executable, '#!/bin/sh\nprintf "%s|%s|%s" "${LD_LIBRARY_PATH-unset}" "${QT_PLUGIN_PATH-unset}" "${WAYLAND_DISPLAY-unset}"\n', True)
        native.write(root / 'scripts/minerva-quickshell', (ROOT / 'scripts/minerva-quickshell').read_text(), True)
        native.write(root / 'package-install.json', '{}')
        metadata = {'schema': 1, 'qtVersion': '6.test', 'sha256': runtime.digest(executable)}
        native.write(root / 'libexec/quickshell/runtime.json', json.dumps(metadata))
        native.write(root / 'runtime/runtime.json', json.dumps(metadata))
        return root

    def test_launch_needs_no_system_qt_or_pkg_config_and_isolates_plugins(self):
        with tempfile.TemporaryDirectory() as temp:
            root = self.fixture(temp)
            result = subprocess.run(['/usr/bin/python3', str(root / 'scripts/minerva-quickshell')],
                env={'PATH': '/nonexistent', 'LD_LIBRARY_PATH': '/nonexistent',
                     'QT_PLUGIN_PATH': '/host/qt', 'WAYLAND_DISPLAY': 'wayland-test'},
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, 'unset|unset|wayland-test')

    def test_mixed_or_tampered_runtime_never_falls_back(self):
        for fault in ('version', 'hash'):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as temp:
                root = self.fixture(temp)
                if fault == 'version':
                    native.write(root / 'runtime/runtime.json', '{"schema":1,"qtVersion":"other"}')
                else:
                    with (root / 'libexec/quickshell/qs').open('a') as stream:
                        stream.write('# changed\n')
                result = subprocess.run(['/usr/bin/python3', str(root / 'scripts/minerva-quickshell')],
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Runtime Liquid incompleto', result.stderr)

    def test_source_cache_tampering_is_rejected_without_download(self):
        with tempfile.TemporaryDirectory() as temp:
            cache = Path(temp)
            (cache / 'test-1.tar').write_bytes(b'changed')
            with mock.patch.object(runtime.urllib.request, 'urlopen') as download:
                with self.assertRaisesRegex(ValueError, 'corrotta'):
                    runtime.fetch({'name': 'test', 'version': '1',
                                   'sha256': hashlib.sha256(b'expected').hexdigest()}, cache)
                download.assert_not_called()

    def test_archive_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / 'bad.tar'
            with tarfile.open(archive, 'w') as output:
                info = tarfile.TarInfo('../escaped')
                info.size = 1
                output.addfile(info, io.BytesIO(b'x'))
            with self.assertRaises(tarfile.FilterError):
                runtime.extract(archive, Path(temp) / 'source')
            self.assertFalse((Path(temp) / 'escaped').exists())


class MigrationTests(unittest.TestCase):
    def test_preserves_data_and_unrelated_launchers_and_is_idempotent(self):
        migration = script('liquid-package-migrate')
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp) / 'home'
            old = home / '.local/opt/liquid-de'
            old.mkdir(parents=True)
            native.write(old / 'radice/user-file', 'keep')
            root = Path(temp) / 'system'
            native.write(root / 'package-install.json', '{}')
            apps = home / '.local/share/applications'
            native.write(apps / 'minerva-files.desktop', 'Exec=' + str(old / 'radice/scripts/minerva-files'))
            native.write(apps / 'unrelated.desktop', 'Exec=unrelated')
            native.write(home / '.config/liquid-de/settings.json', '{"keep":true}')
            state = home / '.local/state/liquid-de'
            with mock.patch.dict(os.environ, {'XDG_DATA_HOME': str(home / '.local/share'),
                                             'XDG_CONFIG_HOME': str(home / '.config')}):
                migration.migrate(home, root, state)
                first = (state / 'package-migration.json').read_bytes()
                migration.migrate(home, root, state)
            self.assertEqual(first, (state / 'package-migration.json').read_bytes())
            self.assertFalse((apps / 'minerva-files.desktop').exists())
            self.assertTrue((apps / 'unrelated.desktop').exists())
            self.assertEqual((old / 'radice/user-file').read_text(), 'keep')
            self.assertEqual((home / '.config/liquid-de/settings.json').read_text(), '{"keep":true}')
            data = json.loads(first)
            self.assertTrue(Path(data['launchers'][0]['backup']).is_file())


class StagingTests(unittest.TestCase):
    def test_stages_complete_fixture_with_fhs_paths_and_no_sdk_or_global_qs(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            source = temp / 'source'
            native.prepare(ROOT, source)
            for relative in native.REQUIRED:
                native.copy_file(Path('/usr/bin/true'), source / relative)
            manifest = source / 'packaging/runtime-sources.json'
            qt = json.loads(manifest.read_text())['qtVersion']
            private = temp / 'private'
            native.write(private / 'runtime.json', json.dumps({'schema': 1,
                         'qtVersion': qt, 'sourceManifestSha256': runtime.digest(manifest)}))
            native.write(private / 'include/sdk.h', 'not a runtime input')
            native.write(private / 'licenses/test/LICENSE', 'fixture')
            native.write(source / 'libexec/quickshell/runtime.json', json.dumps({'schema': 1,
                         'qtVersion': qt, 'sha256': runtime.digest(source / 'libexec/quickshell/qs')}))
            stage = temp / 'stage'
            # Only patchelf is replaced: this test exercises real staging,
            # source adaptation, ldd and archive assembly with ELF fixtures.
            with mock.patch.object(native, 'run') as relocate:
                native.stage(source, private, stage, native.target('ubuntu-24.04'))
            self.assertTrue(relocate.called)
            self.assertTrue(all(call.args[:3] == ('patchelf', '--force-rpath', '--set-rpath')
                                for call in relocate.call_args_list))
            root = stage / native.PREFIX
            self.assertFalse((root / 'runtime/include').exists())
            self.assertFalse((stage / 'usr/bin/qs').exists())
            self.assertTrue((root / 'scripts/qs').is_symlink())
            self.assertFalse((stage / 'usr/bin/liquid-de-radice').is_symlink())
            self.assertIn('/usr/bin/minerva-pam', (root / 'minerva-shell/blocco/Blocco.qml').read_text())
            self.assertIn('/usr/bin/liquid-de-radice',
                (source / 'minervad/lib/services/fucina/requisiti_amministrazione.dart').read_text())
            self.assertTrue((stage / 'usr/share/applications/liquidde-mimeapps.list').is_file())
            self.assertIn('Exec=/usr/bin/minerva-files %u',
                          (stage / 'usr/share/applications/minerva-files.desktop').read_text())
            self.assertTrue((stage / 'usr/share/wayland-sessions/liquid-de.desktop').is_file())
            native.package(stage, temp / 'packages', native.target('ubuntu-24.04'), '1.0.0')


class LoginTests(unittest.TestCase):
    def test_preparation_does_not_change_the_display_manager(self):
        login = script('liquid-login-manager')
        with mock.patch.object(login, 'command') as command:
            login.prepare()
        self.assertEqual([call.args[0] for call in command.call_args_list],
                         ['systemd-sysusers', 'systemd-tmpfiles'])

    def test_activation_is_deferred_and_recovers_if_enable_fails(self):
        login = script('liquid-login-manager')
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            calls = []
            def command(*args):
                calls.append(args)
                if args == ('systemctl', 'enable', '--force', 'greetd.service'):
                    raise subprocess.CalledProcessError(1, args)
            with mock.patch.multiple(login, STATE=root, PREVIOUS=root / 'previous.json',
                                     DROPIN=root / 'greetd.conf'), \
                 mock.patch.object(login, 'validate'), \
                 mock.patch.object(login, 'current', return_value='lightdm.service'), \
                 mock.patch.object(login, 'prepare'), \
                 mock.patch.object(login, 'command', side_effect=command):
                with self.assertRaises(subprocess.CalledProcessError):
                    login.select('greetd.service')
            self.assertIn(('systemctl', 'enable', '--force', 'lightdm.service'), calls)
            self.assertTrue(all('stop' not in call and '--now' not in call for call in calls))
            self.assertEqual(json.loads((root / 'previous.json').read_text())['unit'], 'lightdm.service')

    def test_arbitrary_services_cannot_cross_privilege_boundary(self):
        login = script('liquid-login-manager')
        with mock.patch.object(login.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                login.validate('sshd.service')
            run.assert_not_called()


@unittest.skipUnless(shutil.which('dpkg-deb') and shutil.which('dpkg-shlibdeps'), 'Requires Debian packaging tools')
class DebianPackageTests(unittest.TestCase):
    def fixture(self, temp):
        stage = Path(temp) / 'stage'
        root = stage / native.PREFIX
        native.write(root / 'package-install.json', '{"schema":1,"family":"deb"}')
        native.write(root / 'runtime/runtime.json', '{"schema":1,"qtVersion":"fixture"}')
        native.copy_file(Path('/usr/bin/true'), root / 'bin/fixture')
        for source, destination in [('greetd.toml', 'etc/greetd/liquid-de.toml'),
                ('sysusers.conf', 'usr/lib/sysusers.d/liquid-de-login.conf'),
                ('tmpfiles.conf', 'usr/lib/tmpfiles.d/liquid-de-login.conf')]:
            native.copy_file(ROOT / 'packaging/login' / source, stage / destination)
        for name in ('liquid-login-manager', 'liquid-login-session'):
            native.copy_file(ROOT / 'scripts' / name, root / 'scripts' / name)
        (root / 'scripts/minerva-greetd').symlink_to('liquid-login-manager')
        native.copy_file(ROOT / 'scripts/minerva-avvia-sessione', root / 'login/minerva-avvia-sessione')
        link = stage / 'usr/bin/minerva-greetd'
        link.parent.mkdir(parents=True)
        link.symlink_to('../lib/liquid-de/scripts/liquid-login-manager')
        native.write(stage / 'etc/pam.d/liquid-de', 'auth required pam_unix.so\n')
        return stage

    def test_builds_real_debs_with_system_dependencies_and_optional_login(self):
        with tempfile.TemporaryDirectory() as temp:
            stage = self.fixture(temp)
            output = Path(temp) / 'packages'
            native.package(stage, output, native.target('ubuntu-24.04'), '1.0.0')
            packages = sorted(output.glob('*.deb'))
            self.assertEqual(len(packages), 3)
            main = output / 'liquid-de_1.0.0-1_amd64.deb'
            dependencies = subprocess.check_output(['dpkg-deb', '-f', str(main), 'Depends'], text=True)
            self.assertIn('liquid-de-runtime (= 1.0.0-1)', dependencies)
            self.assertIn('libc6', dependencies)
            self.assertNotIn('greetd', dependencies)
            self.assertNotIn('dart', dependencies)
            bootstrap = script('liquid-package-install')
            candidates = bootstrap.local_packages(output, native.target('ubuntu-24.04'))
            self.assertEqual(len(candidates), 2)
            with self.assertRaisesRegex(ValueError, 'altra piattaforma|altra|piattaforma'):
                bootstrap.local_packages(output, native.target('debian-13'))
            extracted = Path(temp) / 'extracted'
            subprocess.run(['dpkg-deb', '-x', str(main), str(extracted)], check=True)
            self.assertFalse((extracted / 'usr/bin/minerva-greetd').exists())
            self.assertFalse((extracted / native.PREFIX / 'runtime').exists())
            self.assertTrue((extracted / 'etc/pam.d/liquid-de').is_file())

    def test_rejects_escaping_links_before_packaging(self):
        with tempfile.TemporaryDirectory() as temp:
            stage = self.fixture(temp)
            (stage / native.PREFIX / 'escape').symlink_to('/etc/passwd')
            with self.assertRaisesRegex(ValueError, 'Symlink'):
                native.package(stage, Path(temp) / 'output', native.target('debian-13'), '1.0.0')
            self.assertFalse((Path(temp) / 'output').exists())

    @unittest.skipUnless(shutil.which('gpg') and shutil.which('apt-ftparchive'), 'Requires GPG and apt-utils')
    def test_repository_metadata_is_really_signed(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            stage = self.fixture(temp)
            packages = temp / 'packages'
            native.package(stage, packages, native.target('ubuntu-24.04'), '1.0.0')
            home = temp / 'gnupg'
            home.mkdir(mode=0o700)
            with mock.patch.dict(os.environ, GNUPGHOME=str(home)):
                created = subprocess.run(['gpg', '--batch', '--pinentry-mode', 'loopback',
                    '--passphrase', '', '--quick-generate-key', 'Liquid packaging test', 'ed25519', 'sign', '0'],
                    capture_output=True, text=True)
                if created.returncode:
                    if os.environ.get('LIQUID_REQUIRE_GPG') == '1':
                        self.fail('Cannot test repository signatures: ' + created.stderr)
                    self.skipTest('Sandbox does not permit an isolated GPG agent')
                try:
                    listing = subprocess.check_output(['gpg', '--batch', '--with-colons', '--list-keys'], text=True)
                    key = next(line.split(':')[9] for line in listing.splitlines() if line.startswith('fpr:'))
                    sources = temp / 'sources'
                    native.write(sources / 'test-source.c', 'int main(void) { return 0; }\n')
                    destination = temp / 'repository'
                    repository.assemble(packages, destination, native.target('ubuntu-24.04'), key, sources)
                    release = destination / 'dists/stable/Release'
                    verified = subprocess.run(['gpg', '--batch', '--verify', str(release.parent / 'Release.gpg'), str(release)],
                                              capture_output=True, text=True)
                    self.assertEqual(verified.returncode, 0, verified.stderr)
                    self.assertIn(b'Package: liquid-de-runtime', (release.parent / 'main/binary-amd64/Packages').read_bytes())
                    channel = json.loads((destination / 'channel.json').read_text())
                    self.assertEqual(channel['keySha256'], runtime.digest(destination / 'key.asc'))
                finally:
                    subprocess.run(['gpgconf', '--homedir', str(home), '--kill', 'gpg-agent'],
                                   capture_output=True, check=False)


if __name__ == '__main__':
    unittest.main()
