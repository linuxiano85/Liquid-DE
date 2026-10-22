"""Installer control-flow regressions. Builds and system services are test doubles.

Run: python3 -m unittest discover -s tests/installer -v
These tests never run real sudo, pacman or systemctl. They do not test a GUI.
"""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from fakes import put

ROOT = Path(__file__).resolve().parents[2]
FAKES = Path(__file__).with_name('fakes.py')


def entries(path):
    return [s for s in path.read_text().splitlines() if s and not s.startswith('#')]


class Fixture:
    def __init__(self, directory, fault='', gui=False):
        self.case = Path(directory)
        self.root = self.case / 'source'
        self.home = self.case / 'home'
        self.home.mkdir()
        self.prefix = self.home / '.local/opt/liquid-de'
        self.env = {'HOME': str(self.home), 'USER': 'installer-test', 'LANG': 'C.UTF-8',
                    'PATH': str(self.case / 'mockbin') + ':/usr/bin:/bin',
                    'AUDIT_CASE': str(self.case), 'LIQUID_PREFISSO': str(self.prefix),
                    'XDG_RUNTIME_DIR': str(self.case / 'runtime'),
                    'TMPDIR': str(self.case / 'tmp')}
        self.env['MINERVA_INSTALL_GUI'] = '1' if gui else '0'
        for name in ('tmp', 'runtime'):
            (self.case / name).mkdir()
        put(self.case / 'config.json', json.dumps({'fault': fault}))
        shutil.copyfile(FAKES, self.case / 'dispatch.py')
        required = entries(ROOT / 'config/liquid-install-required.list')
        apps = entries(ROOT / 'config/liquid-install-apps.list')
        for app in apps:
            required.extend(['scripts/' + app, 'desktop/' + app + '.desktop',
                             'assets/icons/' + app + '.svg'])
        for name in required:
            put(self.root / name, executable=name.startswith('scripts/'))
        for name in ('config/liquid-install-required.list', 'config/liquid-install-apps.list'):
            shutil.copyfile(ROOT / name, self.root / name)
        # Execute the actual scripts being tested, rather than mirroring their logic.
        for name in ('scripts/install-minerva.sh', 'scripts/minerva-verifica-sorgenti',
                     'scripts/minerva-cartelle.sh', 'scripts/minerva-compila',
                     'scripts/minerva-compila-posta', 'scripts/minerva-installa-radice',
                     'scripts/minerva-install-run', 'scripts/liquid-session-bridge.py',
                     'scripts/costruisci-mpv.sh', 'scripts/costruisci-window-identity.sh',
                     'scripts/costruisci-tiled-headers.sh', 'scripts/minerva-session-wayland',
                     'scripts/minerva-session-recupero', 'compositore/costruisci.sh',
                     'permessi/costruisci.sh'):
            shutil.copyfile(ROOT / name, self.root / name)
            (self.root / name).chmod(0o755)
        # This restricted local host maps only uid 0. CI normally runs as a
        # regular user. The production root guard is tested separately below.
        if os.geteuid() == 0:
            script = self.root / 'scripts/install-minerva.sh'
            text = script.read_text()
            guard = 'if [[ $EUID -eq 0 ]]; then'
            assert text.count(guard) == 1
            script.write_text(text.replace(guard, 'if false; then # fixture only'))
        commands = ('sudo pacman meson ninja pkg-config ldd pgrep cmake python3 dart '
                    'fc-list systemctl udevadm update-desktop-database gtk-update-icon-cache '
                    'qs cliphist wl-copy brightnessctl nmcli pactl bluetoothctl alacritty '
                    'mpv yt-dlp ffmpeg greetd gnome-keyring-daemon').split()
        for command in commands:
            put(self.case / 'mockbin' / command,
                '#!/usr/bin/python3\nimport runpy,sys,os\n'
                'ns=runpy.run_path(os.path.join(os.environ["AUDIT_CASE"],"dispatch.py"))\n'
                'sys.exit(ns["dispatch"](os.path.basename(sys.argv[0]),sys.argv[1:]))\n', True)

    def run(self, scan=False, gui=False):
        script = 'scripts/minerva-install-run' if gui else 'scripts/install-minerva.sh'
        result = subprocess.run(['/bin/bash', str(self.root / script)] + (['--scan'] if scan else []),
                                cwd=self.root, env=self.env, capture_output=True, text=True, timeout=45)
        self.output = result.stdout + result.stderr
        return result

    @property
    def registered(self):
        return (self.case / 'system/usr/share/wayland-sessions/liquid-de.desktop').exists()

    def trace(self):
        path = self.case / 'trace.jsonl'
        return [json.loads(x) for x in path.read_text().splitlines()] if path.exists() else []


class InstallerTests(unittest.TestCase):
    def test_checkout_has_all_installation_inputs(self):
        result = subprocess.run(['/bin/sh', str(ROOT / 'scripts/minerva-verifica-sorgenti')],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_posta_inputs_fail_before_privileges(self):
        for missing in ('scripts/minerva-posta', 'desktop/minerva-posta.desktop',
                        'assets/icons/minerva-posta.svg', 'scripts/minerva-posta-demone',
                        'minerva-shell/posta.qml'):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as directory:
                f = Fixture(directory)
                (f.root / missing).unlink()
                result = f.run(scan=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(missing, f.output)
                self.assertFalse(f.registered)
                self.assertFalse(any(x['command'] == 'sudo' for x in f.trace()))

    def test_non_executable_launcher_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            f = Fixture(directory)
            (f.root / 'scripts/minerva-posta').chmod(0o644)
            self.assertNotEqual(f.run(scan=True).returncode, 0)
            self.assertIn('non è eseguibile', f.output)

    def test_success_installs_posta_and_agent(self):
        with tempfile.TemporaryDirectory() as directory:
            f = Fixture(directory)
            self.assertEqual(f.run().returncode, 0, f.output)
            self.assertTrue(f.registered)
            self.assertTrue((f.prefix / 'bin/minerva-polkit').is_file())
            self.assertTrue((f.prefix / 'bin/minerva-posta').resolve().exists())
            self.assertTrue((f.prefix / 'share/applications/minerva-posta.desktop').is_file())

    def test_required_failures_do_not_publish_session(self):
        for fault in ('compositor', 'compositor_tests', 'window-identity', 'tiled-headers',
                      'quickshell', 'daemon', 'mail', 'mail_sqlite', 'terminal',
                      'polkit_build', 'polkit_headers', 'pam_install', 'greetd'):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                f = Fixture(directory, fault)
                self.assertNotEqual(f.run().returncode, 0, f.output)
                self.assertFalse(f.registered, fault)

    def test_agent_failure_preserves_previous_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            f = Fixture(directory, 'polkit_build')
            previous = f.prefix / 'radice/previous-install.txt'
            put(previous, 'existing runtime')
            self.assertNotEqual(f.run().returncode, 0)
            self.assertEqual(previous.read_text(), 'existing runtime')

    def test_missing_dependency_command_is_caught_before_build(self):
        with tempfile.TemporaryDirectory() as directory:
            f = Fixture(directory)
            # The developer machine may have a real qs in /usr/bin. Override
            # only this lookup so the fixture actually simulates its absence.
            missing_qs = f.case / 'missing-qs.bash'
            put(missing_qs, 'command() {\n'
                '  if [[ $1 == -v && $2 == qs ]]; then return 1; fi\n'
                '  builtin command "$@"\n'
                '}\n')
            f.env['BASH_ENV'] = str(missing_qs)
            self.assertNotEqual(f.run().returncode, 0)
            self.assertFalse(f.registered)
            self.assertFalse(any(x['command'] == 'meson' for x in f.trace()))

    def test_optional_failures_are_summarized_for_gui(self):
        for fault in ('mpv', 'printing', 'inputplumber_missing', 'fonts'):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                f = Fixture(directory, fault, gui=True)
                self.assertEqual(f.run(gui=True).returncode, 0, f.output)
                self.assertIn('Installazione completata con limitazioni', f.output)
                self.assertIn('@@MINERVA_WARNING@@', f.output)

    def test_stale_media_module_is_reported_accurately(self):
        with tempfile.TemporaryDirectory() as directory:
            f = Fixture(directory, 'mpv')
            put(f.root / 'minerva-shell/native/Liquid/Media/libliquidmedia.so', 'old module')
            self.assertEqual(f.run().returncode, 0, f.output)
            self.assertIn('resta la versione precedente', f.output)
            self.assertNotIn('Media userà Qt Multimedia', f.output)

    def test_gui_runner_preserves_failure_exit_status(self):
        with tempfile.TemporaryDirectory() as directory:
            f = Fixture(directory, 'polkit_build')
            self.assertNotEqual(f.run(gui=True).returncode, 0)
            self.assertFalse(f.registered)

    @unittest.skipUnless(os.geteuid() == 0, 'Root guard requires uid 0')
    def test_original_installer_rejects_root(self):
        result = subprocess.run(['/bin/bash', str(ROOT / 'scripts/install-minerva.sh')],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Non eseguire questo script come root', result.stdout)


class BridgeTests(unittest.TestCase):
    def test_recovery_bridge_preserves_environment(self):
        spec = importlib.util.spec_from_file_location('recovery_bridge', ROOT / 'scripts/liquid-session-bridge.py')
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'space & $literal'
            put(root / 'scripts/start-minerva-wayland.sh',
                '#!/bin/sh\nprintf "%s\\n" "$MINERVA_ESCI_COL_FIGLIO" "$MINERVA_DENTRO"\n', True)
            generated = Path(directory) / 'recovery.sh'
            put(generated, bridge.render((ROOT / 'scripts/minerva-session-recupero').read_text(), str(root)), True)
            result = subprocess.run(['/bin/sh', str(generated)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), ['1', str(root / 'scripts/minerva-dentro-recupero')])

    def test_special_paths_are_literal_and_arguments_preserved(self):
        spec = importlib.util.spec_from_file_location('bridge', ROOT / 'scripts/liquid-session-bridge.py')
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)
        with tempfile.TemporaryDirectory() as directory:
            for leaf in ('plain', 'space & apostrophe\' $HOME `literal` | slash\\'):
                root = Path(directory) / leaf
                target = root / 'scripts/start-minerva-wayland.sh'
                put(target, '#!/bin/sh\nprintf "%s\\n" "$0" "$@"\n', True)
                template = (ROOT / 'scripts/minerva-session-wayland').read_text()
                generated = Path(directory) / 'bridge.sh'
                put(generated, bridge.render(template, str(root)), True)
                result = subprocess.run(['/bin/sh', str(generated), 'one two', '$three'],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(), [str(target), 'one two', '$three'])


class MailLauncherTests(unittest.TestCase):
    def test_menu_launcher_preserves_mailto_and_uses_existing_qml(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            launcher = root / 'scripts/minerva-posta'
            launcher.parent.mkdir()
            shutil.copyfile(ROOT / 'scripts/minerva-posta', launcher)
            put(root / 'minerva-shell/posta.qml')
            put(root / 'scripts/minerva-ambiente-app',
                'minerva_avvia_app() { printf "%s\\n" "$MINERVA_POSTA_APRI" "$@"; }\n')
            target = 'MailTo:person@example.org?subject=hello%20world&body=$literal'
            result = subprocess.run(['/bin/sh', str(launcher), target],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(),
                             [target, 'posta', 'qs', '-d', '-p', str(root / 'minerva-shell/posta.qml')])
            invalid = subprocess.run(['/bin/sh', str(launcher), '/tmp/file'],
                                     capture_output=True, text=True)
            self.assertEqual(invalid.returncode, 64)

    def test_daemon_bundle_and_runtime_checks_and_exit_status(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            launcher = root / 'scripts/minerva-posta-demone'
            launcher.parent.mkdir()
            shutil.copyfile(ROOT / 'scripts/minerva-posta-demone', launcher)
            run = lambda env: subprocess.run(['/bin/sh', str(launcher)], env=env, capture_output=True, text=True)
            env = {'PATH': '/usr/bin:/bin'}
            self.assertEqual(run(env).returncode, 1)
            bundle = root / 'posta/daemon/build/cli/bundle'
            put(bundle / 'bin/liquid_maild', '#!/bin/sh\nexit 75\n', True)
            put(bundle / 'lib/libsqlite3.so')
            self.assertEqual(run(env).returncode, 78)
            env['XDG_RUNTIME_DIR'] = directory
            self.assertEqual(run(env).returncode, 75)


class GuiProtocolTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('node'), 'Node is needed to exercise the QML JavaScript parser')
    def test_warnings_survive_completion_and_are_deduplicated(self):
        qml = (ROOT / 'minerva-shell/installer.qml').read_text()
        def function(name):
            start = qml.index('    function ' + name + '(')
            end = qml.index('\n    }', start) + len('\n    }')
            return qml[start:end]
        script = r'''
const vm = require('node:vm');
const assert = require('node:assert/strict');
const context = { app: {installWarnings:[],logText:'',logPath:'',currentManager:'',selectedManager:''},
                  Qt:{callLater:()=>{}},console };
vm.createContext(context);
vm.runInContext(SOURCE,context);
context.app.readinessText=context.readinessText;
context.addLog('@@MINERVA_WARNING@@mpv non disponibile');
context.addLog('@@MINERVA_WARNING@@mpv non disponibile');
context.addLog('@@MINERVA_STAGE@@Verifica');
context.addLog('@@MINERVA_LOG@@/tmp/installer.log');
context.finishChoice();
assert.equal(context.app.installWarnings.length,1);
assert.equal(context.app.stage,'Verifica');
assert.equal(context.app.logPath,'/tmp/installer.log');
assert.equal(context.app.step,4);
assert.match(context.app.resultText,/con limitazioni/);
'''
        source = '\n'.join(function(n) for n in ('addLog', 'readinessText', 'finishChoice'))
        result = subprocess.run([shutil.which('node'), '-e', script.replace('SOURCE', json.dumps(source))],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
